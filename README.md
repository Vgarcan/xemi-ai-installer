# Xemi AI Installer

Xemi AI Installer is a guided Linux installer for setting up a fresh AI server with Ollama, Open WebUI, NVIDIA GPU support, systemd autostart, LAN firewall access, detailed installed configuration reporting, diagnostics, and clean uninstall/purge flows.

The goal is simple: a user who does not know where to start should be able to run one command and end up with a working local AI server.

## Project Structure

xemi_ai_install.sh is the starter and command entry point. Its implementation is split by responsibility under lib/:

- config.sh: default paths and environment-backed settings.
- common.sh: logging, terminal output, prompts, and command wrappers.
- state.sh: lock handling and the installation manifest.
- validation.sh: input/configuration validation and safe path operations.
- system.sh: host checks, repositories, base tools, users, and NVIDIA drivers.
- ollama.sh: Ollama installation, configuration, models, and GPU integration.
- openwebui.sh: Python/Open WebUI installation, updates, and health checks.
- extras.sh: optional Open WebUI tools (Open Terminal, mcpo, SearXNG, Apache Tika).
- services.sh: status table and control (start/stop/restart, boot, logs, analysis) for managed systemd services.
- owui_api.sh: Open WebUI admin API client that connects and disconnects the tools.
- network.sh: LAN firewall and service binding operations.
- lifecycle.sh: uninstall and purge cleanup.
- diagnostics.sh: reports and readiness checks.
- workflows.sh: high-level install, repair, and bootstrap flows.
- cli.sh: menu, argument parsing, and command dispatch.

Keep the lib/ directory alongside the starter when copying or installing the tool.

## Verification

Run the non-destructive smoke tests from the repository with:

```bash
bash tests/smoke.sh
```

They cover argument validation, manifest round-tripping, guarded deletions, and the non-zero failure contract of `doctor`. They do not install packages or start services.
GitHub Actions also runs Bash syntax checks and these smoke tests on pushes and pull requests. Test an actual update and rollback on a disposable supported Linux VM before using them on a production server.

## What It Sets Up

The full installer can prepare a new server end to end:

- Installs base tools such as `curl`, `wget`, `git`, `firewalld`, `jq`, `bc`, `pciutils`, and common diagnostic utilities.
- Enables EPEL and RPM Fusion repositories on supported `dnf`-based systems.
- Installs NVIDIA driver packages and CUDA runtime packages when the GPU is not ready.
- Installs Ollama using the official Ollama Linux installer.
- Configures Ollama as a systemd service with localhost API binding by default and autostart.
- Configures Ollama GPU-related environment variables when NVIDIA GPUs are detected.
- Adds basic systemd hardening for the managed Ollama override and Open WebUI service.
- Offers recommended model sets based on detected VRAM, with an option to skip model downloads.
- Installs Open WebUI as the official Python package inside a dedicated Python 3.11 virtual environment.
- Creates an Open WebUI systemd service with autostart.
- Creates a LAN `firewalld` rule for Open WebUI; the Ollama API rule is opt-in.
- Writes an installation manifest so uninstall and purge can remove what was created.
- Uses a single-run lock to prevent concurrent installer runs from changing the same state.
- Provides a `doctor` command to verify readiness after installation or reboot, returning a non-zero exit code when readiness checks fail.

## Supported Systems

This installer currently targets Linux distributions that use:

- `dnf`
- `systemd`
- `firewalld`

Typical targets are:

- AlmaLinux
- Rocky Linux
- RHEL-compatible systems
- Fedora-like systems

The installer checks for `dnf` and `systemctl` before running installation flows. If your system uses `apt`, `apk`, `zypper`, or another package manager, this installer is not currently intended for that environment.

## Download From GitHub

On a fresh supported server, install the small tools needed to download the repository first:

```bash
sudo dnf install -y git curl ca-certificates
```

Clone the repository into `/usr/local/xemi-ai-installer`:

```bash
sudo git clone https://github.com/Vgarcan/xemi-ai-installer.git /usr/local/xemi-ai-installer
```

Make the installer executable and create the compatibility command:

```bash
sudo chmod +x /usr/local/xemi-ai-installer/xemi_ai_install.sh
sudo ln -sf /usr/local/xemi-ai-installer/xemi_ai_install.sh /usr/local/bin/xemi_ai_install.sh
```

Run a dry run before changing the server:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --dry-run
```

Then run the full installer:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

To update an existing clone later:

```bash
cd /usr/local/xemi-ai-installer
sudo git pull --ff-only
sudo chmod +x xemi_ai_install.sh
```

### Download Without Git

If you prefer not to clone the repository, install `curl` and download the files directly from GitHub:

```bash
sudo dnf install -y curl ca-certificates
sudo mkdir -p /usr/local/xemi-ai-installer
sudo curl -fsSL -o /usr/local/xemi-ai-installer/xemi_ai_install.sh \
  https://raw.githubusercontent.com/Vgarcan/xemi-ai-installer/main/xemi_ai_install.sh
sudo curl -fsSL -o /usr/local/xemi-ai-installer/README.md \
  https://raw.githubusercontent.com/Vgarcan/xemi-ai-installer/main/README.md
sudo chmod +x /usr/local/xemi-ai-installer/xemi_ai_install.sh
sudo ln -sf /usr/local/xemi-ai-installer/xemi_ai_install.sh /usr/local/bin/xemi_ai_install.sh
```

After downloading without Git, run:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --dry-run
```

## Quick Start

After downloading the repository, run the full new-server setup as root:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

This is the recommended path for a new server. It performs the full flow:

1. Checks supported system requirements.
2. Installs base tools.
3. Enables required repositories.
4. Checks NVIDIA GPU readiness with `nvidia-smi`.
5. Installs NVIDIA driver packages if the GPU is not ready.
6. Installs Ollama.
7. Configures Ollama for LAN access, GPU usage, and autostart.
8. Offers recommended model sets and optionally pulls selected models.
9. Installs Python 3.11 side-by-side.
10. Installs Open WebUI in a dedicated virtual environment.
11. Creates and enables the Open WebUI systemd service.
12. Opens LAN firewall access for Ollama and Open WebUI.
13. Runs `doctor` to confirm readiness.

If NVIDIA drivers are installed for the first time, a reboot may be required before the GPU becomes usable.

When the installer asks whether to reboot:

- Answer `yes` on a fresh NVIDIA driver installation unless you have a specific reason not to.
- If the server reboots, SSH back in and run the same install command again.
- The installer is designed to continue from the server's current state.
- If you answer `no`, the installer will try to continue only if `nvidia-smi` already works. If the GPU is still not ready, reboot and rerun the installer.

After reboot, run:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

If you are using unattended mode, rerun the unattended command you originally intended, for example:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --yes
```

## Interactive Menu

To open the interactive menu:

```bash
sudo /usr/local/bin/xemi_ai_install.sh
```

Or explicitly:

```bash
sudo /usr/local/bin/xemi_ai_install.sh menu
```

The main menu groups operations into submenus. Each line lists what the submenu contains:

```text
 1) Guided installation  full setup / repair, NVIDIA drivers, AI stack
 2) Ollama               install, LAN service, status, health check, remove
 3) Models               storage directory, install, list, test, remove
 4) Open WebUI           Python 3.11, install, updates, rollback, health check
 5) Open WebUI tools     Open Terminal, MCP tools, web search, document extraction
 6) Network              LAN firewall, ports and service bindings
 7) Services             status and ports, start/stop/restart, logs, GPU, diagnostics
 8) Diagnostics          GPU info, doctor check, installation report
 9) Uninstall            remove stack (keep Ollama data), purge to zero

 0) Exit
```

For a new server, choose `1` and then `1) Full new server setup`. In every submenu, `0` returns to the main menu.

## Existing Installations

If you run `install` on a host where Ollama or Open WebUI already exists, the installer now detects that state instead of treating it like a blank machine.

It offers two safe paths:

- Exit without making changes.
- Repair and verify the existing installation.

The repair flow:

- Verifies NVIDIA GPU readiness.
- Reapplies the managed Ollama and Open WebUI service settings.
- Rechecks Ollama runtime libraries.
- Restarts Ollama and verifies that it bootstraps with CUDA instead of CPU when the GPU is available.
- Installs a boot-time GPU guard that can restart Ollama once if it comes up in CPU mode even though NVIDIA is ready.
- Runs the normal health checks.

You can also call repair directly:

```bash
sudo /usr/local/bin/xemi_ai_install.sh repair
```

## Dry Run

Use `--dry-run` before touching a real server. It prints the resolved plan and exits without installing packages, creating users, changing systemd units, writing firewall rules, creating the manifest, or writing logs.

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --dry-run
```

Example with explicit settings:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --dry-run \
  --ollama-port 11434 \
  --webui-port 3000 \
  --lan 192.168.2.0/24 \
  --ollama-bind-host 0.0.0.0 \
  --openwebui-package open-webui \
  --ollama-version 0.5.7
```

This is useful for reviewing what the installer would do before running it for real.

## Unattended Mode

Use `--yes` to skip pauses and use default answers or values provided through CLI options:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --yes
```

Example with explicit settings:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --yes \
  --ollama-port 11434 \
  --webui-port 3000 \
  --lan 192.168.2.0/24
```

For safety, `--yes` does not automatically reboot after installing NVIDIA drivers. To allow automatic reboot:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --yes --reboot
```

If `--yes` installs NVIDIA drivers without `--reboot`, the installer stops before the stack is complete when the GPU is not immediately usable. Reboot manually and rerun:

```bash
sudo reboot
sudo /usr/local/bin/xemi_ai_install.sh install --yes
```

## Commands

Full new-server setup:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

Install only the NVIDIA driver stage:

```bash
sudo /usr/local/bin/xemi_ai_install.sh drivers
```

Install only the AI stack, assuming drivers are already working:

```bash
sudo /usr/local/bin/xemi_ai_install.sh stack
```

Run readiness checks:

```bash
sudo /usr/local/bin/xemi_ai_install.sh doctor
```

Show the detailed installed configuration report:

```bash
sudo /usr/local/bin/xemi_ai_install.sh state
```

`report` and `info` are aliases for the same command.

This report reads the current server configuration and shows the installed services, users, model path, Open WebUI data path, endpoints, firewall rules, GPU details, health checks, Open WebUI users, and API-key/token metadata. Sensitive values such as passwords, hashes, API keys, tokens, and secret keys are not printed.

Show listening ports and service status:

```bash
sudo /usr/local/bin/xemi_ai_install.sh status
```

Configure or migrate the Ollama model storage directory:

```bash
sudo /usr/local/bin/xemi_ai_install.sh models-dir
```

Check and apply Open WebUI updates:

```bash
sudo /usr/local/bin/xemi_ai_install.sh openwebui-check
sudo /usr/local/bin/xemi_ai_install.sh openwebui-update
```

Restore the previous release and its matching data snapshot if needed:

```bash
sudo /usr/local/bin/xemi_ai_install.sh openwebui-rollback
```

Remove services and Open WebUI while keeping Ollama binaries and model data:

```bash
sudo /usr/local/bin/xemi_ai_install.sh uninstall
```

Reset everything the installer manages:

```bash
sudo /usr/local/bin/xemi_ai_install.sh purge
```

Show help:

```bash
/usr/local/bin/xemi_ai_install.sh --help
```

## CLI Options

Options can be combined with commands:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --yes \
  --ollama-port 11434 \
  --webui-port 3000 \
  --lan 192.168.2.0/24
```

Supported options:

```text
-y, --yes                    Use defaults and skip pauses.
-n, --dry-run                Print the resolved plan without changing the system.
--ollama-port PORT           Set the Ollama port.
--webui-port PORT            Set the Open WebUI port.
--lan CIDR                   Set the LAN subnet allowed by firewalld.
--firewall-zone ZONE         Choose a firewalld zone when more than one is active.
--expose-ollama             Bind the Ollama API to all IPv4 interfaces.
--ollama-bind-host HOST      Set the Ollama bind host (IPv4 address or DNS name).
--ollama-models-dir PATH     Set a custom Ollama model storage directory.
--ai-user USER               Set the service user.
--ai-group GROUP             Set the service group.
--openwebui-package PACKAGE  Set the pip package, for example open-webui==0.7.2.
--ollama-version VERSION     Set OLLAMA_VERSION for the official Ollama installer.
--ollama-install-sha256 SUM  Verify the downloaded Ollama installer script.
--allow-cpu-fallback         Allow installation without confirmed NVIDIA GPU.
--reboot                     Allow automatic reboot after driver installation in --yes mode.
-h, --help                   Show help.
```

## Version Pinning

By default, the installer uses the latest Open WebUI package available to `pip` and the default version selected by the official Ollama installer.

You can pin Open WebUI:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --openwebui-package open-webui==0.7.2
```

You can pin Ollama:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ollama-version 0.5.7
```

You can also verify the downloaded Ollama installer script when you have a trusted SHA256 digest:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ollama-install-sha256 <64-character-sha256>
```

If no installer checksum is provided, the script warns and relies on HTTPS transport for the official Ollama installer.

You can combine both:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --openwebui-package open-webui==0.7.2 \
  --ollama-version 0.5.7
```

Pinning is useful when you need reproducible deployments or when a newer upstream release introduces a regression.

## Python Policy

Many RHEL-like Linux systems ship Python 3.9 as part of the operating system. That Python installation is often used by system tools and package management.

This installer does not modify:

```bash
/usr/bin/python3
```

It also does not change global `alternatives`, shell aliases, or the default system Python.

Instead, Open WebUI uses Python 3.11 installed side-by-side:

```bash
/usr/bin/python3.11
```

The installer creates a dedicated virtual environment:

```bash
/opt/open-webui-venv
```

This keeps Open WebUI isolated from the operating system. If Open WebUI needs to be repaired or reinstalled, the venv can be removed and recreated without touching Linux's system Python.

Summary:

```text
System Python 3.9: left untouched for the OS.
Python 3.11: dedicated to Open WebUI.
Ollama: independent from Python.
```

## GPU Behavior

The installer is designed to make Ollama use NVIDIA GPU acceleration whenever possible.

During Ollama configuration it:

- Checks `nvidia-smi`.
- Reads NVIDIA GPU UUIDs when available.
- Verifies Ollama runtime libraries, including CUDA libraries when NVIDIA is present.
- Enables NVIDIA persistence when available.
- Enables `OLLAMA_FLASH_ATTENTION=1`.
- Sets `OLLAMA_KEEP_ALIVE=30m` so recently used models stay loaded longer.
- Lets Ollama discover visible CUDA devices automatically.
- Restarts the Ollama service.

If the GPU is not ready, the installer fails instead of silently installing a CPU-only setup.

To allow CPU fallback intentionally:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --allow-cpu-fallback
```

Or with an environment variable:

```bash
sudo ALLOW_CPU_FALLBACK=1 /usr/local/bin/xemi_ai_install.sh install
```

The `doctor` command also checks recent Ollama logs for CUDA/GPU-related signals. If no model has been run yet, the logs may not show GPU usage. In that case, run a model and then run `doctor` again.

When CPU fallback is selected, the full install and repair flows skip the NVIDIA driver requirement and configure Ollama without the GPU startup wait. This is intended for servers that deliberately run models on CPU.

## Ports And Firewall

Default ports:

```text
Ollama:      11434
Open WebUI: 3000
LAN subnet: 192.168.2.0/24
```

Change ports and LAN subnet through CLI options:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ollama-port 11434 \
  --webui-port 3000 \
  --lan 192.168.1.0/24
```

Or set the LAN subnet through an environment variable:

```bash
sudo LAN_SUBNET=192.168.1.0/24 /usr/local/bin/xemi_ai_install.sh install
```

Firewall rules are stored in the installer manifest so they can be removed later by `uninstall` or `purge`. Reconfiguring the firewall replaces the previously recorded Ollama and Open WebUI rules, rather than leaving the old LAN subnet or ports open.

Ollama binds to `127.0.0.1` by default. Open WebUI can reach it locally, while LAN clients cannot access the Ollama API directly. To expose the API to the configured LAN, opt in explicitly:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --expose-ollama --lan 192.168.1.0/24
```

You can also use `--ollama-bind-host HOST`. The firewall rule is added only when Ollama is not bound to localhost. If multiple firewalld zones are active, select the correct one with `--firewall-zone ZONE`. Review existing firewall rules independently: this installer does not remove rules created outside Xemi.

Open WebUI listens on all IPv4 interfaces; its built-in HTTP endpoint has no TLS termination. Put a properly configured HTTPS reverse proxy in front of it before exposing it beyond a trusted LAN.

IPv6 bind addresses are not currently supported by `--ollama-bind-host`; use an IPv4 address or DNS name.

## Users And Permissions

Default service identity:

```text
AI_USER=aiuser
AI_GROUP=aiuser
```

Change it with CLI options:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ai-user openai \
  --ai-group openai
```

Or with environment variables:

```bash
sudo AI_USER=openai AI_GROUP=openai /usr/local/bin/xemi_ai_install.sh install
```

If the installer creates the user or group, it records that fact in the manifest. `purge` only removes the user/group if the manifest says the installer created them.

## Ollama Model Downloads

During the stack installation, the installer detects available VRAM and offers model sets. Any set you install also pulls `qwen2.5:0.5b` (about 0.4 GB), the Open WebUI task model.

Example on a 12 GB GPU:

```text
1) mistral llama3 phi3
2) mistral deepseek-coder phi3
3) phi3 mistral
4) Do not install models now
5) custom
```

Choose:

- Option `1` for a general starter set.
- Option `2` when you also want a coding-oriented model.
- Option `3` to install fewer models.
- `Do not install models now` to finish the stack without downloading models.
- `custom` to type model names manually.

The installer shows `ollama pull` output while models download. Model downloads can take time and several GB of disk space. With the default Xemi service user, Ollama model data is stored under:

```bash
/home/aiuser/.ollama/models
```

Useful checks while a model is downloading:

```bash
ps -ef | grep "ollama pull" | grep -v grep
du -sh /home/aiuser/.ollama
```

After installation, list installed models with:

```bash
sudo -u aiuser ollama list
```

You can install models later with:

```bash
sudo -u aiuser ollama pull mistral
```

## Ollama Model Memory

The installer sets two Ollama defaults for every model:

| Setting | Default | Why |
|---|---|---|
| `OLLAMA_CONTEXT_LENGTH` | `16384` | Without it Ollama picks 4096 on a 12 GB GPU, which is too small for web search results and documents and makes long requests fail ("exceeds the available context size"). |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | Halves the K/V cache versus `f16` with negligible quality loss. Requires flash attention, which the installer always enables. |

Change them from `2) Ollama > Tune model memory`, with `sudo /usr/local/bin/xemi_ai_install.sh ollama-tune`, or at install time with `--ollama-context-length N` and `--ollama-kv-cache-type f16|q8_0|q4_0`. Applying restarts Ollama. The values are stored in the manifest, so repair keeps them.

Ollama loads several models at once when they fit in VRAM and unloads the oldest when a new one does not. Count VRAM, not file size: each loaded model adds its K/V cache, compute buffer and CUDA context. Check real usage in `7) Services > GPU usage`. Keep every single model below the free VRAM; a model that does not fit runs partly on the CPU and becomes much slower.

## Ollama Model Storage

By default, with the Xemi service user, Ollama stores model data under:

```bash
/home/aiuser/.ollama/models
```

If you want to store models on another disk, such as an SSD mounted under `/mnt/ai-ssd`, configure a custom model directory:

```bash
sudo /usr/local/bin/xemi_ai_install.sh models-dir
```

Or set it during install:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ollama-models-dir /mnt/ai-ssd/ollama-models
```

The installer will:

- Create the target directory.
- Set ownership for the AI service user.
- Show the filesystem for the target path with `df -h`.
- Verify that the AI service user can write to the target path.
- Optionally copy existing model data from the previous directory.
- Write `OLLAMA_MODELS=<path>` into the Ollama systemd override.
- Restart Ollama.
- Verify that the Ollama API responds and run `ollama list`.

Paths must be absolute and should not contain spaces. Good examples:

```text
/mnt/ai-ssd/ollama-models
/srv/ollama-models
/data/ollama/models
```

## Open WebUI Details

Open WebUI is installed as the official Python package:

```bash
pip install -U open-webui
```

The systemd service starts it with:

```bash
open-webui serve --host 0.0.0.0 --port 3000
```

On first start, Open WebUI may download embedding assets into its cache before the web port starts responding. The installer waits for `/health`, but on slow connections this may still take several minutes.

A new installation starts with these defaults, written to `/etc/xemi-ai/openwebui.env`:

| Setting | Value | Why |
|---|---|---|
| `TASK_MODEL` | `qwen2.5:0.5b` | Titles, tags and search queries run on a small model instead of queueing on the chat model. If it is not pulled, Open WebUI uses the chat model. |
| `RAG_EMBEDDING_MODEL` | `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | Multilingual document search (Spanish included), on the CPU so it does not compete for VRAM. |
| `RAG_TOP_K` / `WEB_SEARCH_RESULT_COUNT` | `5` / `5` | More context per answer, sized for the 16k Ollama context. |

Open WebUI reads these only on its first start and then keeps its own settings in its database, so existing installations are not changed. For an existing installation use `4) Open WebUI > Apply recommended settings` (all but the embedding model, which needs re-indexing of your documents).

Persistent data is stored in:

```bash
/var/lib/open-webui
```

The environment file is:

```bash
/etc/xemi-ai/openwebui.env
```

It contains values such as:

```text
PORT=3000
DATA_DIR=/var/lib/open-webui
OLLAMA_BASE_URL=http://127.0.0.1:11434
UVICORN_WORKERS=1
XDG_CACHE_HOME=/var/lib/open-webui/cache
HF_HOME=/var/lib/open-webui/cache/huggingface
SENTENCE_TRANSFORMERS_HOME=/var/lib/open-webui/cache/sentence-transformers
TRANSFORMERS_CACHE=/var/lib/open-webui/cache/transformers
```

The service unit is:

```bash
/etc/systemd/system/openwebui.service
```

## Open WebUI Tools

Menu group `5) Open WebUI tools` installs optional free and open-source tools that extend Open WebUI. Each one is installed natively (no containers), runs as a hardened systemd service, and listens on `127.0.0.1` only. Open WebUI calls them from its backend, so no firewall rules are added.

How to use the tools in Open WebUI, with diagrams, for users and administrators (Spanish): [docs/GUIA_HERRAMIENTAS.md](docs/GUIA_HERRAMIENTAS.md).

| Tool | Command | Port | What it adds | Service user |
|---|---|---|---|---|
| Open Terminal | `open-terminal` | 8000 | Shell, file browser and code execution for models | `aiterminal` |
| mcpo | `mcpo` | 8001 | MCP servers `time` and `fetch` as OpenAPI tool servers | `aitools` |
| SearXNG | `searxng` | 8888 | Private web search without paid APIs | `aitools` |
| Apache Tika | `tika` | 9998 | PDF/Word/Excel text extraction for documents and RAG | `aitools` |

```bash
sudo /usr/local/bin/xemi_ai_install.sh searxng
sudo /usr/local/bin/xemi_ai_install.sh tools-status
sudo /usr/local/bin/xemi_ai_install.sh tools-update
```

### Connecting the tools to Open WebUI

Open WebUI keeps these settings in its database, where environment variables no longer apply after the first start. The installer therefore connects the tools through Open WebUI's admin API:

- After each install it asks "Connect ... to Open WebUI now". `5) Open WebUI tools > Connect installed tools to Open WebUI` (or `tools-connect`) connects or refreshes all installed tools at once.
- It asks for an Open WebUI administrator e-mail and password for that step only. They are never stored; the session token stays in memory and is not visible in the process list.
- Only entries created by the installer (ids starting with `xemi-`) are added, refreshed or removed. Your own connections are kept, and so are access grants you gave to the installer's entries. New Open Terminal and tool server connections are admin-only until you grant groups access.
- Before writing, it checks that each API response has the expected shape. If Open WebUI changed its API, nothing is written and the manual values below are shown.
- Unattended runs (`--yes`) skip this step.

`4) Open WebUI > Apply recommended settings` sets the task model to `qwen2.5:0.5b`, and documents Top K and web search results to 5, through the same API. It does not change the embedding model, because that requires re-indexing your documents.

Manual values, also printed by `tools-status`:

- Open Terminal: Admin settings > Integrations > Open Terminal, URL `http://127.0.0.1:8000`, Bearer key from `/etc/xemi-ai/open-terminal.env`. Set Function Calling to Native in the model settings.
- mcpo: Admin settings > Integrations > Manage Tool Servers, one OpenAPI connection per server (`http://127.0.0.1:8001/time`, `http://127.0.0.1:8001/fetch`), Bearer key from `/etc/xemi-ai/mcpo.env`. Add more MCP servers in `/etc/mcpo/config.json`.
- SearXNG: Admin settings > Web Search, engine `searxng`, query URL `http://127.0.0.1:8888/search?q=<query>`.
- Apache Tika: Admin settings > Documents, Content Extraction Engine `Tika`, URL `http://127.0.0.1:9998`.

Security notes:

- Every tool service runs with an extra sandbox drop-in (`/etc/systemd/system/<tool>.service.d/xemi-hardening.conf`): no capabilities, private `/dev`, system-call filter, restricted namespaces and address families. Verified with all four tools; `systemd-analyze security` drops from 7.4 (MEDIUM) to 1.5 (OK). `Update installed tools` applies it to existing installs.

- Open Terminal lets connected models run commands as `aiterminal`. That user has no sudo, sees the system read-only, can write only to `/var/lib/open-terminal`, cannot see `/home` or other users' processes. It can still read world-readable files and reach the network.
- mcpo accepts its API key only as a command-line argument. The tool services run with `ProtectProc=invisible`, so the Open Terminal user cannot see other users' processes or that key; other local login users can still see it in the process list.
- SearXNG follows the upstream main branch; the installed commit is recorded in the manifest, and `tools-update` returns to the previous commit if the new one fails to install or start. Apache Tika is pinned to a release verified by SHA512 and uses Java 21 from the distribution.

### Removing tools without leaving traces

`Remove tools` (and `uninstall`/`purge`) leave the server as it was before the tool was installed:

- The service, its unit, venv or jar, configuration directory and API key file.
- The `aiterminal`/`aitools` users, their groups and home directories, once no installed tool needs them (only users this installer created).
- System packages the tool installed (Java 21 for Tika, git for SearXNG if it was missing). The installer records exactly which RPMs each install added and removes them only if `rpm -e --test` confirms nothing else needs them now; otherwise it keeps them and says so.
- Its manifest entries. Python packages are installed with `--no-cache-dir`, so nothing is added to root's pip cache.

The one exception is user work: if the Open Terminal workspace (`/var/lib/open-terminal`) contains files beyond the shell skeleton, history and Open Terminal logs, the installer asks before deleting it (default: keep) and keeps `aiterminal` as their owner. `purge` deletes it without asking.

Removing tools also offers to delete their Open WebUI connections with one admin login: Open Terminal and mcpo entries are removed, and web search or content extraction are set back to Open WebUI's defaults, but only while they still point to this installer's tools. If you skip that step, each removal prints where to delete the connection by hand. `purge` skips it when it deletes the Open WebUI data itself. The only thing left outside the installer's reach is the systemd journal, which rotates on its own.

Running `Remove tools` with no tools installed also cleans up service users left behind by older versions of this installer.

## Open WebUI Updates

Open WebUI can be updated through the installer:

```bash
sudo /usr/local/bin/xemi_ai_install.sh openwebui-update
```

`openwebui-check` is read-only and reports the installed and available versions. `openwebui-update` requires a Xemi-managed installation. It prepares a separate virtual environment, checks dependencies, stops the service, copies the full data directory (including the database), activates the candidate, then verifies the service and `/health`. If startup fails, it restores the previous environment and data snapshot automatically. A successful update records both paths for `openwebui-rollback`. Keep enough free space for the complete data copy plus 100 MiB; the service is unavailable while the data is copied and the update is activated.

The rollback command restores the matching data snapshot, so changes made after the update will be lost. Back up newer data separately first. Package checks use the configured pip index, while candidate installation uses isolated pip settings; private/custom indexes require an explicit packaging plan. A healthy `/health` response does not prove every user workflow or database migration is compatible: test logins, chats, and models before treating an upgrade as production-ready.

## Paths

Installer directory:

```bash
/usr/local/xemi-ai-installer
```

Main script:

```bash
/usr/local/xemi-ai-installer/xemi_ai_install.sh
```

Compatibility symlink:

```bash
/usr/local/bin/xemi_ai_install.sh
```

Installer manifest:

```bash
/var/lib/xemi-ai/manifest.env
```

Backups:

```bash
/var/lib/xemi-ai/backups
```

Installer log:

```bash
/var/log/xemi-ai/install.log
```

Open WebUI venv:

```bash
/opt/open-webui-venv
```

Open WebUI data:

```bash
/var/lib/open-webui
```

Open WebUI env:

```bash
/etc/xemi-ai/openwebui.env
```

Ollama systemd override:

```bash
/etc/systemd/system/ollama.service.d/override.conf
```

## Services

Menu group `7) Services` shows and controls every systemd unit the installer creates or relies on: `ollama`, `xemi-ollama-gpu-guard`, `openwebui`, the installed Open WebUI tools, `nvidia-persistenced` and `firewalld`. Units that do not exist on the host are not listed.

- Show status of all services: state, start at boot, PID, memory, automatic restarts, error log lines in the last 24 hours, HTTP health and start time. Problem rows are shown in yellow or red. Also available as `sudo /usr/local/bin/xemi_ai_install.sh services`.
- Manage a service: start, stop, restart (with a health check), enable or disable at boot, browse or follow the log, errors since the last boot, the unit file with its overrides, and `systemd-analyze security` exposure analysis. Stopping or disabling asks for confirmation and explains the impact (for example, stopping `firewalld` removes the LAN-only protection).
- Restart AI services: restarts Ollama, Open WebUI and the tools in order and checks that each one responds.
- GPU usage (`gpu` command): utilization, memory, temperature and power per GPU, VRAM used by each service, and the models loaded in Ollama with how much of each runs on the GPU.
- Boot timeline: total boot time, how long each managed service took to start, and what Ollama and Open WebUI waited for.
- Export diagnostic bundle (`diag-bundle` command): status, versions, doctor, install report, ports, firewall, unit files and last-boot logs of every service, plus the installer log, in `/var/lib/xemi-ai/diagnostics/xemi-diag-<host>-<time>.tar.gz` (mode 600). API keys, tokens, passwords and e-mail addresses are redacted; review it before sharing.

The status table also lists the TCP addresses each service listens on (`LISTEN`), read from the processes in the service's cgroup, so it shows the real port even if it was changed during installation.

## Diagnostics

Run:

```bash
sudo /usr/local/bin/xemi_ai_install.sh doctor
```

The doctor check verifies:

- Required commands are available.
- NVIDIA GPU is visible through `nvidia-smi`.
- Ollama runtime libraries are present.
- Recent Ollama logs include CUDA/GPU-related signals when available.
- `ollama` is enabled for autostart.
- `ollama` is running.
- Ollama API responds at `/api/tags`.
- `openwebui` is enabled for autostart.
- `openwebui` is running.
- Open WebUI responds at `/health`.
- firewalld rules recorded by the installer still exist.
- Ollama runs with the context length and K/V cache recorded in the manifest (warning: run `ollama-tune`).
- Ollama bind address (warning when it listens on all interfaces).
- Each installed Open WebUI tool is running, responds, and has its hardening drop-in (warning: run `tools-update`).

Warnings do not make the doctor fail; they point to settings worth reviewing.

Useful manual checks:

```bash
systemctl status ollama --no-pager
systemctl status openwebui --no-pager
curl -fsS http://127.0.0.1:11434/api/tags
curl -fsS http://127.0.0.1:3000/health
firewall-cmd --list-rich-rules
journalctl -u ollama -e --no-pager
journalctl -u openwebui -e --no-pager
```

## Reboot Validation

After a successful installation, a good production check is:

```bash
sudo reboot
```

After the server comes back:

```bash
sudo /usr/local/bin/xemi_ai_install.sh doctor
```

This confirms that both services start automatically and remain reachable after boot.

## Uninstall

To remove services and Open WebUI while keeping Ollama binaries and model data:

```bash
sudo /usr/local/bin/xemi_ai_install.sh uninstall
```

This removes or disables:

- Open WebUI service.
- Open WebUI virtual environment.
- Open WebUI environment file.
- Xemi-created Ollama systemd override.
- firewalld rules recorded in the manifest.

It keeps:

- Ollama binary.
- Ollama model data.
- Open WebUI persistent data, unless using `purge`.

## Purge

To reset the stack to zero:

```bash
sudo /usr/local/bin/xemi_ai_install.sh purge
```

When applicable, `purge` removes:

- Open WebUI service.
- Open WebUI venv.
- Open WebUI data.
- Open WebUI environment file.
- Ollama systemd override.
- Ollama service file.
- Ollama binary recorded as created by Xemi, plus its standard libraries and model data when installation ownership was recorded.
- firewalld rules recorded in the manifest.
- Open WebUI tools (Open Terminal, mcpo, SearXNG, Apache Tika), including the Open Terminal workspace.
- Created AI user/group and the `aiterminal`/`aitools` users if the installer created them.
- Installer manifest and `/etc/xemi-ai`.

Before removing important paths, the installer saves backups in the directory below. `purge` keeps these backups and the log in `/var/log/xemi-ai`; delete both manually once you no longer need them:

```bash
/var/lib/xemi-ai/backups
```

The installer preserves pre-existing Open WebUI data, external services, and Ollama binaries that it cannot prove it created. For older installations without ownership markers, inspect and remove leftovers manually after taking a backup. `--yes` skips optional model downloads; pull models later with `ollama pull MODEL`.

## Troubleshooting

### Installer lock is active

The installer uses a single-run lock at:

```bash
/var/lib/xemi-ai/install.lock
```

Do not run the installer with `source`. Run it as a command:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

If you see `Another installer run is already active`, check which process owns the lock:

```bash
sudo fuser -v /var/lib/xemi-ai/install.lock
```

If the owner is an old interactive shell from a previous sourced run, close that terminal or run this inside that same terminal:

```bash
exec 9>&-
```

### GPU is not detected

Check:

```bash
nvidia-smi
```

If NVIDIA drivers were just installed, reboot and run the installer again:

```bash
sudo reboot
sudo /usr/local/bin/xemi_ai_install.sh install
```

### Installer rebooted before Ollama was installed

On a fresh server, the full install may install NVIDIA drivers first and ask for a reboot before installing Ollama and Open WebUI. If this happens, `ollama` may not exist yet. This is expected.

After the reboot, continue with:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

or, if you were using unattended mode:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --yes
```

The installer will detect that drivers are already installed and continue with Ollama, model selection, Open WebUI, firewall rules, and diagnostics.

### Ollama is not responding

Check:

```bash
systemctl status ollama --no-pager
journalctl -u ollama -e --no-pager
systemctl show ollama -p Environment --no-pager
curl -fsS http://127.0.0.1:11434/api/tags
```

If you changed the Ollama port, use your configured port.

If `command -v ollama` returns nothing, Ollama has not been installed yet. Continue the installer:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

If you changed the model directory, confirm the `OLLAMA_MODELS` path exists and is owned by the AI service user:

```bash
sudo ls -la /path/to/ollama-models
sudo chown -R aiuser:aiuser /path/to/ollama-models
```

### Open WebUI is not responding

Check:

```bash
systemctl status openwebui --no-pager
journalctl -u openwebui -e --no-pager
cat /etc/xemi-ai/openwebui.env
test -x /opt/open-webui-venv/bin/open-webui
curl -fsS http://127.0.0.1:3000/health
```

If you changed the Open WebUI port, use your configured port.

On first start, Open WebUI may download embedding assets into `/var/lib/open-webui/cache` before it opens the port. You can check progress with:

```bash
du -sh /var/lib/open-webui/cache
journalctl -u openwebui -f
```

### Firewall access does not work from LAN

Check:

```bash
systemctl status firewalld --no-pager
firewall-cmd --list-rich-rules
sudo /usr/local/bin/xemi_ai_install.sh state
```

Confirm the configured LAN subnet matches your real network.

### Open WebUI package installation fails

Check that Python 3.11 exists:

```bash
/usr/bin/python3.11 --version
```

Then inspect pip output in the installer log:

```bash
cat /var/log/xemi-ai/install.log
```

You can also pin a known working package version:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install --openwebui-package open-webui==0.7.2
```

## Operational Notes

- The script is intentionally conservative about GPU: by default it fails if GPU readiness cannot be confirmed.
- It does not replace or modify the operating system's default Python.
- It uses systemd services so Ollama and Open WebUI survive reboot.
- It records installer-created resources in a manifest for safer cleanup.
- It loads only supported manifest keys instead of sourcing arbitrary manifest contents.
- It refuses recursive deletion outside the managed path prefixes used by the installer.
- It is designed for `dnf` systems. Other Linux families need a dedicated package-management branch before they should be considered supported.
