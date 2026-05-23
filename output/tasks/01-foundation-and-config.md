---
title: Foundation and Config
id: voiceflow-local-foundation-and-config
local_id: foundation-and-config
depends_on: []
---

# Implementation Task 01: Foundation and Config

## Objective

Create the Python package skeleton, CLI entrypoint, shared config system, and core runtime data models for `voiceflow-local`.

## Scope

- add `pyproject.toml` and console entrypoint `voiceflow-local`
- create `src/voiceflow_local/` package layout
- implement CLI subcommand registration
- implement config loading, validation, and override precedence
- define shared pipeline, error, and metrics models

## Owned Paths

- `pyproject.toml`
- `src/voiceflow_local/cli/`
- `src/voiceflow_local/config/`
- `src/voiceflow_local/platform/`
- `src/voiceflow_local/app/`
- `src/voiceflow_local/metrics/`
- `tests/unit/`

## Dependencies

- none

## Acceptance Criteria

- `voiceflow-local --help` runs
- required subcommands are registered
- config path defaults to `~/.config/voiceflow-local/config.yaml`
- precedence order is defaults < file < env < CLI
- runtime models serialize cleanly to JSON

## Validation

- unit tests for CLI parsing
- unit tests for config validation and override merging
- unit tests for shared result/error model serialization
