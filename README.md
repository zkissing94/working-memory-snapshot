# Working Memory Snapshot

A local-first macOS app that helps founder/coders return to deep work in under 60 seconds.

This repository is a **Codex-ready project seed**. It contains the product requirements, architecture, UI and data specifications, local-model contract, implementation roadmap, engineering workflow, task prompts, validation scripts, Git hooks, and a repository-scoped Codex skill.

It intentionally contains no product implementation yet.

## Product loop

```text
Choose project
→ Start a session with a mission
→ Work normally
→ End with a short brain dump
→ Generate a Working Memory Snapshot
→ Resume later in under 60 seconds
```

## Technical direction

- Native macOS app
- Swift and SwiftUI
- Local SQLite persistence
- User-selected project folders with persistent security-scoped access
- LM Studio local server through its OpenAI-compatible API
- Generic event stream for file, Git, application, and user evidence
- No cloud backend, accounts, telemetry, screenshots, keystrokes, or clipboard capture

## AI direction

The long-term design is a two-stage local-model pipeline:

1. **Evidence janitor:** a small model that selects, tags, deduplicates, and compresses noisy evidence.
2. **Snapshot synthesizer:** a stronger model that produces the Working Memory Snapshot.

The minimal usable increment does **not** begin with two live models. It uses deterministic evidence compaction plus the synthesizer. The small-model stage is added only after real session data proves it is necessary.

## Start here

Read [`CODEX_START_HERE.md`](CODEX_START_HERE.md).

## Canonical documents

- [`docs/00-product-prd.md`](docs/00-product-prd.md)
- [`docs/01-system-architecture.md`](docs/01-system-architecture.md)
- [`docs/02-ui-spec.md`](docs/02-ui-spec.md)
- [`docs/03-data-model.md`](docs/03-data-model.md)
- [`docs/04-local-ai-spec.md`](docs/04-local-ai-spec.md)
- [`docs/05-mvp-roadmap.md`](docs/05-mvp-roadmap.md)
- [`docs/06-codex-workflow.md`](docs/06-codex-workflow.md)
- [`docs/07-testing-strategy.md`](docs/07-testing-strategy.md)
- [`docs/08-decision-log.md`](docs/08-decision-log.md)
- [`docs/09-risk-register.md`](docs/09-risk-register.md)

## Current milestone

**M0 — Seed the repository and establish the engineering workflow.**
