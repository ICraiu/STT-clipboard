---
title: Audio Capture and STT
id: voiceflow-local-audio-and-stt
local_id: audio-and-stt
depends_on:
  - voiceflow-local-foundation-and-config
  - voiceflow-local-oneoff-and-llm
---

# Implementation Task 03: Audio Capture and STT

## Objective

Extend the shared pipeline to support audio file input, timed microphone capture, and `whisper.cpp` transcription.

## Scope

- implement Linux PipeWire recorder using `pw-record`
- manage temp WAV lifecycle
- implement `whisper.cpp` adapter and transcript parsing
- add `once --file` and `once --record`
- include STT timings and model metadata in result payloads

## Owned Paths

- `src/voiceflow_local/recording/`
- `src/voiceflow_local/stt/`
- `src/voiceflow_local/app/`
- `src/voiceflow_local/cli/`
- `tests/unit/`
- `tests/integration/`

## Dependencies

- `output/tasks/01-foundation-and-config.md`
- `output/tasks/02-oneoff-and-llm.md`

## Acceptance Criteria

- audio file input runs through STT and optional transform pipeline
- timed recording produces a valid mono WAV at default 16 kHz
- STT adapter supports model path, language, threads, and GPU settings
- whitespace-normalized transcript is returned in a structured result

## Validation

- unit tests for recorder and STT command construction
- integration tests using fake STT
- optional real-STT integration test when model and binary are present
