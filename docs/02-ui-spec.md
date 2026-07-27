# Working Memory Snapshot — UI and Interaction Specification

## 1. Experience goal

The app should feel like a quiet macOS utility that is present at session boundaries and nearly absent during work.

It should not look like a productivity dashboard.

## 2. Navigation

Use a native `NavigationSplitView`.

### Sidebar

- Projects
- Add Project
- Settings

### Detail

The selected project, active session, end-session form, snapshot, or settings.

Do not create a tab bar, dashboard, or multi-level information architecture in v0.

### Post-MVP M8/9 layout

After M7 dogfooding, the app uses a simpler two-column `NavigationSplitView` while preserving the same product loop:

- sidebar: active project, card-like project rows, lightweight project metadata, Settings
- workspace: selected project dashboard, active session, selected historical session, latest memory, snapshot, access recovery, generation failure, or settings

This is still not a generic productivity dashboard. The hierarchy is `Project -> Session -> Pomodoro Block -> Work Increment`, and every surface should help the user preserve or resume cognitive context.

## 3. Project list

Each row shows:

- project name
- latest completed session date, when available
- a subtle indicator when a Resume Brief exists
- an active-session indicator when applicable

Pinned projects appear in a separate `Pinned` group above the remaining projects. A row context menu supports Pin/Unpin, and drag and drop reorders projects within either group. Pin state and manual order persist across launches.

Empty state:

```text
No projects yet

Add a project folder to create your first Working Memory Snapshot.
```

Primary action:

```text
Add Project
```

## 4. Add project

Present the native directory picker.

After selection:

- name defaults to folder name
- selected location is displayed
- access is persisted
- the new project becomes selected

Errors:

- folder no longer accessible
- project already exists

Do not ask for project metadata beyond the folder and default name in M1.

## 5. Project detail

### No sessions

Show:

- project name
- abbreviated path
- primary button: `Start Session`
- message explaining the first snapshot

### With latest snapshot

Place the most useful resumption information first:

```text
Resume Brief
<brief>

Start here
<next action>
```

Then show:

- latest session time
- `Start Session`
- `View Snapshot`

The user should not need to enter a history screen to find the latest Resume Brief.

## 6. Start session

Field label:

```text
Mission
```

Prompt:

```text
What are you trying to make true?
```

The mission is required.

Primary action:

```text
Start Session
```

Do not ask for timer length, tags, category, priority, or definition of done in the MUI.

## 7. Active session

Show:

- project name
- mission
- elapsed time
- a quiet `Session active` state
- compact evidence counters after M5
- primary action: `End Session`
- secondary action: `Cancel Session`

Example:

```text
Session active                         42:18

Mission
Determine why the benchmark regressed.

Observed
6 files changed · Git repository · Cursor, Terminal, Safari
```

Do not show a live feed of raw events by default.

The timer counts upward. It does not enforce intervals or trigger break notifications.

### Post-MVP M8 active block surface

The active session surface may include one 20-minute Pomodoro block capture card:

- countdown from 20 minutes by default
- pause/resume current block
- complete block with an optional summary
- start next block without ending the session
- take a break by leaving the session active with no open block
- end session through the existing brain-dump flow

A session never ends automatically when a block ends. Blocks are capture points, not productivity enforcement. Do not add streaks, scores, break notifications, or gamified status.

Manual work increments can be added inside the current block with these kinds:

- note
- decision
- blocker

Observed context remains read-only and generic: Git, changed files, and active applications from existing events. Do not add message, transcript, clipboard, browser-history, screenshot, or keystroke observation.

Historical session detail groups checkpointed file and application evidence under the focus block where it was observed. Evidence captured while a block is paused or no block is open appears under `Between blocks`. Older events without window metadata remain visible as session-wide evidence. Git stays session-level and exposes bounded branch, HEAD, changed-path, diff-stat, and commit facts through a disclosure rather than a raw event count.

### Post-MVP block completion alert

When an active focus block reaches zero, the app may post a local macOS notification, bring Working Memory Snapshot to the front, select the active project, and show an in-app completion prompt:

```text
Focus Block <n> complete

The session is still active. Capture what changed before starting another block.
```

The prompt includes the block intention, an optional “What changed during this block?” summary field, `Return to Block`, and `Save and Complete Block`.

This alert is a capture boundary only. It does not auto-complete the block, end the session, enforce a break, create a streak, or add new observation sources. If notification permission is denied, the in-app prompt and foreground activation remain the primary behavior while the app process is running.

## 8. End-session brain dump

Prompt:

```text
What is still in your head?
```

Supporting text:

```text
Include decisions, surprises, blockers, and what you would do next.
```

Use one large multiline text editor.

Primary action:

```text
Generate Working Memory Snapshot
```

Secondary action:

```text
Return to Session
```

The brain dump may be empty, but the UI should gently explain that a sentence or two produces a more useful snapshot.

When the primary action is pressed:

1. Save the brain dump first.
2. Complete the session.
3. Show generation progress.
4. Preserve the form and offer retry if generation fails.

## 9. Snapshot

Use one vertically scrollable detail view with clear sections:

1. What changed
2. Decisions
3. Open loops
4. Next action
5. Resume Brief

Empty decisions or open loops should show a neutral statement such as:

```text
No supported decisions were identified.
```

Do not substitute generic content.

Actions:

- `Start New Session`
- `Regenerate` when generation failed or the user explicitly requests it
- `Back to Project`

Snapshot editing is a post-MUI enhancement. Do not add a complex review workflow before the core loop is proven.

## 10. Settings

### LM Studio section

Fields:

- Base URL
- Synthesizer Model
- API Token, optional and masked

Defaults:

```text
Base URL: http://localhost:1234/v1
Synthesizer Model: none selected
API Token: empty
```

Actions:

- `Test Connection`
- `Refresh Models`
- `Save`

Connection state should distinguish:

- server unreachable
- authentication required or rejected
- server reachable with no models
- selected model unavailable
- success

If the base URL is not loopback, display:

```text
This server is not running on this Mac. Project evidence may leave this device.
```

### Future model setting

Do not expose a janitor-model selector until that stage is implemented.

## 11. Session recovery

When the app launches with an active session, show a recovery sheet:

```text
A session was active when the app closed.

Mission
<mission>

Started
<time>
```

Actions:

- `Resume Session`
- `End Session`
- `Cancel Session`

Do not silently mark it complete or create another session.

## 12. Loading and error states

### Snapshot generation

Show a small progress indicator and:

```text
Creating your Working Memory Snapshot locally…
```

Do not imply the app is uploading data.

### LM Studio unreachable

```text
LM Studio could not be reached.

Start the local server, confirm the address in Settings, and try again.
```

### Invalid model output

```text
The selected model did not return a valid snapshot.

Your session and brain dump are saved. Try again or select another model.
```

### Project access lost

```text
This project folder is no longer accessible.

Choose the folder again to restore access.
```

## 13. Native behavior

- Use standard macOS toolbar, buttons, sheets, alerts, and focus behavior.
- Support keyboard shortcuts where obvious:
  - `⌘N` add project or start session based on context
  - `⌘,` settings
  - `⌘Return` submit a focused primary form when safe
- Preserve text during navigation and failures.
- Respect system appearance.
- Respect Dynamic Type and reduced motion.
- Avoid custom animations in v0.

### Post-MVP M13 motion and visual polish

The post-MVP interface uses one shared native SwiftUI presentation system across all mapped workspace states.

- Preserve the existing navigation, copy, controls, information order, and state transitions.
- Use 8-point continuous corner radii, adaptive system backgrounds, SF typography, the system accent color, and semantic success/warning/error tones.
- Keep interactive feedback brief: 100-140 ms for hover and press, 180-240 ms for ordinary state changes, and 260-320 ms for a single emphasized moment.
- Animate workspace replacement with opacity, no more than 8 points of vertical movement, and a maximum 0.99 insertion scale.
- Use numeric content transitions for live timers and short interpolation for progress updates.
- Use a one-shot checkmark halo only after a focus block is completed. Do not repeat it automatically.
- Do not add ambient looping animation, particles, confetti, sound, gamified effects, or motion that delays input.
- When Reduce Motion is enabled, remove scale, movement, symbol choreography, and the completion halo; use an instant update or a short opacity transition.
- Keep native macOS sheet and window presentation behavior.

## 14. Copy rules

Use literal, calm copy.

Prefer:

- Start Session
- End Session
- Resume Brief
- Start here
- Generate Working Memory Snapshot

Avoid:

- Supercharge
- Optimize productivity
- AI magic
- Crush your goals
- Flow score
- Streak

## 15. Visual non-goals

No:

- charts
- productivity scores
- streaks
- badges
- confetti
- gamification
- heat maps
- animated countdown rings
- dense side panels
- message/transcript capture

## 16. Global Daily Rollup

- Place a selected `Daily Rollup` row above Projects in the persistent sidebar.
- Use the Carry-Forward Focus direction preserved at `docs/mockups/global-daily-rollup-carry-forward-focus.png`.
- Lead with the date and a compact whole-day brief; render project threads in the main column and carry-forwards in one emphasized secondary surface.
- End with a closure note. Keep generated content scannable at 1440 × 1024.
- Ready, blocked, generating, generated, stale, empty, and failed are mutually exclusive states in the same hierarchy.
- A stale artifact remains visible with a calm `Refresh Rollup` notice.
- Project names open the project workspace. Available source sessions open historical session detail; deleted sources remain labeled but disabled.
- Previous Rollups lists every generated run newest-first. Same-day revisions include generation time so an earlier set of carry-forwards can be reopened unambiguously.
- Do not introduce checkboxes, scores, charts, streaks, timelines, or task-manager language.
