$milestone-execution

Implement M5a only: GitService as an isolated leaf task.

Run this in a Codex worktree based on the clean M4 `main` commit.

Required reading:
- AGENTS.md
- docs/01-system-architecture.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md
- docs/09-risk-register.md

Branch:
`feature/m5a-git-service`

Allowed areas:
- `WorkingMemorySnapshot/Observation/GitService.swift`
- `WorkingMemorySnapshot/Utilities/ProcessRunner.swift`
- focused Git models if needed
- corresponding test files
- decision log only when a real architectural decision is required

Do not modify:
- views
- navigation
- database schema
- session repository
- snapshot generator
- LM Studio client

Scope:
- detect Git repository
- run `/usr/bin/git` with argument arrays
- capture branch, HEAD, porcelain status, bounded diff stat, changed names
- distinguish non-repository from command failure
- support paths containing spaces
- apply timeout and output bounds
- temporary-repository tests
- manual App Sandbox test notes

Acceptance criteria:
- non-Git project is a normal result
- dirty state can be captured
- session-observed paths can be used to bound final evidence
- command failure is typed
- output is bounded
- tests and full check pass

Commit:
`feat: add bounded Git evidence service`
