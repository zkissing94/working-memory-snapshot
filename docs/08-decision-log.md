# Working Memory Snapshot — Architecture Decision Log

Record durable decisions here. Do not use this file for ordinary implementation notes.

## ADR-001 — Native macOS implementation

**Date:** 2026-06-25
**Status:** Accepted

Use Swift and SwiftUI rather than a cross-platform web wrapper.

**Reasoning:** The product depends on macOS folder access, workspace activation, local persistence, and calm native behavior. Native APIs reduce integration friction and produce the intended experience.

## ADR-002 — Project-based memory

**Date:** 2026-06-25
**Status:** Accepted

Sessions and snapshots belong to user-selected project folders.

**Reasoning:** Project scope grounds the model, limits observation, and gives the user a clear privacy boundary.

## ADR-003 — Local SQLite source of truth

**Date:** 2026-06-25
**Status:** Accepted

Use local SQLite behind repository interfaces.

**Reasoning:** The data is relational, small, durable, and local. A graph database is unnecessary for the MUI.

## ADR-004 — Persistent project access through bookmarks

**Date:** 2026-06-25
**Status:** Superseded by ADR-013

Persist security-scoped bookmark data, not only a path.

**Reasoning:** A sandboxed macOS app needs durable user-granted folder access across launches.

## ADR-005 — LM Studio local server

**Date:** 2026-06-25
**Status:** Accepted

Use LM Studio through its OpenAI-compatible local API.

**Reasoning:** The user already runs LM Studio. The compatibility endpoint supports model listing and structured JSON output without bundling a model runtime.

## ADR-006 — Optional token in Keychain

**Date:** 2026-06-25
**Status:** Accepted

Store an optional LM Studio API token in Keychain.

**Reasoning:** LM Studio authentication is optional, but credentials must not live in SQLite, logs, prompts, or source control.

## ADR-007 — Generic event stream

**Date:** 2026-06-25
**Status:** Accepted

Represent observations as generic events.

**Reasoning:** Codex, Cursor, Claude, Terminal, browsers, and future tools should not create tool-specific persistence schemas.

## ADR-008 — Deterministic compaction before the second model

**Date:** 2026-06-25
**Status:** Accepted

The long-term architecture has a small evidence janitor and a stronger synthesizer. The MUI starts with deterministic compaction plus the synthesizer.

**Reasoning:** This preserves the chosen two-stage direction while removing unvalidated complexity from the first build.

## ADR-009 — No raw file contents in v0

**Date:** 2026-06-25
**Status:** Accepted

Observe changed relative paths and bounded Git summaries, not arbitrary file contents.

**Reasoning:** This is a stronger privacy boundary and is enough to test whether the brain dump plus evidence produces useful resumption.

## ADR-010 — One active session

**Date:** 2026-06-25
**Status:** Accepted

Allow one active session globally in v0.

**Reasoning:** Multiple concurrent sessions create observation-routing and recovery complexity without helping the first user.

## ADR-011 — App activation events, not window content

**Date:** 2026-06-25
**Status:** Accepted

Use `NSWorkspace` activation transitions. Do not use accessibility APIs to inspect windows.

**Reasoning:** App transitions provide context without invasive permissions or sensitive content.

## ADR-012 — Serial architecture, parallel leaf work

**Date:** 2026-06-25
**Status:** Accepted

Build through the placeholder vertical slice serially. Parallelize only isolated leaf services in worktrees.

**Reasoning:** Parallel architecture changes create incompatible patterns and integration churn. Leaf services have clearer ownership.

## ADR-013 — MVP build foundation with sandbox deferred

**Date:** 2026-06-26
**Status:** Accepted

For the MVP, run with App Sandbox off, persist selected project paths, use explicit `.xcconfig` and `Info.plist` files, and validate compilation through `./scripts/check.sh` with signing disabled.

**Reasoning:** The first milestone needs a boring compile path and a working product loop before adding security-scoped bookmark and entitlement complexity. Sandbox migration remains required before public distribution.

## ADR-014 — Pomodoro blocks as session capture points

**Date:** 2026-06-27
**Status:** Accepted

Add Pomodoro blocks inside sessions as lightweight capture points with optional summaries and manual note/decision/blocker increments. Keep sessions as the resumable memory container and keep snapshots session-level.

**Reasoning:** The product promise is cognitive continuity, not productivity enforcement. Blocks make a long session easier to scan and summarize without turning the app into a timer, task manager, or activity monitor.

**Consequences:** Passive Git/file/app evidence remains in the generic `events` table and is rendered as observed context by session or block time window. No message, transcript, clipboard, browser-history, screenshot, or keystroke observation is introduced. Snapshot prompts may include user-entered block summaries and manual increments below the brain dump and above passive evidence.

## ADR-015 — Local focus-block completion alerts

**Date:** 2026-07-09
**Status:** Accepted

When an active focus block reaches zero, post a local macOS notification, bring Working Memory Snapshot to the front, and show an in-app completion prompt.

**Reasoning:** The alert makes the block boundary harder to miss and brings the user back to the capture surface that preserves working memory. The block remains a capture point inside the session, not an enforcement mechanism.

**Consequences:** No database migration is required. Deadlines are derived from existing `pomodoro_blocks` timing fields, and reaching zero does not complete a block or end a session. Notification permission is optional; if permission is denied, foreground activation plus the in-app prompt remain the app-process behavior. No new passive observation source is introduced.

## ADR-016 — Native shared UI motion system

**Date:** 2026-07-09
**Status:** Accepted

Use a small internal SwiftUI layer for visual tokens, adaptive surfaces, status presentation, hover and press feedback, workspace transitions, numeric timer transitions, and reduced-motion behavior.

**Reasoning:** The app needs consistent, expressive polish without changing its workflow or making focus sessions visually noisy. Native SwiftUI covers the required transitions and one-shot completion halo on the macOS 14 deployment target.

**Consequences:** Pow was evaluated but is not added. No production dependency, schema change, service boundary, or build-setting change is required. All motion must use the durations and accessibility fallbacks defined in the UI specification.

## ADR-017 — Durable local Daily Rollup through the existing synthesizer

**Date:** 2026-07-13
**Status:** Superseded in part by ADR-018

Create one on-demand, refreshable Daily Rollup per local calendar day from completed sessions across projects. Reuse the selected LM Studio synthesizer and persist validated results plus source metadata in SQLite.

**Reasoning:** End-of-day closure is a cross-project cognitive-continuity need. A durable artifact remains useful after generation, while a shared model configuration avoids a second runtime and settings surface.

**Consequences:** Migration 8 adds `daily_rollups` and `daily_rollup_sources`. Active sessions block generation. Snapshot-backed evidence is preferred, capture points provide a grounded fallback, and failed refreshes preserve the last valid artifact. This adds no observation source, cloud backend, account, analytics, or production dependency.

## ADR-018 — Append-only Daily Rollup revisions

**Date:** 2026-07-14
**Status:** Accepted

Persist every successful Daily Rollup generation as a revision rather than replacing the existing row for that local day. Continue to load the latest revision by default and expose earlier same-day runs through Previous Rollups with generation times.

**Reasoning:** Dogfooding showed that a valid refresh could return fewer or no carry-forwards and destructively erase useful unresolved context from an earlier run. Preserving revisions protects cognition without merging stale items into the current synthesis or introducing task-state semantics.

**Consequences:** Migration 9 drops the unique date index and adds a history index. Each revision retains its own source links. Failed generation writes nothing; successful generation never mutates an earlier artifact. History may contain multiple entries for one date, ordered newest-first.

## Open decision template

### ADR-NNN — Title

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Superseded

**Decision**

...

**Reasoning**

...

**Consequences**

...
