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

## 3. Project list

Each row shows:

- project name
- latest completed session date, when available
- a subtle indicator when a Resume Brief exists
- an active-session indicator when applicable

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
