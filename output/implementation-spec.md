# Implementation Specification: voiceflow-local

## 1. Purpose

This specification translates the approved product scope and technical direction into an implementable v1 plan for `voiceflow-local`. The goal is to move from the current Fedora/Wayland prototype to a packaged Python application that supports:

- daemon mode with hold-to-record hotkey behavior
- one-off CLI runs for text, file, and timed recording inputs
- local speech-to-text through `whisper.cpp`
- transcript transformation through a configurable OpenAI-compatible endpoint
- clipboard output and a lightweight recording/processing indicator
- installer, doctor, status, test, benchmark, and evaluation workflows

The implementation must preserve the fastest proven path from the current repository: Linux host-native execution, `whisper.cpp` CLI integration, PipeWire recording, and clipboard-first output.

## 2. Delivery Scope

### In scope for v1

- Python package with `voiceflow-local` CLI entrypoint
- Linux-first daemon mode on Fedora/Wayland
- one-off `once --file`, `once --record`, and `once --text`
- `raw`, `clean`, and `command` modes as first-class supported modes
- prompt-template support for the remaining named modes
- host-native `whisper.cpp` management and invocation
- configurable external OpenAI-compatible LLM endpoint
- optional raw-only mode with no LLM dependency
- clipboard adapters for Wayland, X11 fallback, and macOS
- indicator helper with local IPC and no focus stealing
- metrics logging, status reporting, and doctor checks
- Docker-based compatibility test harness
- eval runner using configurable OpenAI-compatible judge endpoint
- 200-case synthetic text eval dataset

### Deferred from v1

- polished signed app bundle
- full macOS parity for every desktop integration path
- default managed `llama-server` install path
- AMD GPU Docker acceleration
- direct text insertion into the focused app
- multiple hotkeys per mode
- personal dictionary

## 3. Implementation Principles

1. Keep desktop integration on the host. Docker is a support tool, not the interactive runtime.
2. Isolate platform-specific behavior behind adapters with stable interfaces.
3. Reuse one core pipeline for daemon and one-off execution.
4. Prefer explicit state transitions and structured result objects over ad hoc subprocess glue.
5. Preserve privacy defaults by not storing audio or transcript content outside debug and eval paths.
6. Make failure modes inspectable through status, doctor, metrics, and logs.

## 4. Target Repository Shape

```text
voiceflow-local/
  pyproject.toml
  README.md
  src/voiceflow_local/
    cli/
    app/
    config/
    daemon/
    state/
    platform/
    hotkey/
    recording/
    stt/
    llm/
    clipboard/
    indicator/
    metrics/
    install/
    doctor/
    status/
    testing/
  tests/
    unit/
    integration/
    e2e/
    compat/
    eval/
    fixtures/
  testdata/
    text_cases.jsonl
    audio/
  docker/
    fedora/
    ubuntu/
    debian/
    arch/
    llm-server/
  scripts/
  docs/
  output/
```

## 5. Module Responsibilities

### `cli/`

Owns argument parsing and command dispatch.

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

Preferred implementation:

- `argparse` or `typer`; choose the simplest option that supports subcommands, JSON output, and testable command handlers
- one handler module per command
- command handlers return process exit code integers and structured result payloads where appropriate

### `config/`

Owns config schema, default generation, load/merge logic, and validation.

Implementation details:

- store config in `~/.config/voiceflow-local/config.yaml`
- define a typed settings model
- support precedence order: defaults < config file < environment overrides < CLI flags
- expand `~` and env vars during load
- validate file paths, URLs, enum-like mode names, numeric thresholds, and backend names

### `app/`

Owns the reusable pipeline shared by daemon mode and one-off mode.

Primary objects:

- `PipelineRequest`
- `PipelineResult`
- `TranscriptResult`
- `TransformResult`
- `ClipboardResult`
- `RunMetrics`

Responsibilities:

- orchestrate record -> transcribe -> transform -> copy flow
- handle mode-specific behavior
- enforce clipboard write only on success
- emit metrics and normalized errors

### `daemon/`

Owns the long-running desktop process and service integration.

Responsibilities:

- initialize config and adapters
- subscribe to hotkey events
- manage in-memory state machine
- coordinate indicator lifecycle
- persist minimal status snapshot for `status`
- expose PID and runtime metadata through state files

### `state/`

Owns the explicit runtime state machine.

States:

- `IDLE`
- `RECORDING`
- `STOPPING_RECORDING`
- `TRANSCRIBING`
- `TRANSFORMING`
- `COPYING`
- `DONE`
- `ERROR`

Implementation details:

- state transition table in one module
- attach timing markers at each transition boundary
- reject illegal transitions and classify them as internal errors

### `platform/`

Owns OS detection, path conventions, dependency probing, and service helpers.

Key abstractions:

- `PlatformInfo`
- `ServiceManager`
- `PathProvider`
- `DependencyProbe`

### `hotkey/`

Owns global press-and-hold detection.

v1 implementations:

- Linux `evdev` backend
- macOS backend stub or helper-backed implementation behind the same interface

Contract:

- emit `hotkey_down` once when the configured key is pressed
- emit `hotkey_up` once when released
- ignore repeats
- support minimum press duration and maximum record duration

### `recording/`

Owns microphone capture and temp WAV management.

v1 implementations:

- Linux PipeWire recorder via `pw-record`
- macOS helper-backed recorder abstraction

Contract:

- mono WAV
- default 16 kHz
- temp file path returned on stop
- cleanup on both success and failure

### `stt/`

Owns `whisper.cpp` command construction, execution, parsing, and health checks.

Implementation details:

- support `whisper-cli`
- parse transcript from stdout
- capture stderr for diagnostics
- include model path, language, threads, and GPU settings in the request
- normalize whitespace in returned transcript

### `llm/`

Owns prompt templates, OpenAI-compatible HTTP requests, response parsing, and health checks.

Implementation details:

- raw mode bypasses HTTP entirely
- prompt templates keyed by mode
- strict response parsing for chat completion content
- configurable endpoint, model, timeout, temperature, top_p, and max_tokens
- handle transport, timeout, auth, schema, and empty-response failures distinctly

### `clipboard/`

Owns clipboard backend selection and copy execution.

Backends:

- Wayland `wl-copy`
- X11 `xclip`
- X11 `xsel`
- macOS `pbcopy`

Behavior:

- detect backend on startup
- fail fast in doctor if no backend exists
- preserve previous clipboard contents on pipeline failure by only copying after all upstream stages succeed

### `indicator/`

Owns the small red recording indicator as a separate helper process.

IPC commands:

- `show_recording`
- `show_processing`
- `show_success`
- `show_error`
- `hide`

Implementation details:

- helper process launched by daemon when enabled
- IPC over Unix domain socket or stdin control channel
- one-off mode never starts the helper
- if helper crashes, daemon continues and logs a degraded indicator status

### `metrics/`

Owns JSONL metrics serialization and aggregation helpers for status and bench.

Implementation details:

- default path `~/.local/share/voiceflow-local/metrics.jsonl`
- store timings, lengths, success, model metadata, and error classification
- do not store transcript or output text unless debug or eval mode enables it explicitly

### `install/`

Owns installer execution, host checks, dependency acquisition, service installation, and default config creation.

Implementation details:

- start from the behavior already encoded in `whisper-ptt-install.sh`
- expose dry-run mode for every installer action
- support host-native STT setup, optional LLM mode selection, and optional service creation
- keep packaging logic separate from runtime pipeline logic

### `doctor/` and `status/`

Own readiness inspection and runtime reporting.

`doctor` checks:

- microphone command availability
- hotkey backend availability
- STT binary path and model path
- LLM endpoint reachability if enabled
- clipboard backend availability
- indicator helper availability
- service/user permission issues

`status` reports:

- daemon running or stopped
- hotkey config
- STT readiness
- model path
- LLM health
- clipboard backend
- indicator backend
- last success
- last error
- recent latency summary

## 6. Cross-Cutting Data Contracts

### Config schema

Minimum top-level sections:

- `app`
- `hotkey`
- `recording`
- `stt`
- `llm`
- `clipboard`
- `indicator`
- `metrics`

### Status snapshot

Persist a small JSON file in the runtime directory with:

- daemon PID
- started timestamp
- current state
- hotkey name
- active backends
- last success timestamp
- last error summary
- rolling latency summary

### Error model

Normalize runtime failures into stable categories:

- `config_error`
- `dependency_error`
- `permission_error`
- `recording_error`
- `stt_error`
- `llm_error`
- `clipboard_error`
- `indicator_error`
- `internal_error`

These categories feed CLI output, metrics, and logs.

## 7. Core Flows

### Daemon flow

1. `start` loads config, validates dependencies, writes runtime metadata, and starts the hotkey listener.
2. On `hotkey_down`, daemon enters `RECORDING`, shows indicator, and starts recorder.
3. On `hotkey_up`, daemon stops recorder and moves into post-processing states.
4. Pipeline transcribes audio, optionally transforms text, copies final output, emits metrics, and updates status snapshot.
5. Indicator shows success or error, then hides.

### One-off flow

1. `once` resolves input source: `--text`, `--file`, or `--record`.
2. Text input bypasses recording and STT.
3. Audio input runs through the same STT and transform pipeline.
4. Output goes to stdout by default.
5. Clipboard copy happens only when `--copy` is passed.
6. JSON mode returns structured result payload with timings and selected backend metadata.

## 8. CLI Command Breakdown

### `install`

Implementation tasks:

- platform detection
- dependency probe
- optional dependency install plan
- `whisper.cpp` detect/build/install path
- model detect/download path
- LLM mode selection
- config generation
- user service install
- final verification report

### `start`, `stop`, `restart`

Implementation tasks:

- foreground/background execution modes
- PID and service integration
- stale PID detection
- graceful shutdown signals

### `status`

Implementation tasks:

- service/PID inspection
- status snapshot read
- health probes for configured backends
- human-readable and JSON formats

### `once`

Implementation tasks:

- mutually exclusive input validation
- optional clipboard flag
- optional JSON output
- mode selection
- raw mode behavior

### `doctor`

Implementation tasks:

- readiness probes
- actionable remediation messages
- non-zero exit on failing checks

### `test`

Implementation tasks:

- dispatch to unit, integration, e2e, compat, and eval runners
- support judge URL and judge model flags

### `bench`

Implementation tasks:

- reusable benchmark harness
- repeated run orchestration
- summary generation in JSON and Markdown

### `config`

Implementation tasks:

- show current config path
- print effective config
- generate default config
- validate config file

## 9. Packaging and Service Plan

### Python packaging

- create `pyproject.toml`
- expose console script entrypoint `voiceflow-local`
- keep runtime dependencies minimal
- isolate optional test and macOS helper dependencies in extras where possible

### Linux service

- install user-level `systemd` service
- support `start`, `stop`, `restart`, and `status` through both direct process mode and systemd-aware mode
- write logs to journald in service mode

### macOS service approach

- keep v1 CLI-functional first
- allow foreground daemon execution before full `launchd` automation
- document permissions and helper setup

## 10. Testing Plan

### Unit tests

Must cover:

- config parsing and validation
- CLI parsing
- state transitions
- hotkey debounce logic
- recorder command construction
- STT command construction and output parsing
- LLM request construction and response parsing
- clipboard backend selection
- indicator IPC client behavior
- metrics serialization
- error classification

### Integration tests

Must cover:

- `once --text` with fake LLM
- `once --file` with fake STT
- raw mode bypassing LLM
- clean mode calling LLM
- one-off mode never starting indicator
- clipboard adapter integration
- LLM health checks
- indicator IPC roundtrip

### Host E2E tests

Linux v1 target scenarios:

- daemon start and stop
- hotkey press/release handling
- recording start/stop
- clipboard receives final output
- indicator state changes
- failures preserve clipboard contents

### Docker compatibility tests

Targets:

- Fedora latest
- Fedora previous
- Ubuntu LTS
- Debian stable
- Arch

Rules:

- no real microphone requirement
- no real overlay requirement
- no real global hotkey requirement
- fake STT and fake LLM support mandatory

### Eval and benchmark outputs

Required generated files:

- `results/compat-docker-report.md`
- `results/compat-docker-results.jsonl`
- `results/bench-summary.json`
- `results/bench-results.jsonl`
- `results/bench-report.md`

## 11. Incremental Delivery Plan

### Phase 1: Foundation

- create Python package skeleton
- implement config, logging, error model, and shared result types
- implement `once --text`
- implement LLM adapter and raw mode

Exit criteria:

- CLI package installs locally
- `once --text` works in raw and clean modes
- unit tests cover config and LLM adapter basics

### Phase 2: Local audio pipeline

- implement recorder adapter
- implement STT adapter with `whisper.cpp`
- implement `once --file` and `once --record`
- implement metrics logging

Exit criteria:

- one-off audio path works end-to-end on Linux
- JSON output includes timings and backend metadata

### Phase 3: Daemon and desktop behavior

- implement hotkey adapter
- implement daemon state machine
- implement clipboard adapter
- implement indicator helper and IPC
- implement `status`, `stop`, and `restart`

Exit criteria:

- hold-to-record works on Fedora/Wayland
- indicator behavior matches product spec
- clipboard updates only on success

### Phase 4: Installer and operations

- port installer responsibilities from Bash prototype
- add `doctor`
- add systemd service integration
- add default config generation

Exit criteria:

- new user can install and start the daemon from the documented flow
- doctor catches missing dependencies and misconfiguration

### Phase 5: Quality harness

- add integration and E2E suites
- add Docker compatibility suite
- add benchmark runner
- add eval dataset and judge runner

Exit criteria:

- required reports are generated
- latency and quality regressions are observable

## 12. Risks and Mitigations

### Linux hotkey permissions

Risk:

- `evdev` may require group membership or device access that is fragile across distros.

Mitigation:

- keep Linux-first support explicit
- validate access during install and doctor
- structure the hotkey adapter so alternate backends can be added later without pipeline changes

### Overlay portability

Risk:

- Wayland and macOS overlay behavior differs and may complicate a single helper implementation.

Mitigation:

- separate helper from daemon
- keep IPC protocol tiny
- allow `--no-indicator` and config-based disablement

### LLM runtime packaging sprawl

Risk:

- trying to fully manage local LLM runtimes in v1 will slow delivery.

Mitigation:

- default to external OpenAI-compatible endpoint support
- keep managed and Dockerized LLM modes optional

### Performance variance

Risk:

- end-to-end latency may miss targets on longer recordings or weaker CPUs.

Mitigation:

- emit precise stage timings
- keep raw mode available
- benchmark multiple speech lengths early

## 13. Decisions Locked for Breakdown

The following decisions should be treated as fixed unless a later product decision explicitly changes them:

1. Python is the v1 implementation language.
2. `whisper.cpp` CLI is the default STT backend.
3. External OpenAI-compatible endpoint is the default transform mode.
4. Docker is not the primary desktop runtime.
5. The indicator runs as a separate helper, not inside the main daemon process.
6. One-off and daemon modes share the same core pipeline and result contracts.

## 14. Ready-for-Breakdown Output

The next planning step should decompose work into implementation tickets grouped by:

- package foundation
- one-off pipeline
- STT integration
- daemon and hotkey flow
- indicator helper
- installer and doctor
- testing, benchmark, and eval harnesses

Each breakdown item should name:

- concrete deliverable
- owning module path
- dependencies on earlier work
- acceptance checks or test evidence
