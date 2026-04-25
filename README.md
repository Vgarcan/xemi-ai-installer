# Xemi AI Installer

Xemi AI Installer is a guided Linux installer for setting up a fresh AI server with Ollama, Open WebUI, NVIDIA GPU support, systemd autostart, LAN firewall access, installation state tracking, diagnostics, and clean uninstall/purge flows.

The goal is simple: a user who does not know where to start should be able to run one command and end up with a working local AI server.

## What It Sets Up

The full installer can prepare a new server end to end:

- Installs base tools such as `curl`, `wget`, `git`, `firewalld`, `jq`, `bc`, `pciutils`, and common diagnostic utilities.
- Enables EPEL and RPM Fusion repositories on supported `dnf`-based systems.
- Installs NVIDIA driver packages and CUDA runtime packages when the GPU is not ready.
- Installs Ollama using the official Ollama Linux installer.
- Configures Ollama as a systemd service with LAN binding and autostart.
- Configures Ollama GPU-related environment variables when NVIDIA GPUs are detected.
- Pulls recommended models based on detected VRAM.
- Installs Open WebUI as the official Python package inside a dedicated Python 3.11 virtual environment.
- Creates an Open WebUI systemd service with autostart.
- Creates LAN-only `firewalld` rich rules for Ollama and Open WebUI.
- Writes an installation manifest so uninstall and purge can remove what was created.
- Provides a `doctor` command to verify readiness after installation or reboot.

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

## Quick Start

Run the full new-server setup as root:

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
8. Pulls recommended models.
9. Installs Python 3.11 side-by-side.
10. Installs Open WebUI in a dedicated virtual environment.
11. Creates and enables the Open WebUI systemd service.
12. Opens LAN firewall access for Ollama and Open WebUI.
13. Runs `doctor` to confirm readiness.

If NVIDIA drivers are installed for the first time, a reboot may be required before the GPU becomes usable. After reboot, run:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install
```

The installer is designed to continue from the server's current state.

## Interactive Menu

To open the interactive menu:

```bash
sudo /usr/local/bin/xemi_ai_install.sh
```

Or explicitly:

```bash
sudo /usr/local/bin/xemi_ai_install.sh menu
```

For a new server, use:

```text
1) Full new server setup
```

The menu also exposes individual operations such as installing drivers, installing the AI stack, configuring firewall rules, checking services, running diagnostics, uninstalling, and purging.

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

Show recorded installer state:

```bash
sudo /usr/local/bin/xemi_ai_install.sh state
```

Show listening ports and service status:

```bash
sudo /usr/local/bin/xemi_ai_install.sh status
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
--ai-user USER               Set the service user.
--ai-group GROUP             Set the service group.
--openwebui-package PACKAGE  Set the pip package, for example open-webui==0.7.2.
--ollama-version VERSION     Set OLLAMA_VERSION for the official Ollama installer.
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
- Writes `CUDA_VISIBLE_DEVICES=<gpu-uuid-list>` to the Ollama systemd override.
- Enables `OLLAMA_FLASH_ATTENTION=1`.
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

Firewall rules are stored in the installer manifest so they can be removed later by `uninstall` or `purge`.

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

## Open WebUI Details

Open WebUI is installed as the official Python package:

```bash
pip install -U open-webui
```

The systemd service starts it with:

```bash
python -m open_webui serve
```

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
```

The service unit is:

```bash
/etc/systemd/system/openwebui.service
```

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

## Diagnostics

Run:

```bash
sudo /usr/local/bin/xemi_ai_install.sh doctor
```

The doctor check verifies:

- Required commands are available.
- NVIDIA GPU is visible through `nvidia-smi`.
- Ollama has GPU-related systemd environment settings.
- Recent Ollama logs include CUDA/GPU-related signals when available.
- `ollama` is enabled for autostart.
- `ollama` is running.
- Ollama API responds at `/api/tags`.
- `openwebui` is enabled for autostart.
- `openwebui` is running.
- Open WebUI responds at `/health`.
- firewalld rules recorded by the installer still exist.

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
- Ollama binaries and libraries discovered by the installer.
- Ollama model data.
- firewalld rules recorded in the manifest.
- Created AI user/group if the installer created them.
- Installer manifest.

Before removing important paths, the installer attempts to save backups in:

```bash
/var/lib/xemi-ai/backups
```

## Troubleshooting

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

### Ollama is not responding

Check:

```bash
systemctl status ollama --no-pager
journalctl -u ollama -e --no-pager
curl -fsS http://127.0.0.1:11434/api/tags
```

If you changed the Ollama port, use your configured port.

### Open WebUI is not responding

Check:

```bash
systemctl status openwebui --no-pager
journalctl -u openwebui -e --no-pager
cat /etc/xemi-ai/openwebui.env
curl -fsS http://127.0.0.1:3000/health
```

If you changed the Open WebUI port, use your configured port.

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
- It is designed for `dnf` systems. Other Linux families need a dedicated package-management branch before they should be considered supported.
