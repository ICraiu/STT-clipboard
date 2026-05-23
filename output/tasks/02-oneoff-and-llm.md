---
title: One-Off Pipeline and LLM Modes
id: voiceflow-local-oneoff-and-llm
local_id: oneoff-and-llm
depends_on:
  - voiceflow-local-foundation-and-config
---

# Implementation Task 02: One-Off Pipeline and LLM Modes

## Objective

Implement the shared one-off pipeline for text input first, including OpenAI-compatible transform support and raw-mode bypass.

## Scope

- implement prompt templates for `raw`, `clean`, and `command`
- add LLM adapter for `/v1/chat/completions`
- implement `once --text`
- add `--json` and `--copy` behavior
- append metrics for one-off runs

## Owned Paths

- `src/voiceflow_local/llm/`
- `src/voiceflow_local/app/`
- `src/voiceflow_local/cli/`
- `src/voiceflow_local/metrics/`
- `tests/unit/`
- `tests/integration/`

## Dependencies

- `output/tasks/01-foundation-and-config.md`

## Acceptance Criteria

- `once --text` works in raw mode without any LLM endpoint
- clean mode sends a valid OpenAI-compatible request
- stdout is the default output sink
- clipboard copy is only performed when `--copy` is passed
- JSON mode returns structured timings and backend metadata

## Validation

- fake LLM integration test for clean mode
- raw-mode integration test proving HTTP bypass
- unit tests for prompt selection and response parsing
