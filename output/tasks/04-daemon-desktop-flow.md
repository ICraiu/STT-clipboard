---
title: Daemon Desktop Flow
id: voiceflow-local-daemon-desktop-flow
local_id: daemon-desktop-flow
depends_on:
  - voiceflow-local-foundation-and-config
  - voiceflow-local-oneoff-and-llm
  - voiceflow-local-audio-and-stt
---

# Implementation Task 04: Daemon, Hotkey, Clipboard, and Indicator

## Objective

Implement the long-running desktop flow for hold-to-record dictation on Linux, using the shared pipeline from earlier tasks.

## Scope

- implement explicit daemon state machine
- add Linux `evdev` hotkey backend
- add daemon runtime, PID files, and status snapshot
- implement clipboard backend selection
- add indicator helper with local IPC
- wire `start`, `stop`, `restart`, and `status`

## Owned Paths

- `src/voiceflow_local/state/`
- `src/voiceflow_local/hotkey/`
- `src/voiceflow_local/daemon/`
- `src/voiceflow_local/status/`
- `src/voiceflow_local/clipboard/`
- `src/voiceflow_local/indicator/`
- `src/voiceflow_local/cli/`
- `tests/unit/`
- `tests/integration/`
- `tests/e2e/`

## Dependencies

- `output/tasks/01-foundation-and-config.md`
- `output/tasks/02-oneoff-and-llm.md`
- `output/tasks/03-audio-and-stt.md`

## Acceptance Criteria

- `start --foreground` runs the daemon
- hotkey press starts recording and release stops it
- state transitions drive indicator behavior
- clipboard updates only after successful processing
- one-off mode never starts the indicator helper
- `status` reports daemon state, backends, last success, last error, and latency summary

## Validation

- unit tests for state transitions and debounce logic
- integration tests for indicator IPC and clipboard selection
- host E2E tests on Fedora/Wayland for record/process/copy behavior
