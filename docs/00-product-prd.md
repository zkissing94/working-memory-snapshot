# Working Memory Snapshot — Product Requirements Document

**Status:** Seed specification
**Target:** Minimal usable increment for macOS
**Primary user:** Founder/coder
**Core promise:** Return to deep work in under 60 seconds

## 1. Product summary

Working Memory Snapshot is a local-first macOS app that preserves enough context from a project-based work session to make the next session easy to resume.

A user selects a local project, states what they are trying to make true, works normally across tools such as Codex, Cursor, Claude, a browser, Terminal, and an editor, then ends with a short brain dump. The app combines that human account with lightweight local evidence and generates a one-screen Working Memory Snapshot.

The session timer is a boundary, not the product. The product is continuity of thought.

## 2. Problem

The expensive part of knowledge work is often not focusing. It is rebuilding the mental model that existed before an interruption.

At the end of a productive session, a founder/coder may know:

- the real problem they are solving
- what changed
- what they ruled out
- why they made a decision
- what is still uncertain
- the exact next move

That state is fragile. Files, commits, terminal commands, and chat transcripts show fragments of the work but do not reliably preserve the user's working model.

Existing timers measure elapsed time. Existing task managers preserve commitments. Existing notes preserve what the user explicitly writes. This product preserves the thread required to continue.

## 3. Job to be done

> When I return to a project after an interruption, help me reconstruct the thread I was holding so I can take the next meaningful action within 60 seconds.

## 4. Target user

The first user is a founder/coder who:

- works in local project folders and Git repositories
- moves between implementation, debugging, research, and product reasoning
- uses AI coding tools but does not want private project data sent to a cloud summarizer
- often stops with unfinished reasoning in working memory
- values a calm, local, low-maintenance tool

The MVP is not optimized for managers monitoring a team, students tracking study intervals, or organizations performing workforce analytics.

## 5. Product thesis

1. Context reconstruction is a meaningful tax.
2. Session boundaries create natural moments to capture and compress context.
3. A short brain dump contains more cognitive meaning than passive telemetry alone.
4. Lightweight evidence makes that brain dump more specific and less dependent on memory.
5. A local model can synthesize the two without exposing private project context.

## 6. Core loop

```text
Choose project
→ State a mission
→ Start session
→ Work normally
→ End session
→ Brain dump
→ Generate Working Memory Snapshot
→ Return later
→ Read Resume Brief and next action
→ Resume
```

## 7. Minimal usable increment

The first product must prove only this:

> A generated snapshot helps the user restart meaningful work faster than memory alone.

The minimal usable increment includes:

- project creation from a user-selected folder
- one active session at a time
- mission entry
- elapsed session time
- typed end-session brain dump
- lightweight file, Git, and app-activation evidence
- local snapshot generation through LM Studio
- latest Resume Brief and next action visible from the project screen
- local persistence across app restarts

## 8. Working Memory Snapshot

The snapshot is the core artifact.

```json
{
  "what_changed": "string",
  "decisions": ["string"],
  "open_loops": ["string"],
  "next_action": "string",
  "resume_brief": "string"
}
```

### Field intent

- `what_changed`: The most meaningful change in understanding or project state.
- `decisions`: Choices the user appears to have made. Empty when unsupported.
- `open_loops`: Unresolved questions, blockers, risks, and follow-ups.
- `next_action`: One concrete, immediately executable action.
- `resume_brief`: A compact reconstruction of the thread, under 120 words.

### Evidence hierarchy

The synthesizer should weigh evidence in this order:

1. User brain dump
2. Explicit mission
3. Git changes and session-scoped file activity
4. Application transitions
5. Timing metadata

Passive activity must not override explicit user statements.

### Decision and open-loop rules

A decision may be included only when the supplied evidence supports an actual choice, conclusion, or ruled-out option. “The user edited a file” is not a decision.

An open loop may be inferred from explicit unfinished language, failed work, unresolved questions, blockers, TODO-like statements, or a clear next probe. If uncertainty remains, phrase it as uncertainty rather than fact.

When evidence is insufficient, return an empty array. Do not manufacture completeness.

## 9. Good output

```text
What changed
You narrowed the benchmark regression to the input set rather than the reducer logic.

Decisions
• Do not modify the reducer yet.
• Inspect benchmark_set_b.json before changing core code.

Open loops
• Determine whether repeated boilerplate inflates the baseline.
• Re-run the benchmark with unique prompts.

Next action
Create a deduplicated benchmark input file and run the benchmark again.

Resume brief
You were debugging a token-reduction benchmark regression. The reducer may not be the problem. The current lead is duplicate or boilerplate-heavy prompts in benchmark_set_b.json. Start by creating a deduplicated input set and rerun the benchmark before touching the reducer.
```

## 10. Bad output

```text
You worked on code and made progress. Continue debugging tomorrow.
```

Generic summaries do not satisfy the product.

## 11. Functional requirements

### Projects

- Add a project through the macOS folder picker.
- Persist access across launches.
- Show the latest snapshot and session date.
- Never observe outside a selected project or active session.

### Sessions

- Require a non-empty mission.
- Allow only one active session in v0.
- Show elapsed time without gamification.
- Persist session state.
- Support completion and cancellation.
- Recover an active session after app relaunch.

### Evidence

- Record changed paths within the selected project.
- Record compact Git evidence when the folder is a repository.
- Record application activation transitions, not screen contents.
- Deduplicate and compact evidence before model input.
- Never read arbitrary file contents in v0.

### Brain dump

- Offer one large text field at session end.
- Prompt: “What is still in your head? Include decisions, surprises, blockers, and what you would do next.”
- Preserve the text even when model generation fails.

### Snapshot

- Generate locally through LM Studio.
- Validate structured output.
- Persist the result.
- Allow retry after a generation failure.
- Show the latest Resume Brief and next action within one click of app launch.

### Settings

- Configure LM Studio base URL.
- List and select available models.
- Store an optional authentication token in Keychain.
- Test server connectivity.
- Warn when a non-loopback server address is configured.

## 12. Non-functional requirements

### Privacy

- No cloud backend.
- No telemetry.
- No account.
- No screenshots.
- No keystrokes.
- No clipboard.
- No browser history.
- No messages from other apps.
- No project data outside the selected folder.

### Reliability

- User input is saved before model generation.
- Database writes are transactional where multiple records must remain consistent.
- A model failure cannot destroy the session or brain dump.
- Project-folder access failures are visible and recoverable.
- Main remains runnable after each merged milestone.

### Performance

- Starting or ending a session should feel immediate, excluding model inference.
- Observation must not continuously rescan large generated directories.
- Evidence passed to the model must be bounded.
- The UI remains responsive during file, Git, database, and model operations.

### Accessibility

- Use native controls and labels.
- Support keyboard navigation.
- Do not convey state by color alone.
- Respect reduced-motion settings.

## 13. Design principles

1. **Preserve cognition, not activity.**
2. **Local first.**
3. **Calm during work.**
4. **Minimal observation.**
5. **Evidence over inference.**
6. **One-screen snapshots.**
7. **Resume over remember.**
8. **User input outranks telemetry.**
9. **No scorekeeping.**
10. **Remove features until the core loop remains.**

## 14. Explicit non-goals

Do not build in the MVP:

- Pomodoro intervals or enforced breaks
- task management
- notes hierarchy
- team dashboards
- employee monitoring
- productivity scores
- streaks or gamification
- screenshots or OCR
- keylogging or mouse tracking
- clipboard capture
- full browser history
- deep Cursor, Codex, Claude, or VS Code integrations
- transcript scraping
- cloud sync
- user accounts
- billing
- plugin marketplace
- general AI chat
- knowledge graph
- semantic search across all sessions

## 15. Local-model plan

The committed product direction is a two-stage local-model architecture:

- a small evidence janitor
- a stronger snapshot synthesizer

The minimal usable increment ships deterministic evidence compaction and only the synthesizer. The janitor is introduced after observing real event volume and measuring a failure mode deterministic rules cannot solve.

This is a sequencing decision, not a rejection of the two-model design.

## 16. Success criteria

### Primary product test

A user reopens the app, reads the latest Resume Brief, and can identify the correct next meaningful action within 60 seconds.

### Supporting measures

During dogfooding, record:

- Was the next action correct?
- Did the brief omit a critical decision?
- Did it invent a decision?
- How much editing would the user make?
- Did the user resume within 60 seconds?
- Which evidence sources materially improved the brief?

No analytics instrumentation is required in the MVP; these can be captured manually during evaluation.

## 17. MVP exit criteria

The MVP is complete when a user can:

1. Add a local project.
2. Start a session with a mission.
3. Work normally while minimal observation runs.
4. End with a brain dump.
5. Generate a grounded snapshot through LM Studio.
6. Quit and relaunch the app.
7. See the latest Resume Brief and next action.
8. Resume meaningful work without manually reconstructing the session.
