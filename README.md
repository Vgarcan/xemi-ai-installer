# Xemi AI Installer

Xemi AI Installer is a guided Linux installer for setting up a fresh AI server with Ollama, Open WebUI, NVIDIA GPU support, systemd autostart, LAN firewall access, detailed installed configuration reporting, diagnostics, and clean uninstall/purge flows.

The goal is simple: a user who does not know where to start should be able to run one command and end up with a working local AI server.

## What It Sets Up

The full installer can prepare a new server end to end:

- Installs base tools such as `curl`, `wget`, `git`, `firewalld`, `jq`, `bc`, `pciutils`, and common diagnostic utilities.
- Enables EPEL and RPM Fusion repositories on supported `dnf`-based systems.
- Installs NVIDIA driver packages and CUDA runtime packages when the GPU is not ready.
- Installs Ollama using the official Ollama Linux installer.
- Configures Ollama as a systemd service with LAN binding and autostart.
- Configures Ollama GPU-related environment variables when NVIDIA GPUs are detected.
- Adds basic systemd hardening for the managed Ollama override and Open WebUI service.
- Offers recommended model sets based on detected VRAM, with an option to skip model downloads.
- Installs Open WebUI as the official Python package inside a dedicated Python 3.11 virtual environment.
- Creates an Open WebUI systemd service with autostart.
- Creates LAN-only `firewalld` rich rules for Ollama and Open WebUI.
- Writes an installation manifest so uninstall and purge can remove what was created.
- Uses a single-run lock to prevent concurrent installer runs from changing the same state.
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

For a new server, use:

```text
1) Full new server setup
```

The menu also exposes individual operations such as installing drivers, installing the AI stack, configuring firewall rules, checking services, running diagnostics, uninstalling, and purging.

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
sudo /usr/local/bin/xemi_ai_install.sh openwebui-update
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
--ollama-bind-host HOST      Set the Ollama bind host.
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

Ollama binds to `0.0.0.0` by default so LAN clients can reach it through the firewall rules. To bind it differently:

```bash
sudo /usr/local/bin/xemi_ai_install.sh install \
  --ollama-bind-host 127.0.0.1
```

If you bind Ollama to localhost only, LAN clients will not be able to reach the Ollama API directly.

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

During the stack installation, the installer detects available VRAM and offers model sets.

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

## Open WebUI Updates

Open WebUI can be updated through the installer:

```bash
sudo /usr/local/bin/xemi_ai_install.sh openwebui-update
```

The update flow:

- Reads the currently installed `open-webui` version from `/opt/open-webui-venv`.
- Checks PyPI through `pip list --outdated`.
- Shows the available version change when an update exists.
- Stops `openwebui` before upgrading.
- Runs `pip install -U open-webui` inside the existing virtual environment.
- Reapplies the SQLite compatibility shim used on Alma/RHEL systems.
- Rewrites the Open WebUI environment and systemd service with the managed settings.
- Restarts `openwebui`.
- Waits for `http://127.0.0.1:3000/health` to respond.

If no update is reported, the command still repairs/verifies the managed service settings and runs the health check.

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
- Ollama runtime libraries are present.
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
