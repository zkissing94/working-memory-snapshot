# Working Memory Snapshot - Current Status

## Where the project is

Current handoff branch:

```text
feature/m2-lm-studio-settings
```

Completed milestones:

- M0 - Repository seed and Codex workflow
- M1 - App shell, build foundation, and project persistence
- M2 - LM Studio settings and model discovery

Current implementation state:

- Native SwiftUI macOS app scaffold exists.
- Shared `WorkingMemorySnapshot` scheme is committed.
- Build settings are pinned through `Config/*.xcconfig`.
- Explicit `WorkingMemorySnapshot/Resources/Info.plist` is committed.
- `./scripts/check.sh` builds and tests with signing disabled.
- SQLite project persistence works with path-based project access while App Sandbox is off for MVP.
- Settings persistence works through `app_settings`.
- LM Studio base URL and selected synthesizer model persist locally.
- Optional LM Studio API token is stored in Keychain, not SQLite.
- Settings UI supports base URL, synthesizer model, optional token, connection testing, model refresh, and non-loopback warning.
- `LMStudioClient` lists models through `GET /v1/models` with optional bearer authentication.
- Automated M2 tests cover URL normalization, loopback warning logic, settings persistence, token privacy, bearer headers, and distinct connection states.
- LM Studio is not required to compile or launch the app.

## Next milestone

Next task after merging M2 to `main`:

```text
M3 - Session lifecycle
```

Use:

```text
prompts/03-m3-session-lifecycle.md
```

Expected branch:

```text
feature/m3-session-lifecycle
```

Expected commit message:

```text
feat: implement project session lifecycle
```

## Fresh chat startup

In a fresh Codex chat, start by opening this repository root and reading:

- `AGENTS.md`
- `docs/10-current-status.md`
- `docs/05-mvp-roadmap.md`
- `docs/07-macos-build-compile.md`
- `prompts/03-m3-session-lifecycle.md`

Then run:

```bash
git status --short
git branch --show-current
./scripts/check.sh
```

Do not start M3 unless M2 has been merged to `main`, `main` is clean, and `./scripts/check.sh` passes.

## M2 completion summary

M2 added local LM Studio configuration only:

- settings repository backed by `app_settings`
- optional Keychain token storage
- `LMStudioSettings` model
- Settings UI and view model
- base URL normalization
- loopback/non-loopback detection and warning
- model listing through `GET /v1/models`
- selected model persistence
- mocked network tests through an injected transport

M2 did not add sessions, observation, snapshot generation, chat completions, or external Swift packages.

Branch:

```text
feature/m2-lm-studio-settings
```

Commit:

```text
6b8dc7e feat: add LM Studio settings and model discovery
```

Validation:

```text
./scripts/check.sh - passed
```

## M3 scope reminder

M3 owns session lifecycle only:

- sessions migration and repository
- one-active-session invariant
- required mission form
- active-session screen
- elapsed count-up timer
- complete and cancel flows
- end-session brain-dump form
- active-session recovery on relaunch

M3 must not add observation, events, snapshots, LM Studio generation, Pomodoro intervals, or notifications.

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
