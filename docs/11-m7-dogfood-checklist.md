# M7 Manual Dogfood Checklist

Run five real project sessions after M7 lands. Record results manually; do not add analytics or telemetry.

## Setup

- Use a real local project folder.
- Configure LM Studio at a loopback URL.
- Select a downloaded instruct model.
- Keep App Sandbox off for the MVP build.

## Per-session checklist

For each of five sessions:

1. Start a session with a concrete mission.
2. Work normally for at least 10 minutes.
3. Make at least one observable project change when the session calls for it.
4. End the session and write a brain dump with decisions, surprises, blockers, and next action.
5. Generate a Working Memory Snapshot through LM Studio.
6. Quit and relaunch the app.
7. Confirm the latest Resume Brief and Start here action are visible within one click.
8. Time how long it takes to identify the next meaningful action.

## Recovery checks

During at least one of the five sessions:

- Quit the app while a session is active, relaunch, and confirm the recovery sheet offers Resume Session, End Session, and Cancel Session.
- Move or rename the selected project folder before relaunch, confirm Resume Session is blocked, choose the folder again, then resume.
- Stop LM Studio before generation, confirm the session and brain dump are saved, restart LM Studio, and retry generation.

## Record

For each resumed session, record:

- Time to identify the next action.
- Whether the Resume Brief was accurate.
- Whether any decision was invented.
- Whether any critical open loop was missing.
- Whether another artifact was needed before resuming.
- Whether the next action was concrete enough to start immediately.

The M7 dogfood pass succeeds when the user can identify the correct next action in under 60 seconds for most sessions without losing trust in the snapshot.
