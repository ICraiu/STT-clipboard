---
title: Install, Operations, and Quality Harnesses
id: voiceflow-local-install-ops-and-quality
local_id: install-ops-and-quality
depends_on:
  - voiceflow-local-foundation-and-config
  - voiceflow-local-oneoff-and-llm
  - voiceflow-local-audio-and-stt
  - voiceflow-local-daemon-desktop-flow
---

# Implementation Task 05: Install, Operations, and Quality Harnesses

## Objective

Make the application installable and operable end-to-end, then add the required compatibility, benchmark, and eval systems.

## Scope

- port installer logic from `whisper-ptt-install.sh`
- add `doctor`
- add user service integration
- create Docker compatibility harness
- create benchmark runner
- create eval dataset and judge runner
- update README and operational docs

## Owned Paths

- `src/voiceflow_local/install/`
- `src/voiceflow_local/doctor/`
- `src/voiceflow_local/platform/`
- `src/voiceflow_local/testing/`
- `tests/compat/`
- `tests/eval/`
- `testdata/`
- `docker/`
- `docs/`
- `README.md`

## Dependencies

- `output/tasks/01-foundation-and-config.md`
- `output/tasks/02-oneoff-and-llm.md`
- `output/tasks/03-audio-and-stt.md`
- `output/tasks/04-daemon-desktop-flow.md`

## Acceptance Criteria

- installer supports dry-run and default config generation
- `doctor` reports actionable failures for dependencies, permissions, and endpoint health
- service integration supports `start`, `stop`, `restart`, and `status`
- `test --compat --docker` generates compatibility reports
- `bench` generates JSON and Markdown summaries
- eval suite contains 200 text transcript cases and supports configurable judge URL/model

## Validation

- installer dry-run output
- service smoke test on Linux host
- generated compatibility, benchmark, and eval artifacts from test commands
