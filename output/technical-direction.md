# Technical Direction: voiceflow-local

## Direction Summary

Build `voiceflow-local` as a host-native CLI application with a long-running daemon for desktop interaction and a one-off execution path for batch or script usage. Use `whisper.cpp` as the default local speech-to-text backend. Treat LLM transformation as a pluggable OpenAI-compatible HTTP integration rather than a hard dependency on one runtime. Keep desktop-specific concerns behind adapters so Linux Wayland/X11 and macOS can share most of the application core.

The current repository already proves the Linux/Fedora path with a Bash installer, Wayland clipboard, PipeWire recording, and an `evdev`-based hold-to-record flow. v1 should preserve that path as the fastest route to a useful product, while reorganizing it into a maintainable multi-command architecture.

## Recommended v1 Technical Choices

1. Use Python for v1.
2. Prefer external OpenAI-compatible endpoint mode by default.
3. Keep `whisper.cpp` host-native and managed locally.
4. Add managed native LLM and Dockerized LLM as optional install modes, not the default.
5. Build a minimal separate overlay helper controlled over local IPC.

Rationale:

- The current project is Bash plus Python-oriented already.
- Python reduces time-to-delivery for CLI, process orchestration, adapters, metrics, and tests.
- Linux desktop integration via subprocesses and small helpers is straightforward in Python.
- macOS support remains feasible through platform-specific helpers without rewriting the core.
- External endpoint mode removes the highest-risk packaging dependency from the critical path.

## Architecture

Recommended structure:

```text
src/
  voiceflow_local/
    cli/
    app/
    config/
    daemon/
    state/
    hotkey/
    recording/
    stt/
    llm/
    clipboard/
    indicator/
    install/
    metrics/
    health/
    platform/
tests/
  unit/
  integration/
  e2e/
  compat/
  eval/
testdata/
docker/
scripts/
docs/
```

Core architectural rule:

- Desktop and backend integrations are adapter interfaces.
- Business flow and state transitions live in platform-agnostic core modules.

## Runtime Components

### CLI layer

Responsibilities:

- Parse commands and flags.
- Resolve config overrides.
- Dispatch to daemon control, one-off run, installer, test, bench, and doctor routines.

### Daemon

Responsibilities:

- Own the hotkey lifecycle.
- Coordinate recording, STT, transform, clipboard, and indicator updates.
- Expose status and control through PID/service files and lightweight local state.

### One-off runner

Responsibilities:

- Accept text, file, or timed recording input.
- Reuse the same STT and transform pipeline as daemon mode.
- Avoid any overlay or daemon coupling.

### Core pipeline

Pipeline after recording stop:

1. Finalize temp WAV
2. Run STT adapter
3. Optionally run LLM transform adapter
4. Copy to clipboard if requested
5. Emit metrics and result object

## State Machine

Use an explicit state machine in code:

```text
IDLE
RECORDING
STOPPING_RECORDING
TRANSCRIBING
TRANSFORMING
COPYING
DONE
ERROR
```

Benefits:

- Cleaner E2E assertions
- Safer indicator behavior
- Better error classification
- Easier metrics timing boundaries

## Adapter Boundaries

### Hotkey adapter

Interface:

- `start_listening()`
- `stop_listening()`
- callback or event stream for `hotkey_down`, `hotkey_up`

Linux implementations:

- `evdev` backend first
- future compositor- or portal-friendly alternatives later

macOS implementation:

- native event tap helper

Key behavior:

- ignore repeats
- debounce taps shorter than configured minimum
- enforce max recording duration

### Recorder adapter

Interface:

- `begin_recording() -> RecordingHandle`
- `stop_recording(handle) -> AudioCaptureResult`

Linux implementation:

- PipeWire via `pw-record`

macOS implementation:

- native helper or stable subprocess-backed recorder

Output contract:

- mono WAV
- default 16 kHz
- temp-file cleanup guaranteed

### STT adapter

Default implementation:

- `whisper.cpp` CLI invocation

Interface:

- `transcribe(audio_path, config) -> TranscriptResult`

Notes:

- parse CLI output into structured fields
- normalize whitespace
- capture stderr for diagnostics
- support thread count, language, model path, and optional GPU usage flags

### LLM adapter

Default implementation:

- OpenAI-compatible `/v1/chat/completions`

Interface:

- `transform(mode, transcript, config) -> TransformResult`

Requirements:

- configurable endpoint and model
- timeout support
- robust HTTP and JSON error mapping
- strict prompt templates per mode
- raw mode bypass

### Clipboard adapter

Linux:

- Wayland `wl-copy`
- X11 fallback `xclip` or `xsel`

macOS:

- `pbcopy`

Interface:

- `copy_text(text) -> None`

Rule:

- do not modify clipboard on failed pipeline runs

### Indicator adapter

Recommendation:

- separate helper process with local IPC

IPC commands:

- `show_recording`
- `show_processing`
- `show_success`
- `show_error`
- `hide`

Rationale:

- prevents focus stealing
- isolates platform-specific overlay behavior
- keeps daemon headless by default

## Configuration

Store config at:

```text
~/.config/voiceflow-local/config.yaml
```

Implementation direction:

- typed config schema with validation on load
- per-command overrides layered over file config
- write a generated default config during install
- fail early with actionable doctor output for invalid paths or endpoints

High-value config areas:

- app mode and latency thresholds
- hotkey key and backend
- recorder settings
- STT binary/model options
- LLM endpoint/model/timeout
- clipboard backend
- indicator enablement and position
- metrics path and privacy flags

## Packaging and Install Strategy

### Linux

v1 deliverables:

- Python package or binary archive
- single installer script
- user-level `systemd` service

Installer responsibilities:

- detect distro and commands
- install/check host packages
- discover or build `whisper.cpp`
- discover or download model files
- choose LLM mode
- write config
- install service
- run doctor checks

### macOS

v1 deliverables:

- CLI-first install path
- Homebrew-friendly packaging later

Installer must handle:

- accessibility permission guidance
- microphone permission guidance
- platform-specific helper installation

## Docker Strategy

Docker is a support tool, not the main desktop runtime.

Use Docker for:

- distro compatibility tests
- installer dry-runs
- fake STT/fake LLM integration tests
- optional local LLM server profile
- one-off non-interactive image

Do not treat Docker as a solution for:

- global hotkeys
- overlay
- live microphone capture
- clipboard integration

## Testing Plan

### Unit tests

Prioritize:

- CLI parsing
- config validation
- state transitions
- command construction for recorder/STT
- LLM request/response parsing
- clipboard backend selection
- indicator IPC protocol
- metrics serialization
- error classification

### Integration tests

Prioritize:

- `once --text` with fake LLM
- `once --file` with fake STT
- raw mode bypass
- clean mode prompt routing
- endpoint health checks
- indicator IPC interactions

### Host E2E

Required because desktop behavior is host-specific:

- daemon startup
- hotkey press/release
- recording start/stop
- indicator state changes
- clipboard success/failure behavior

### Docker compatibility

Run against:

- Fedora latest
- Fedora previous
- Ubuntu LTS
- Debian stable
- Arch

Artifacts:

- `results/compat-docker-report.md`
- `results/compat-docker-results.jsonl`

### Eval and bench

Bench outputs:

- `results/bench-summary.json`
- `results/bench-results.jsonl`
- `results/bench-report.md`

Eval dataset:

- `testdata/text_cases.jsonl`

Eval must use a configurable judge endpoint and model.

## Error Handling and Observability

Implement structured error classes for:

- missing dependency
- permission denied
- hotkey backend unavailable
- recording failure
- STT failure
- LLM timeout or HTTP failure
- clipboard failure
- indicator failure
- invalid config

Observability outputs:

- user-friendly CLI and doctor messages
- structured metrics JSONL
- recent daemon state for `status`
- service logs through `systemd` or foreground mode

## Migration From Current Prototype

The current `whisper-ptt-install.sh` and README establish useful defaults:

- Fedora-first assumptions
- Wayland clipboard via `wl-copy`
- `pw-record`
- input-group access for `evdev`
- `whisper.cpp` CLI invocation

Those should be retained as the initial Linux adapter path, but moved from a single generated script into a package with:

- stable module boundaries
- config file ownership
- service management commands
- explicit metrics and status reporting
- optional LLM transformation stage

## Open Questions Resolved For v1

1. Python v1 or Rust v1: Python.
2. Default LLM strategy: prefer external OpenAI-compatible endpoint first.
3. Overlay strategy: separate lightweight helper over local IPC.
4. Dockerized LLM GPU scope: CPU-first, document GPU as follow-up.
5. Multiple hotkeys: defer until after single-hotkey stability.
6. Direct insertion: defer until clipboard mode is stable.
7. Personal dictionary: defer from v1.

## Implementation Phases

Phase 1:

- package skeleton
- config loader
- one-off `--text` and `--file`
- STT and LLM adapters
- metrics

Phase 2:

- daemon
- Linux hotkey/recording/clipboard path
- indicator IPC and helper
- `status`, `doctor`, and installer refactor

Phase 3:

- Docker compatibility suite
- eval dataset and judge runner
- benchmarks
- macOS platform helpers

## Delivery Recommendation

Treat this as a Linux-first packaged CLI/daemon product with portable interfaces, not as a container-first app and not as a GUI app. The shortest credible v1 path is to harden the existing Fedora/Wayland approach, add one-off and LLM transform support, formalize the architecture, and only then extend the platform surface to macOS and richer install modes.
