# Working Memory Snapshot — Risk Register

| Risk | Impact | Early mitigation | Validation point |
|---|---|---|---|
| Path-based project access is too loose for distribution | Public release blocked | Keep App Sandbox migration as an explicit later milestone | Pre-distribution hardening |
| App Sandbox prevents Git subprocess behavior | Git evidence unavailable | Defer sandbox until core loop works; later run `/usr/bin/git` with active security scope and record entitlement decisions | Sandbox migration/M5a |
| Passive evidence lacks deep meaning from Codex or Claude work | Resume brief becomes generic | Brain dump is primary evidence; preserve mission, manual increments, and Git/file facts | M6/M8 dogfood |
| Model invents decisions | Product becomes untrustworthy | Strict prompt, empty arrays allowed, low temperature, structured output, manual evaluation | M6/M7 |
| Small model adds latency without quality | Two-stage design harms experience | Keep janitor disabled until measured need | M9 evaluation |
| Pomodoro UI shifts the product toward productivity enforcement | Calm cognitive-continuity loop becomes a timer app | Treat blocks as optional capture points; no auto-ending sessions, streaks, scores, or break enforcement | M8 dogfood |
| Focus-block completion alerts become intrusive | The app feels disruptive during work instead of useful at capture boundaries | Alert only at block completion, require user confirmation before persistence, avoid repeated prompts for a dismissed block | Manual alert validation |
| Session detail implies message or transcript observation | Privacy promise is weakened and user trust drops | Render only Git/file/app events as observed context; explicitly exclude messages/transcripts from schema and UI | M8 review |
| Large repositories create event noise or CPU load | Observation disrupts work | FSEvents, ignore rules, bounded aggregation, no repeated full scans | M5b |
| Pre-existing Git changes are attributed to the session | Snapshot reports false work | Capture initial state and session-observed paths; label limitations | M5a/M6 |
| App closes during an active session | Session is orphaned | Persist state at start; recovery sheet on launch | M3 |
| LM Studio is stopped, model unloaded, or authentication changes | Snapshot generation fails | Save brain dump before generation; clear connection states; retry | M2/M6 |
| Structured output varies by local model | JSON parsing fails | Schema mode, validation, one bounded repair retry, model-selection guidance | M5d |
| Daily Rollup invents cross-project progress or turns carry-forwards into task scoring | End-of-day closure becomes untrustworthy or gamified | Snapshot-first evidence, strict project attribution and word limits, no scores, one bounded repair retry, preserve last valid artifact | Daily Rollup dogfood |
| Daily Rollup refresh removes useful carry-forwards from an earlier run | Unresolved context is lost during testing or refinement | Append every successful generation as a revision; load latest by default; keep exact prior runs in history | Daily Rollup dogfood |
| Non-loopback LM Studio URL leaks private evidence | Privacy promise is violated | Detect and warn before saving remote address | M2 |
| Token or prompt content appears in logs | Sensitive data exposure | Keychain, OSLog privacy, no prompt/body logging | Every milestone |
| Parallel Codex threads edit shared files | Merge conflicts and inconsistent architecture | Worktrees only after M4; explicit file ownership | M5 |
| Agent commits unrelated changes | Reviewability degrades | Clean-state protocol, explicit staging, diff review, pre-commit hook | Every task |
| Hand-authored Xcode project file is malformed | Build cannot open | Generate initial project through Xcode; avoid manual `.pbxproj` creation | Before M1 |
| Codex changes Xcode build settings opportunistically | Project becomes brittle | Pin settings in `.xcconfig`; require build-contract doc before config edits | Every build config task |
