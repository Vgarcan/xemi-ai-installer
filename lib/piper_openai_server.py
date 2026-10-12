#!/usr/bin/env python3
"""OpenAI-compatible text-to-speech endpoint for Open WebUI, backed by Piper voices.

Installed by xemi_ai_install.sh into the Piper venv and run as a hardened systemd service
on 127.0.0.1. Open WebUI's "OpenAI" TTS engine calls:

  POST {base}/audio/speech   {"input": "...", "voice": "...", "speed": 1.0}  -> audio/mpeg
  GET  {base}/audio/voices   -> {"voices": [{"id": ..., "name": ...}]}
  GET  {base}/audio/models   -> {"models": [{"id": "piper"}]}

Unknown voice names (for example OpenAI's "alloy") fall back to the default voice.
Configuration comes from the environment: PIPER_VOICES_DIR, PIPER_DEFAULT_VOICE,
PIPER_HOST, PIPER_PORT.
"""

import json
import math
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import lameenc
from piper import PiperVoice, SynthesisConfig

VOICES_DIR = os.environ.get("PIPER_VOICES_DIR", "/opt/piper-tts/voices")
DEFAULT_VOICE = os.environ.get("PIPER_DEFAULT_VOICE", "")
HOST = os.environ.get("PIPER_HOST", "127.0.0.1")
PORT = int(os.environ.get("PIPER_PORT", "8002"))
MAX_INPUT_CHARS = 10000
MAX_BODY_BYTES = 256 * 1024

_voices = {}
_voices_lock = threading.Lock()


def available_voices():
    return sorted(name[:-5] for name in os.listdir(VOICES_DIR) if name.endswith(".onnx"))


def voice_label(voice_id):
    # es_ES-davefx-medium -> "davefx (es_ES, medium)"
    parts = voice_id.split("-")
    if len(parts) == 3:
        return f"{parts[1]} ({parts[0]}, {parts[2]})"
    return voice_id


def resolve_voice(requested):
    voices = available_voices()
    if requested in voices:
        return requested
    if DEFAULT_VOICE in voices:
        return DEFAULT_VOICE
    if voices:
        return voices[0]
    raise RuntimeError(f"no Piper voices installed in {VOICES_DIR}")


def load_voice(voice_id):
    with _voices_lock:
        if voice_id not in _voices:
            _voices[voice_id] = PiperVoice.load(os.path.join(VOICES_DIR, voice_id + ".onnx"))
        return _voices[voice_id]


def synthesize_mp3(text, voice_id, speed):
    voice = load_voice(voice_id)
    # Piper's length_scale is the inverse of speed (smaller is faster).
    config = SynthesisConfig(length_scale=1.0 / min(max(speed, 0.25), 4.0))
    encoder = None
    mp3 = bytearray()
    for chunk in voice.synthesize(text, syn_config=config):
        if encoder is None:
            encoder = lameenc.Encoder()
            encoder.set_bit_rate(64)
            encoder.set_in_sample_rate(chunk.sample_rate)
            encoder.set_channels(chunk.sample_channels)
            encoder.set_quality(2)
        mp3 += encoder.encode(chunk.audio_int16_bytes)
    if encoder is not None:
        mp3 += encoder.flush()
    return bytes(mp3)


class Handler(BaseHTTPRequestHandler):
    server_version = "xemi-piper-tts/1"

    def log_message(self, fmt, *args):
        # One line per request in the journal, without the request body.
        print(f"{self.address_string()} {fmt % args}", flush=True)

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def route(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        return path[3:] if path.startswith("/v1") else path

    def do_GET(self):
        route = self.route()
        if route == "/health":
            self.send_json(200, {"status": "ok", "voices": len(available_voices())})
        elif route == "/audio/voices":
            self.send_json(200, {"voices": [{"id": v, "name": voice_label(v)} for v in available_voices()]})
        elif route in ("/audio/models", "/models"):
            models = [{"id": "piper", "name": "Piper"}]
            self.send_json(200, {"models": models, "data": models})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if self.route() != "/audio/speech":
            self.send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if length <= 0 or length > MAX_BODY_BYTES:
                self.send_json(413, {"error": "request body missing or too large"})
                return
            request = json.loads(self.rfile.read(length))
            if not isinstance(request, dict):
                raise ValueError("body must be a JSON object")
            speed = float(request.get("speed") or 1.0)
            if not math.isfinite(speed):
                raise ValueError("speed must be a number")
            text = str(request.get("input") or "").strip()
            if not text:
                self.send_json(400, {"error": "input is empty"})
                return
            if len(text) > MAX_INPUT_CHARS:
                self.send_json(413, {"error": f"input longer than {MAX_INPUT_CHARS} characters"})
                return
            voice_id = resolve_voice(str(request.get("voice") or ""))
            audio = synthesize_mp3(text, voice_id, speed)
        except (ValueError, TypeError) as err:
            self.send_json(400, {"error": f"bad request: {err}"})
            return
        except Exception as err:  # keep the service up; the journal keeps the reason
            print(f"synthesis failed: {err}", flush=True)
            self.send_json(500, {"error": "synthesis failed"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(audio)))
        self.end_headers()
        self.wfile.write(audio)


def main():
    voices = available_voices()
    print(f"Piper TTS on {HOST}:{PORT}, voices: {', '.join(voices) or 'none'}, default: {DEFAULT_VOICE}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
