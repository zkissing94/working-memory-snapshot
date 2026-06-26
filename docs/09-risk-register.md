# Working Memory Snapshot — Risk Register

| Risk | Impact | Early mitigation | Validation point |
|---|---|---|---|
| Path-based project access is too loose for distribution | Public release blocked | Keep App Sandbox migration as an explicit later milestone | Pre-distribution hardening |
| App Sandbox prevents Git subprocess behavior | Git evidence unavailable | Defer sandbox until core loop works; later run `/usr/bin/git` with active security scope and record entitlement decisions | Sandbox migration/M5a |
| Passive evidence lacks deep meaning from Codex or Claude work | Resume brief becomes generic | Brain dump is primary evidence; preserve mission and Git/file facts; later consider explicit transcript import | M6 dogfood |
| Model invents decisions | Product becomes untrustworthy | Strict prompt, empty arrays allowed, low temperature, structured output, manual evaluation | M6/M7 |
| Small model adds latency without quality | Two-stage design harms experience | Keep janitor disabled until measured need | M8 evaluation |
| Large repositories create event noise or CPU load | Observation disrupts work | FSEvents, ignore rules, bounded aggregation, no repeated full scans | M5b |
| Pre-existing Git changes are attributed to the session | Snapshot reports false work | Capture initial state and session-observed paths; label limitations | M5a/M6 |
| App closes during an active session | Session is orphaned | Persist state at start; recovery sheet on launch | M3 |
| LM Studio is stopped, model unloaded, or authentication changes | Snapshot generation fails | Save brain dump before generation; clear connection states; retry | M2/M6 |
| Structured output varies by local model | JSON parsing fails | Schema mode, validation, one bounded repair retry, model-selection guidance | M5d |
| Non-loopback LM Studio URL leaks private evidence | Privacy promise is violated | Detect and warn before saving remote address | M2 |
| Token or prompt content appears in logs | Sensitive data exposure | Keychain, OSLog privacy, no prompt/body logging | Every milestone |
| Parallel Codex threads edit shared files | Merge conflicts and inconsistent architecture | Worktrees only after M4; explicit file ownership | M5 |
| Agent commits unrelated changes | Reviewability degrades | Clean-state protocol, explicit staging, diff review, pre-commit hook | Every task |
| Hand-authored Xcode project file is malformed | Build cannot open | Generate initial project through Xcode; avoid manual `.pbxproj` creation | Before M1 |
| Codex changes Xcode build settings opportunistically | Project becomes brittle | Pin settings in `.xcconfig`; require build-contract doc before config edits | Every build config task |
