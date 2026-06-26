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
**Status:** Accepted

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
