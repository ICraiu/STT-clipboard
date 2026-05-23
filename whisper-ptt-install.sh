#!/usr/bin/env bash
set -euo pipefail

# whisper-ptt-install.sh
#
# End-to-end installer for local push-to-talk dictation using whisper.cpp on Fedora/Wayland.
#
# What it installs/configures:
#   - Fedora packages: python3-evdev, wl-clipboard, libnotify, pipewire-utils, etc.
#   - Adds current user to the input group if needed
#   - Creates ~/bin/whisper-push-to-talk.py
#   - Creates ~/bin/whisper
#   - Creates ~/.config/systemd/user/whisper-push-to-talk.service
#   - Optionally enables/starts the service
#
# Expected flow after install:
#   hold configured key  -> record microphone
#   release key          -> run whisper.cpp
#                       -> copy transcription to clipboard
#                       -> show desktop notification
#
# Run:
#   chmod +x whisper-ptt-install.sh
#   ./whisper-ptt-install.sh

# -------------------------
# Helpers
# -------------------------

info() {
  printf "\n\033[1;34m==>\033[0m %s\n" "$*"
}

warn() {
  printf "\n\033[1;33mWARN:\033[0m %s\n" "$*"
}

err() {
  printf "\n\033[1;31mERROR:\033[0m %s\n" "$*" >&2
}

ask_default() {
  local prompt="$1"
  local default="$2"
  local answer=""

  read -r -p "$prompt [$default]: " answer
  if [[ -z "$answer" ]]; then
    printf "%s" "$default"
  else
    printf "%s" "$answer"
  fi
}

ask_yes_no_default_yes() {
  local prompt="$1"
  local answer=""

  read -r -p "$prompt [Y/n]: " answer
  case "${answer,,}" in
    n|no) return 1 ;;
    *) return 0 ;;
  esac
}

ask_yes_no_default_no() {
  local prompt="$1"
  local answer=""

  read -r -p "$prompt [y/N]: " answer
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Missing command: $1"
    exit 1
  fi
}

# -------------------------
# Preflight
# -------------------------

if [[ "${EUID}" -eq 0 ]]; then
  err "Do not run this script as root. Run it as your normal user. It will call sudo when needed."
  exit 1
fi

USER_NAME="$(id -un)"
USER_HOME="${HOME}"

info "Installing push-to-talk dictation for user: ${USER_NAME}"

if [[ -f /etc/fedora-release ]]; then
  info "Fedora detected: $(cat /etc/fedora-release)"
else
  warn "This script is designed for Fedora. It may still work on other systemd/Wayland Linux systems, but package install commands may fail."
fi

require_command sudo
require_command systemctl

# -------------------------
# Install packages
# -------------------------

info "Installing required packages"

sudo dnf install -y \
  python3 \
  python3-evdev \
  wl-clipboard \
  libnotify \
  pipewire-utils \
  alsa-utils \
  ffmpeg \
  procps-ng \
  findutils \
  grep \
  sed \
  coreutils

# -------------------------
# Locate whisper.cpp
# -------------------------

DEFAULT_WHISPER_DIR="${USER_HOME}/llm/whisper.cpp"
WHISPER_DIR="$(ask_default "Path to whisper.cpp directory" "$DEFAULT_WHISPER_DIR")"

if [[ ! -d "$WHISPER_DIR" ]]; then
  err "Directory not found: $WHISPER_DIR"
  echo "Build whisper.cpp first, or rerun this script with the correct path."
  exit 1
fi

DEFAULT_WHISPER_BIN="${WHISPER_DIR}/build/bin/whisper-cli"
WHISPER_BIN="$(ask_default "Path to whisper-cli binary" "$DEFAULT_WHISPER_BIN")"

if [[ ! -x "$WHISPER_BIN" ]]; then
  err "whisper-cli is not executable or not found: $WHISPER_BIN"
  echo "Check:"
  echo "  ls ${WHISPER_DIR}/build/bin"
  exit 1
fi

# Find model candidates.
MODEL_CANDIDATES=()
while IFS= read -r -d '' f; do
  MODEL_CANDIDATES+=("$f")
done < <(find "${WHISPER_DIR}/models" -maxdepth 1 -type f \( -name "ggml-*.bin" -o -name "*.bin" \) -print0 2>/dev/null || true)

DEFAULT_MODEL="${WHISPER_DIR}/models/ggml-large-v3-turbo.bin"
if [[ ! -f "$DEFAULT_MODEL" && "${#MODEL_CANDIDATES[@]}" -gt 0 ]]; then
  DEFAULT_MODEL="${MODEL_CANDIDATES[0]}"
fi

info "Detected model files"
if [[ "${#MODEL_CANDIDATES[@]}" -gt 0 ]]; then
  for m in "${MODEL_CANDIDATES[@]}"; do
    echo "  - $m"
  done
else
  warn "No model files found under ${WHISPER_DIR}/models"
fi

WHISPER_MODEL="$(ask_default "Path to Whisper model" "$DEFAULT_MODEL")"

if [[ ! -f "$WHISPER_MODEL" ]]; then
  err "Model not found: $WHISPER_MODEL"
  echo "Example download from whisper.cpp:"
  echo "  cd ${WHISPER_DIR}"
  echo "  bash ./models/download-ggml-model.sh large-v3-turbo"
  exit 1
fi

# -------------------------
# Choose config
# -------------------------

HOTKEY="$(ask_default "Hold-to-record key" "KEY_SCROLLLOCK")"
LANGUAGE="$(ask_default "Language: auto, en, ro, fr, etc." "auto")"
THREADS="$(ask_default "Whisper threads" "16")"
SAMPLE_RATE="$(ask_default "Recording sample rate" "16000")"

DEFAULT_MIN_SECONDS="0.35"
MIN_SECONDS="$(ask_default "Minimum recording length in seconds" "$DEFAULT_MIN_SECONDS")"

info "Configuration"
cat <<EOF
  whisper.cpp dir:     $WHISPER_DIR
  whisper-cli:         $WHISPER_BIN
  model:               $WHISPER_MODEL
  hotkey:              $HOTKEY
  language:            $LANGUAGE
  threads:             $THREADS
  sample rate:         $SAMPLE_RATE
  min recording sec:   $MIN_SECONDS
EOF

if ! ask_yes_no_default_yes "Continue with this configuration?"; then
  err "Cancelled."
  exit 1
fi

# -------------------------
# input group
# -------------------------

info "Checking input group access"

if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "input"; then
  info "User is already in input group"
  NEED_RELOGIN=0
else
  warn "User is not in input group. Adding ${USER_NAME} to input group."
  sudo usermod -aG input "$USER_NAME"
  NEED_RELOGIN=1
fi

# -------------------------
# Validate user session basics
# -------------------------

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
  warn "XDG_SESSION_TYPE is '${XDG_SESSION_TYPE:-unset}', not 'wayland'."
  warn "wl-copy is Wayland-oriented. If you are on X11, replace wl-copy with xclip/xsel in the generated script."
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  warn "DBUS_SESSION_BUS_ADDRESS is not set. notify-send may not work outside a graphical session."
fi

# -------------------------
# Create daemon script
# -------------------------

info "Writing daemon script"

mkdir -p "${USER_HOME}/bin"

PTT_SCRIPT="${USER_HOME}/bin/whisper-push-to-talk.py"

cat > "$PTT_SCRIPT" <<PYEOF
#!/usr/bin/env python3
import os
import sys
import time
import signal
import tempfile
import subprocess
from pathlib import Path
from select import select

from evdev import InputDevice, categorize, ecodes, list_devices


# =========================
# CONFIG
# =========================

WHISPER_DIR = Path(${WHISPER_DIR@Q})
WHISPER_BIN = Path(${WHISPER_BIN@Q})
WHISPER_MODEL = Path(${WHISPER_MODEL@Q})

HOTKEY = ${HOTKEY@Q}
LANGUAGE = ${LANGUAGE@Q}
THREADS = ${THREADS@Q}
MIN_SECONDS = float(${MIN_SECONDS@Q})
SAMPLE_RATE = ${SAMPLE_RATE@Q}

# Copy command for Wayland.
CLIPBOARD_CMD = ["wl-copy"]

# Notification command. Timeout is in milliseconds.
NOTIFY_CMD = ["notify-send", "-t", "200"]


# =========================
# HELPERS
# =========================

def notify(title: str, body: str = ""):
    try:
        subprocess.run(
            NOTIFY_CMD + [title, body],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except Exception:
        pass


def copy_to_clipboard(text: str):
    subprocess.run(
        CLIPBOARD_CMD,
        input=text.encode("utf-8"),
        check=True,
    )


def keycode_matches(keycode) -> bool:
    if isinstance(keycode, list):
        return HOTKEY in keycode
    return keycode == HOTKEY


def find_keyboard_devices():
    devices = []

    for path in list_devices():
        try:
            dev = InputDevice(path)
            caps = dev.capabilities()
            keys = caps.get(ecodes.EV_KEY, [])

            # Real keyboard heuristic.
            if ecodes.KEY_A in keys and ecodes.KEY_SPACE in keys:
                devices.append(dev)
        except PermissionError:
            pass
        except Exception:
            pass

    return devices


def transcribe(audio_path: str) -> str:
    cmd = [
        str(WHISPER_BIN),
        "-m", str(WHISPER_MODEL),
        "-f", audio_path,
        "-l", LANGUAGE,
        "-t", THREADS,
        "-nt",
        "-np",
    ]

    result = subprocess.run(
        cmd,
        cwd=str(WHISPER_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if result.returncode != 0:
        stderr = result.stderr.strip()
        raise RuntimeError(stderr if stderr else "whisper-cli failed")

    text = result.stdout.strip()

    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return " ".join(lines).strip()


def start_recording(output_path: str):
    cmd = [
        "pw-record",
        "--rate", SAMPLE_RATE,
        "--channels", "1",
        "--format", "s16",
        output_path,
    ]

    return subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        preexec_fn=os.setsid,
    )


def stop_recording(proc):
    if proc is None:
        return

    if proc.poll() is None:
        os.killpg(os.getpgid(proc.pid), signal.SIGINT)

        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            proc.wait(timeout=2)


def validate():
    missing = []

    if not WHISPER_BIN.exists():
        missing.append(str(WHISPER_BIN))
    elif not os.access(WHISPER_BIN, os.X_OK):
        missing.append(str(WHISPER_BIN) + " is not executable")

    if not WHISPER_MODEL.exists():
        missing.append(str(WHISPER_MODEL))

    for binary in ["pw-record", "wl-copy", "notify-send"]:
        if subprocess.run(["which", binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
            missing.append(binary)

    if missing:
        print("Missing requirements:", file=sys.stderr)
        for item in missing:
            print(f"  - {item}", file=sys.stderr)
        sys.exit(1)


# =========================
# MAIN
# =========================

def main():
    validate()

    devices = find_keyboard_devices()

    if not devices:
        print("No keyboard devices found.", file=sys.stderr)
        print("Likely fix:", file=sys.stderr)
        print('  sudo usermod -aG input "\$USER"', file=sys.stderr)
        print("Then log out and log back in.", file=sys.stderr)
        notify("Whisper dictation error", "No keyboard devices found")
        sys.exit(1)

    print("Whisper dictation ready.")
    print(f"Hotkey: {HOTKEY}")
    print("Listening on:")
    for dev in devices:
        print(f"  {dev.path}: {dev.name}")
    print()

    recording = False
    record_proc = None
    record_started_at = 0.0
    current_wav = None

    while True:
        readable, _, _ = select(devices, [], [])

        for dev in readable:
            for event in dev.read():
                if event.type != ecodes.EV_KEY:
                    continue

                key = categorize(event)

                if not keycode_matches(key.keycode):
                    continue

                # 0 = release, 1 = press, 2 = repeat/hold
                if key.keystate == 1 and not recording:
                    fd, current_wav = tempfile.mkstemp(prefix="whisper-ptt-", suffix=".wav")
                    os.close(fd)

                    recording = True
                    record_started_at = time.time()
                    record_proc = start_recording(current_wav)

                    print("Recording...")

                elif key.keystate == 0 and recording:
                    elapsed = time.time() - record_started_at

                    print("Stopping...")
                    stop_recording(record_proc)

                    recording = False
                    record_proc = None

                    if elapsed < MIN_SECONDS:
                        print("Ignored short tap.")
                        try:
                            os.remove(current_wav)
                        except Exception:
                            pass
                        continue

                    try:
                        print("Transcribing...")

                        text = transcribe(current_wav)

                        if text:
                            copy_to_clipboard(text)
                            print(f"Copied: {text}")
                            notify("Copied")
                        else:
                            print("No speech detected.")
                            notify("No speech")

                    except Exception as exc:
                        print(f"Error: {exc}", file=sys.stderr)
                        notify("Whisper dictation error", str(exc)[:180])

                    finally:
                        try:
                            os.remove(current_wav)
                        except Exception:
                            pass


if __name__ == "__main__":
    main()
PYEOF

chmod +x "$PTT_SCRIPT"

info "Created: $PTT_SCRIPT"

# -------------------------
# Create CLI
# -------------------------

info "Writing CLI"

CLI_SCRIPT="${USER_HOME}/bin/whisper"

cat > "$CLI_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SERVICE="whisper-push-to-talk.service"

usage() {
  cat <<USAGE
Usage:
  whisper status
  whisper start
  whisper stop
USAGE
}

if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  status)
    systemctl --user status "$SERVICE" --no-pager
    ;;
  start)
    systemctl --user reset-failed "$SERVICE" >/dev/null 2>&1 || true
    systemctl --user enable --now "$SERVICE"
    ;;
  stop)
    systemctl --user stop "$SERVICE"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
EOF

chmod +x "$CLI_SCRIPT"

info "Created: $CLI_SCRIPT"

# -------------------------
# Create systemd service
# -------------------------

info "Writing systemd user service"

mkdir -p "${USER_HOME}/.config/systemd/user"

SERVICE_FILE="${USER_HOME}/.config/systemd/user/whisper-push-to-talk.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Whisper push-to-talk dictation
After=graphical-session.target pipewire.service

[Service]
Type=simple
ExecStart=${PTT_SCRIPT}
Restart=always
RestartSec=2
Environment=PATH=/usr/local/bin:/usr/bin:/bin:${USER_HOME}/bin

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload

info "Created: $SERVICE_FILE"

# -------------------------
# Optional service enable
# -------------------------

if [[ "$NEED_RELOGIN" -eq 1 ]]; then
  warn "You were added to the input group."
  warn "You must log out and log back in before the daemon can read keyboard events."
  warn "After logging back in, run:"
  echo
  echo "  systemctl --user enable --now whisper-push-to-talk.service"
  echo "  journalctl --user -u whisper-push-to-talk.service -f"
  echo
else
  if ask_yes_no_default_yes "Enable and start the user service now?"; then
    systemctl --user enable --now whisper-push-to-talk.service

    info "Service started"
    echo "Check logs:"
    echo "  journalctl --user -u whisper-push-to-talk.service -f"
  else
    info "Service not started"
    echo "Manual start:"
    echo "  systemctl --user enable --now whisper-push-to-talk.service"
  fi
fi

# -------------------------
# Smoke tests / final output
# -------------------------

info "Smoke checks"

if command -v wl-copy >/dev/null 2>&1; then
  echo "ok: wl-copy found"
else
  warn "wl-copy not found"
fi

if command -v notify-send >/dev/null 2>&1; then
  echo "ok: notify-send found"
else
  warn "notify-send not found"
fi

if command -v pw-record >/dev/null 2>&1; then
  echo "ok: pw-record found"
else
  warn "pw-record not found"
fi

echo "ok: whisper-cli = $WHISPER_BIN"
echo "ok: model       = $WHISPER_MODEL"

info "Done"

cat <<EOF

Usage:
  Hold ${HOTKEY}, speak, release.
  The transcription is copied to your clipboard.
  Paste with Ctrl+V.

Run manually:
  ${PTT_SCRIPT}

CLI commands:
  whisper status
  whisper start
  whisper stop

Logs:
  journalctl --user -u whisper-push-to-talk.service -f

Edit generated daemon:
  nano ${PTT_SCRIPT}

EOF
