# Implementation Specification: voiceflow-local

## 1. Purpose

This document converts the approved product direction into a build-ready implementation plan for `voiceflow-local`. The target is a Linux-first, host-native dictation tool with:

- daemon mode for hold-to-record desktop dictation
- one-off CLI mode for text, file, and timed recording inputs
- local STT through `whisper.cpp`
- optional transcript transformation through an OpenAI-compatible endpoint
- clipboard output, metrics, status, doctor checks, and a lightweight indicator helper

This plan assumes the existing [whisper-ptt-install.sh](/workspace/project/whisper-ptt-install.sh) prototype is the starting reference for the Fedora/Wayland path and should be mined, not discarded.

## 2. Locked Decisions

These are implementation constraints for v1:

1. Use Python for the application and packaging layer.
2. Use `whisper.cpp` CLI as the default STT backend.
3. Default to an external OpenAI-compatible transform endpoint.
4. Keep desktop integrations on the host; Docker is only for compatibility, CI, optional LLM serving, and one-off non-interactive runs.
5. Run the indicator as a separate helper controlled over local IPC.
6. Share one pipeline contract between daemon mode and one-off mode.
7. Prioritize Fedora/Wayland first, while keeping abstractions ready for X11 fallback and later macOS support.

## 3. Scope Split

### In scope for v1

- Python package with `voiceflow-local` entrypoint
- `install`, `start`, `stop`, `restart`, `status`, `once`, `test`, `bench`, `doctor`, and `config` commands
- one-off `--text`, `--file`, and `--record`
- daemon mode with hold-to-record behavior
- `raw`, `clean`, and `command` as fully implemented modes
- prompt-template support for the remaining named modes
- Linux PipeWire recording
- Wayland clipboard plus X11 fallback
- local metrics and runtime status snapshots
- Docker compatibility suite
- benchmark harness and judge-based eval harness
- 200-case text eval dataset

### Explicitly deferred

- polished signed desktop app bundle
- full macOS parity across all integrations
- multi-hotkey workflows
- direct text insertion
- personal dictionary
- default managed local LLM runtime as the primary install mode
- AMD GPU container support

## 4. Repository Target

```text
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
docker/
docs/
scripts/
output/
```

## 5. Core Contracts

### Runtime pipeline contract

`PipelineRequest`

- source type: `text`, `audio_file`, or `live_record`
- mode
- copy enabled flag
- json output flag
- input metadata

`PipelineResult`

- raw transcript
- final output
- selected mode
- selected STT and LLM backends
- stage timings
- success boolean
- normalized error category

### State machine

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

The daemon owns these transitions. One-off mode reuses the same post-record pipeline stages without running the hotkey or indicator lifecycle.

### Error categories

- `config_error`
- `dependency_error`
- `permission_error`
- `recording_error`
- `stt_error`
- `llm_error`
- `clipboard_error`
- `indicator_error`
- `internal_error`

### Runtime status snapshot

Persist a small JSON file with:

- daemon PID
- started timestamp
- current state
- configured hotkey
- resolved backends
- last success timestamp
- last error summary
- rolling latency summary

## 6. Workstream Sequence

Implementation should proceed in this order:

1. Package foundation and typed config
2. Shared pipeline contracts and one-off text mode
3. Audio capture and STT integration
4. Daemon, hotkey flow, and runtime state
5. Clipboard and indicator integration
6. Installer, doctor, and service wiring
7. Test, benchmark, eval, and Docker harnesses
8. Documentation and packaging hardening

This sequence keeps the proven prototype path alive while moving riskier desktop features after the reusable core exists.

## 7. Ticket Breakdown

Each item below is intended to be a directly actionable implementation ticket.

### WS1. Package foundation

#### WS1-T1: Create Python package skeleton

Deliverable:

- `pyproject.toml`
- `src/voiceflow_local/__init__.py`
- `src/voiceflow_local/cli/`
- `tests/unit/`

Implementation notes:

- expose console script `voiceflow-local`
- keep dependencies minimal
- define optional extras for test-only requirements

Depends on:

- none

Acceptance:

- `voiceflow-local --help` runs
- test runner can import `voiceflow_local`

#### WS1-T2: Implement CLI command surface and dispatch

Deliverable:

- subcommand parser for `install`, `start`, `stop`, `restart`, `status`, `once`, `test`, `bench`, `doctor`, `config`

Owned paths:

- `src/voiceflow_local/cli/`

Implementation notes:

- use `argparse` unless a stronger need appears
- each command handler returns exit code plus structured result where appropriate
- define shared JSON output helpers early

Depends on:

- WS1-T1

Acceptance:

- help output shows all required subcommands
- unit tests validate flag parsing for `once`, `status`, `test`, and `install`

#### WS1-T3: Add typed config schema and path management

Deliverable:

- default config generation
- config loading, validation, and override layering

Owned paths:

- `src/voiceflow_local/config/`
- `src/voiceflow_local/platform/`

Implementation notes:

- config path: `~/.config/voiceflow-local/config.yaml`
- precedence: defaults < file < env < CLI
- expand `~` and environment variables on load

Depends on:

- WS1-T1

Acceptance:

- invalid paths and invalid modes fail with actionable messages
- unit tests cover merge precedence and path expansion

#### WS1-T4: Define shared result, error, and metrics models

Deliverable:

- stable dataclasses or typed models for runtime requests and results

Owned paths:

- `src/voiceflow_local/app/`
- `src/voiceflow_local/metrics/`

Depends on:

- WS1-T3

Acceptance:

- pipeline-facing models exist and are serializable to JSON
- error categories are centralized in one module

### WS2. Core one-off pipeline

#### WS2-T1: Implement prompt templates and LLM adapter

Deliverable:

- OpenAI-compatible chat completions client
- prompt registry for `raw`, `clean`, `command`, and placeholder support for other named modes

Owned paths:

- `src/voiceflow_local/llm/`

Implementation notes:

- raw mode must bypass HTTP entirely
- parse strict chat completion output
- map timeout, transport, empty body, and malformed schema failures separately

Depends on:

- WS1-T3
- WS1-T4

Acceptance:

- `once --text` works in raw mode without endpoint access
- fake server integration proves clean mode request construction

#### WS2-T2: Build shared one-off pipeline runner

Deliverable:

- reusable `run_pipeline()` entrypoint for text and audio inputs

Owned paths:

- `src/voiceflow_local/app/`

Implementation notes:

- for `--text`, bypass recording and STT
- stdout is default sink
- clipboard copy happens only when requested

Depends on:

- WS2-T1

Acceptance:

- `voiceflow-local once --text "hi"` returns transformed or raw output
- `--json` returns structured result with timings and backend metadata

#### WS2-T3: Add metrics JSONL writer and summary helpers

Deliverable:

- metrics append path
- summary helpers for status and bench

Owned paths:

- `src/voiceflow_local/metrics/`

Depends on:

- WS1-T4
- WS2-T2

Acceptance:

- successful and failed one-off runs append metrics
- transcript and final text are excluded unless debug or eval mode enables storage

### WS3. Audio and STT

#### WS3-T1: Implement recorder adapter

Deliverable:

- Linux PipeWire recorder backend using `pw-record`
- temp WAV lifecycle management

Owned paths:

- `src/voiceflow_local/recording/`

Implementation notes:

- default mono, 16 kHz WAV
- guarantee cleanup on both success and failure

Depends on:

- WS1-T3
- WS2-T2

Acceptance:

- recorder command construction is unit tested
- `once --record 3s` creates valid WAV input for later stages

#### WS3-T2: Implement `whisper.cpp` adapter

Deliverable:

- `whisper-cli` command builder
- stdout/stderr parsing into `TranscriptResult`

Owned paths:

- `src/voiceflow_local/stt/`

Implementation notes:

- configurable model path, threads, language, and GPU use
- normalize whitespace in transcripts
- preserve stderr for diagnostics

Depends on:

- WS3-T1
- WS1-T4

Acceptance:

- unit tests cover command construction and transcript parsing
- fake STT integration path is available for non-host tests

#### WS3-T3: Add one-off file and recording flows

Deliverable:

- `once --file`
- `once --record`

Owned paths:

- `src/voiceflow_local/cli/`
- `src/voiceflow_local/app/`

Depends on:

- WS3-T1
- WS3-T2

Acceptance:

- audio file and timed recording paths work end-to-end
- JSON output includes STT latency and model metadata

### WS4. Daemon and hotkey flow

#### WS4-T1: Implement explicit runtime state machine

Deliverable:

- transition table and state timing markers

Owned paths:

- `src/voiceflow_local/state/`

Depends on:

- WS1-T4

Acceptance:

- unit tests cover legal and illegal transitions
- stage timings are exposed to metrics/status layers

#### WS4-T2: Implement hotkey adapter

Deliverable:

- Linux `evdev` hold-to-record backend

Owned paths:

- `src/voiceflow_local/hotkey/`

Implementation notes:

- emit one `hotkey_down` and one `hotkey_up`
- ignore repeats
- ignore taps shorter than configured minimum
- enforce max recording duration

Depends on:

- WS1-T3
- WS4-T1

Acceptance:

- unit tests cover debounce and repeat suppression
- Linux host test proves press/release mapping

#### WS4-T3: Implement daemon runtime and PID/status files

Deliverable:

- foreground daemon
- background/service-ready daemon
- runtime snapshot persistence

Owned paths:

- `src/voiceflow_local/daemon/`
- `src/voiceflow_local/status/`

Depends on:

- WS4-T1
- WS4-T2
- WS3-T3

Acceptance:

- `start --foreground` runs
- `status` shows running/stopped and backend summary
- stale PID detection works

#### WS4-T4: Implement daemon control commands

Deliverable:

- `stop`
- `restart`
- service-aware process control

Owned paths:

- `src/voiceflow_local/cli/`
- `src/voiceflow_local/daemon/`

Depends on:

- WS4-T3

Acceptance:

- daemon can be started, stopped, and restarted from CLI
- non-zero exit on control failure

### WS5. Clipboard and indicator

#### WS5-T1: Implement clipboard backend selection

Deliverable:

- Wayland `wl-copy`
- X11 `xclip`
- X11 `xsel`
- macOS `pbcopy` adapter boundary

Owned paths:

- `src/voiceflow_local/clipboard/`

Depends on:

- WS1-T3
- WS2-T2

Acceptance:

- backend detection prefers `wl-copy` on Wayland
- clipboard is only updated after successful upstream processing

#### WS5-T2: Implement indicator helper IPC protocol

Deliverable:

- helper control API for `show_recording`, `show_processing`, `show_success`, `show_error`, `hide`

Owned paths:

- `src/voiceflow_local/indicator/`

Implementation notes:

- choose Unix socket or stdio control and keep protocol tiny
- daemon must degrade gracefully if helper is disabled or crashes

Depends on:

- WS4-T3

Acceptance:

- integration test proves IPC roundtrip
- one-off mode never starts the helper

#### WS5-T3: Bind daemon state to clipboard and indicator behavior

Deliverable:

- state-driven visual behavior during record/process/success/error

Owned paths:

- `src/voiceflow_local/daemon/`
- `src/voiceflow_local/indicator/`

Depends on:

- WS5-T1
- WS5-T2
- WS4-T3

Acceptance:

- host E2E shows indicator during recording and processing
- clipboard remains unchanged on failure

### WS6. Install, doctor, and service integration

#### WS6-T1: Port installer logic from Bash prototype

Deliverable:

- Python-driven install workflow covering dependency checks, `whisper.cpp` detection, model detection, config generation, and optional service setup

Owned paths:

- `src/voiceflow_local/install/`
- `scripts/`

Implementation notes:

- treat [whisper-ptt-install.sh](/workspace/project/whisper-ptt-install.sh) as source material for Fedora package and permission logic
- every action must support `--dry-run`

Depends on:

- WS1-T2
- WS1-T3
- WS4-T3

Acceptance:

- installer can produce a no-op plan in dry-run mode
- installer can generate a default config and service file without manual edits

#### WS6-T2: Implement `doctor`

Deliverable:

- readiness checks for dependencies, permissions, paths, clipboard, hotkey backend, and LLM endpoint reachability

Owned paths:

- `src/voiceflow_local/doctor/`

Depends on:

- WS6-T1
- WS5-T1
- WS3-T2

Acceptance:

- failing checks produce concrete remediation messages
- command exits non-zero on blocking problems

#### WS6-T3: Implement user service integration

Deliverable:

- systemd user service generation and lifecycle wiring

Owned paths:

- `src/voiceflow_local/install/`
- `src/voiceflow_local/platform/`

Depends on:

- WS4-T4
- WS6-T1

Acceptance:

- service file is generated correctly
- `start`, `stop`, `restart`, and `status` work with service mode

### WS7. Quality harness

#### WS7-T1: Add unit and integration suites

Deliverable:

- coverage for config, CLI parsing, state transitions, debounce logic, recorder command construction, STT parsing, LLM request construction, clipboard selection, indicator IPC, metrics serialization, and error mapping

Owned paths:

- `tests/unit/`
- `tests/integration/`

Depends on:

- WS1 through WS6 components as they land

Acceptance:

- unit and integration suites pass in local development without real desktop dependencies

#### WS7-T2: Add host E2E suite

Deliverable:

- host-only validation for daemon startup, hotkey press/release, recording lifecycle, indicator behavior, clipboard behavior, and failure safety

Owned paths:

- `tests/e2e/`

Depends on:

- WS5-T3

Acceptance:

- Fedora/Wayland target scenarios are executable on host
- failures do not overwrite clipboard contents

#### WS7-T3: Add Docker compatibility harness

Deliverable:

- distro matrix for Fedora latest, Fedora previous, Ubuntu LTS, Debian stable, and Arch
- fake STT and fake LLM support
- generated reports

Owned paths:

- `tests/compat/`
- `docker/`

Depends on:

- WS2-T2
- WS3-T2
- WS6-T1

Acceptance:

- `voiceflow-local test --compat --docker` produces:
  - `results/compat-docker-report.md`
  - `results/compat-docker-results.jsonl`

#### WS7-T4: Add benchmark runner

Deliverable:

- repeated-run harness with percentile summaries

Owned paths:

- `src/voiceflow_local/testing/`
- `tests/`

Depends on:

- WS2-T3
- WS3-T3

Acceptance:

- `bench` produces:
  - `results/bench-summary.json`
  - `results/bench-results.jsonl`
  - `results/bench-report.md`

#### WS7-T5: Add eval dataset and judge runner

Deliverable:

- `testdata/text_cases.jsonl` with 200 synthetic examples
- judge runner using configurable OpenAI-compatible endpoint and model

Owned paths:

- `tests/eval/`
- `testdata/`

Depends on:

- WS2-T1

Acceptance:

- `test --eval --judge-url ... --judge-model ...` runs without code changes
- strict JSON judge output is parsed and pass/fail criteria are enforced

### WS8. Docs and packaging hardening

#### WS8-T1: Update README and operational docs

Deliverable:

- setup, config, install mode, Docker compatibility, and troubleshooting docs

Owned paths:

- `README.md`
- `docs/`

Depends on:

- core commands stabilized through WS6

Acceptance:

- docs reflect actual command behavior and output files

#### WS8-T2: Add packaging guidance and release checklist

Deliverable:

- repeatable release checklist for Linux-first packaging and later macOS expansion

Owned paths:

- `docs/packaging.md`
- `docs/architecture.md`

Depends on:

- WS6-T3
- WS7-T3

Acceptance:

- release process names required artifacts, smoke tests, and known platform limits

## 8. Milestones and Exit Criteria

### Milestone A: CLI and text pipeline

Includes:

- WS1-T1 through WS1-T4
- WS2-T1 and WS2-T2

Exit criteria:

- package installs locally
- `once --text` works for `raw` and `clean`
- JSON output is stable enough for tests

### Milestone B: Audio one-off pipeline

Includes:

- WS2-T3
- WS3-T1 through WS3-T3

Exit criteria:

- `once --file` and `once --record` work end-to-end on Linux
- STT timings and metadata are emitted

### Milestone C: Daemon desktop flow

Includes:

- WS4-T1 through WS4-T4
- WS5-T1 through WS5-T3

Exit criteria:

- hold-to-record works on Fedora/Wayland
- indicator behavior matches state changes
- clipboard only updates after success

### Milestone D: Operations and installability

Includes:

- WS6-T1 through WS6-T3

Exit criteria:

- install flow is dry-run capable and idempotent
- doctor identifies missing dependencies and permissions
- service-managed daemon lifecycle works

### Milestone E: Quality gates

Includes:

- WS7-T1 through WS7-T5
- WS8-T1 and WS8-T2

Exit criteria:

- compatibility, benchmark, and eval outputs are generated
- docs cover actual supported install and runtime modes

## 9. Acceptance Matrix

### Core acceptance

- `voiceflow-local start` starts the daemon
- hold hotkey -> record -> release -> transcribe -> transform -> copy flow works
- indicator shows during recording and processing, then hides
- errors do not corrupt clipboard contents

### One-off acceptance

- `once --file`, `once --record`, and `once --text` work
- no indicator appears in one-off mode
- `--copy` is opt-in
- `--json` returns structured output

### Operational acceptance

- `status` reports daemon state, hotkey, backends, model path, endpoint health, last success, last error, and latency summary
- `doctor` reports actionable failures
- installer supports dry-run and optional service creation

### Quality acceptance

- Docker compatibility reports are generated
- benchmark reports include percentile summaries
- eval suite contains 200 cases and uses configurable judge URL/model

## 10. Risks and Mitigations

### Hotkey permissions on Linux

Risk:

- `evdev` device access is brittle across distros and user sessions.

Mitigation:

- keep Fedora/Wayland as the explicit first target
- make permission checks first-class in install and doctor
- isolate hotkey backend behind an adapter

### Overlay portability

Risk:

- one helper implementation may not map cleanly across Wayland and macOS.

Mitigation:

- keep IPC protocol tiny
- allow indicator disablement
- do not block daemon success on helper availability

### LLM packaging sprawl

Risk:

- managed LLM runtime work can dominate v1 effort.

Mitigation:

- keep external OpenAI-compatible endpoint as default
- treat managed and Dockerized LLM as optional install modes

### Performance drift

Risk:

- long recordings or weak CPUs may miss latency targets.

Mitigation:

- emit stage timings from the start
- keep raw mode available
- add benchmarks before packaging is finalized

## 11. Ready-for-Execution Summary

This specification is ready to drive implementation tickets. The critical path is:

1. package foundation
2. text pipeline
3. audio pipeline
4. daemon and hotkey loop
5. clipboard and indicator behavior
6. installer and service wiring
7. quality harnesses and docs

If planning is split across multiple owners, the cleanest ownership boundaries are:

- core CLI/config/app
- audio/STT
- daemon/hotkey/indicator
- install/doctor/service
- test/eval/benchmark/Docker
