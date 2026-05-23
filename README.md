# Whisper Push-To-Talk Clipboard

Local hold-to-record dictation for Fedora/Wayland using `whisper.cpp`.

Hold the configured key, speak, then release. The app transcribes the audio locally, copies the text to the Wayland clipboard, and shows a short completion notification.

The default hotkey is `KEY_SCROLLLOCK`.

## Requirements

This setup expects:

- Fedora Workstation or another systemd Linux desktop
- Wayland
- PipeWire
- `whisper.cpp`
- a `whisper.cpp` GGML model file
- access to `/dev/input/event*` through the `input` group

The installer installs the runtime Fedora packages:

```bash
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
```

To build `whisper.cpp`, install build tools first:

```bash
sudo dnf install -y git cmake gcc gcc-c++ make
```

## Install Whisper.cpp

One expected layout is `~/llm/whisper.cpp`:

```bash
mkdir -p ~/llm
cd ~/llm
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
cmake -B build
cmake --build build -j"$(nproc)"
```

Confirm the CLI exists:

```bash
~/llm/whisper.cpp/build/bin/whisper-cli --help
```

## Install A Model

Recommended default:

```bash
cd ~/llm/whisper.cpp
bash ./models/download-ggml-model.sh large-v3-turbo
```

That should create:

```text
~/llm/whisper.cpp/models/ggml-large-v3-turbo.bin
```

Other `ggml-*.bin` models can also work. Use a smaller model if you need lower CPU or memory usage.

## Install This App

From this repo:

```bash
chmod +x whisper-ptt-install.sh
./whisper-ptt-install.sh
```

The installer creates:

- `~/bin/whisper-push-to-talk.py`
- `~/bin/whisper`
- `~/.config/systemd/user/whisper-push-to-talk.service`

It also adds your user to the `input` group if needed. If that happens, reboot before using the service. A simple service restart may not be enough because the already-running user systemd manager can keep the old group list.

Make sure `~/bin` is on your `PATH` if your shell does not already include it.

## Usage

Start the service:

```bash
whisper start
```

Check status:

```bash
whisper status
```

Stop the service:

```bash
whisper stop
```

Dictation flow:

```text
Hold Scroll Lock -> speak -> release Scroll Lock -> paste with Ctrl+V
```

On success, the transcription is copied to the clipboard and a short `Copied` notification is shown.

## Logs

Follow service logs:

```bash
journalctl --user -u whisper-push-to-talk.service -f
```

Show recent logs:

```bash
journalctl --user -u whisper-push-to-talk.service -n 80 --no-pager
```

## Troubleshooting

If status says `No keyboard devices found`, check group membership:

```bash
id
getent group input
```

Your user needs to be in the `input` group. If you were just added, reboot.

If clipboard copy does not work, confirm Wayland clipboard support:

```bash
command -v wl-copy
```

If notifications do not appear, confirm `notify-send` exists:

```bash
command -v notify-send
```

If recording fails, confirm PipeWire recording is available:

```bash
command -v pw-record
```
