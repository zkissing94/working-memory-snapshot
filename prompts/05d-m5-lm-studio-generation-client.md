$milestone-execution

Implement M5d only: LM Studio structured snapshot generation client.

Run this in a Codex worktree based on the clean M4 `main` commit.

Required reading:
- AGENTS.md
- docs/01-system-architecture.md
- docs/04-local-ai-spec.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md

Branch:
`feature/m5d-lm-studio-generation`

Allowed areas:
- `WorkingMemorySnapshot/LocalAI/LMStudioClient.swift`
- response/request DTOs
- `SnapshotSchema.swift`
- focused validation types
- corresponding tests

Do not modify:
- views
- database schema
- repositories
- PromptBuilder
- observation services
- session lifecycle

Scope:
- POST `/v1/chat/completions`
- JSON-schema structured response request
- optional bearer token
- timeout and HTTP error mapping
- decode response content
- validate SnapshotGenerationResult
- one bounded JSON-repair retry
- injected transport and mocked tests

Acceptance criteria:
- successful structured response decodes
- invalid envelope is typed
- invalid snapshot JSON triggers at most one retry
- previous valid data is not involved or overwritten
- token behavior matches M2
- no prompts or responses are logged
- tests and full check pass

Commit:
`feat: add LM Studio structured generation client`
