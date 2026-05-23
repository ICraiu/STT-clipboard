# Product Specification: voiceflow-local

## Summary

`voiceflow-local` is a local-first push-to-talk dictation application for macOS and Linux. While the configured hotkey is held, the app records microphone audio, shows a small red recording indicator, transcribes the recording locally with `whisper.cpp`, optionally transforms the transcript through a local or user-provided OpenAI-compatible LLM endpoint, copies the final result to the clipboard, and then dismisses the indicator. The product also supports one-off CLI usage for file, text, and timed recording workflows without any desktop overlay.

The product extends the current Fedora/Wayland `whisper.cpp` clipboard prototype into a packaged, installable application with daemon mode, one-off mode, installer flows, metrics, compatibility tests, and cross-platform abstractions.

## Users and Jobs

Primary users:

- Developers and knowledge workers who want fast local dictation with strong privacy defaults.
- Linux desktop users, especially Fedora/Wayland users, who need a hold-to-record workflow.
- macOS users who want the same workflow without depending on a cloud speech service.

Primary jobs:

- Dictate text anywhere and paste the cleaned output immediately.
- Run one-off audio or text cleanup from the terminal.
- Choose between raw transcript output and LLM-cleaned or instruction-following output.
- Install the whole stack without manually wiring together `whisper.cpp`, models, services, and endpoints.

## Product Goals

- Deliver a local-first dictation flow that feels near-instant after hotkey release.
- Keep speech-to-text local by default through `whisper.cpp`.
- Support LLM transformation through any OpenAI-compatible endpoint, not one locked runtime.
- Package the system so non-expert users can install and operate it end-to-end.
- Provide a CLI and daemon architecture that works on Linux first and expands cleanly to macOS.

Non-goals for v1:

- Fully containerized desktop UX.
- Direct text insertion into focused apps.
- Multi-hotkey workflows.
- Personal dictionary and domain adaptation.
- Polished signed GUI app bundles.

## Core Experience

### Daemon mode

Command:

```bash
voiceflow-local start
```

Expected flow:

1. User holds the configured hotkey.
2. App shows a small red top-right indicator.
3. App records microphone audio until key release.
4. On release, the app stops recording and indicator switches to processing animation.
5. `whisper.cpp` produces a raw transcript.
6. If transform mode is enabled, the app sends the transcript to the configured OpenAI-compatible endpoint.
7. Final text is copied to the clipboard.
8. Indicator shows success briefly, then hides.
9. If the flow fails, the clipboard remains unchanged and the indicator flashes an error state.

### One-off mode

Commands:

```bash
voiceflow-local once --file ./audio.wav
voiceflow-local once --record 10s
voiceflow-local once --text "raw transcript here"
```

Requirements:

- No overlay or red circle.
- No daemon required.
- Print final output to stdout.
- Copy only when `--copy` is provided.
- Support `--json` for structured output.

## Command Surface

Primary binary:

```bash
voiceflow-local
```

Required commands:

- `install`
- `start`
- `stop`
- `restart`
- `status`
- `once`
- `test`
- `bench`
- `doctor`
- `config`

### `install`

Purpose:

- Detect platform and dependencies.
- Install or validate `whisper.cpp`.
- Install or validate Whisper model files.
- Configure LLM mode: managed native runtime, external endpoint, Dockerized LLM, or raw-only.
- Create default config.
- Install a per-user service where supported.
- Verify microphone, clipboard, hotkey, and transform endpoint readiness.

### `start`

Supported examples:

```bash
voiceflow-local start --foreground
voiceflow-local start --hotkey KEY_F8
voiceflow-local start --mode clean
voiceflow-local start --no-indicator
```

### `status`

Must report:

- Daemon running/stopped
- Hotkey and hotkey backend
- STT backend readiness
- Whisper model path
- LLM endpoint health
- Clipboard backend
- Indicator backend
- Last success timestamp
- Last error
- Recent latency summary if available

### `test`

Must support:

- unit
- integration
- host E2E
- Docker compatibility
- eval with configurable judge URL/model

## Modes

Transformation modes:

- `raw`
- `clean`
- `command`
- `rewrite`
- `translate-en`
- `translate-fr`
- `translate-ro`
- `principal-engineer`

Behavior:

- `raw` bypasses the LLM and returns transcript text.
- `clean` rewrites the transcript into polished written text without answering its content.
- `command` interprets dictated intent and writes the requested result directly.
- Other named modes map to different prompt templates and output expectations.

## Platforms

### Linux v1 priority

Primary Linux target:

- Fedora
- Wayland-first
- PipeWire recording
- `wl-copy` clipboard
- `notify-send` fallback notifications
- optional `evdev` hotkey backend

Secondary support:

- X11 via `xclip` or `xsel`
- Ubuntu, Debian, Arch through compatibility testing

### macOS v1 secondary target

Primary assumptions:

- Apple Silicon
- `pbcopy` clipboard
- native hotkey event tap
- native microphone access
- lightweight overlay helper

## Installation Modes

The product supports four install/runtime modes:

1. Host-native full install with local STT and managed local LLM runtime.
2. Host app with external OpenAI-compatible LLM endpoint.
3. Host app with Dockerized local LLM server.
4. Host app in raw-only mode with no LLM.

Recommended v1 default:

- Host-native app
- Host-native `whisper.cpp`
- External or managed OpenAI-compatible LLM endpoint
- Optional Dockerized LLM

This keeps the desktop integration on the host, where hotkeys, microphone access, clipboard, and overlay are practical.

## Privacy and Data Handling

Defaults:

- Do not store audio.
- Do not store transcripts or final text unless debug/eval mode is enabled.
- Store timings, sizes, success/failure, and model metadata in metrics logs.
- Keep all default processing local except optional user-configured LLM endpoints.

## Metrics and Quality

Each completed run should log:

- timestamp
- mode
- audio duration
- recording finalization latency
- STT latency
- LLM latency
- clipboard latency
- total post-release latency
- transcript/output sizes
- selected models
- success/failure
- error class

User-facing performance targets:

- 2-5 seconds speech: target under 2 seconds after release, acceptable under 4
- 10 seconds speech: target under 4 seconds, acceptable under 7
- 30 seconds speech: target under 10 seconds, acceptable under 15

## Testing and Validation Expectations

Required suites:

- Unit tests for parsing, config, state machine, adapters, metrics, and errors
- Integration tests for one-off flows and backend interactions
- Host E2E tests for real desktop behavior
- Docker compatibility tests for distro coverage
- Benchmark reporting
- LLM-as-judge evaluation with configurable OpenAI-compatible endpoint

## Acceptance Criteria

The product is acceptable for v1 when:

- `voiceflow-local start` launches a working daemon flow.
- Hold-to-record works with a visible recording indicator.
- Release triggers local transcription and optional transform.
- Final output is copied to clipboard on success.
- One-off `--file`, `--record`, and `--text` modes work without overlay.
- Installer is idempotent and supports dry-run.
- External and managed LLM configurations are supported.
- Docker compatibility testing runs without requiring real desktop integration.
- The eval dataset and benchmark reports exist and are runnable.

## Recommended v1 Scope

Ship first:

- Fedora-first host-native daemon and one-off CLI
- `whisper.cpp` local STT
- OpenAI-compatible transform endpoint support
- Clipboard output
- red recording/processing indicator
- `status` and `doctor`
- Docker compatibility tests
- eval runner and 200-case synthetic text dataset
- benchmark reporting

Ship after v1:

- macOS hardening
- managed `llama-server` install defaults
- optional Dockerized LLM profile
- direct text insertion
- personal dictionary
- multiple hotkeys mapped to different modes
