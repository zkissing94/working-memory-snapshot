# Working Memory Snapshot - Current Status

## Where the project is

Current branch baseline:

```text
main
```

Completed milestones:

- M0 - Repository seed and Codex workflow
- M1 - App shell, build foundation, and project persistence

Current implementation state:

- Native SwiftUI macOS app scaffold exists.
- Shared `WorkingMemorySnapshot` scheme is committed.
- Build settings are pinned through `Config/*.xcconfig`.
- Explicit `WorkingMemorySnapshot/Resources/Info.plist` is committed.
- `./scripts/check.sh` builds and tests with signing disabled.
- SQLite project persistence works with path-based project access while App Sandbox is off for MVP.
- LM Studio is not required to compile or launch the app.

## Next milestone

Next task:

```text
M2 - LM Studio settings
```

Use:

```text
prompts/02-m2-lm-studio-settings.md
```

Expected branch:

```text
feature/m2-lm-studio-settings
```

Expected commit message:

```text
feat: add LM Studio settings and model discovery
```

## Fresh chat startup

In a fresh Codex chat, start by opening this repository root and reading:

- `AGENTS.md`
- `docs/10-current-status.md`
- `docs/05-mvp-roadmap.md`
- `docs/07-macos-build-compile.md`
- `prompts/02-m2-lm-studio-settings.md`

Then run:

```bash
git status --short
git branch --show-current
./scripts/check.sh
```

Do not start M2 unless `main` is clean and `./scripts/check.sh` passes.

## M2 summary

M2 adds local LM Studio configuration only:

- settings repository backed by `app_settings`
- optional Keychain token storage
- `LMStudioSettings` model
- Settings UI and view model
- base URL normalization
- loopback/non-loopback detection and warning
- model listing through `GET /v1/models`
- selected model persistence
- mocked network tests through an injected transport

M2 must not add sessions, observation, snapshot generation, chat completions, or external Swift packages.

## Persistent build constraints

Keep these pinned unless explicitly changed by a new accepted decision:

```text
Project: WorkingMemorySnapshot.xcodeproj
Scheme: WorkingMemorySnapshot
Bundle ID: com.broceps.WorkingMemorySnapshot
Minimum macOS target: 14.0
Swift language mode: Swift 5
App Sandbox: off for MVP
SQLite: system SQLite3
LM Studio required for compile: no
```
