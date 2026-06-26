$milestone-execution

Implement M1 only: app shell, build foundation, and project persistence.

Required reading:
- AGENTS.md
- docs/00-product-prd.md
- docs/01-system-architecture.md
- docs/02-ui-spec.md
- docs/03-data-model.md
- docs/05-mvp-roadmap.md
- docs/07-macos-build-compile.md
- docs/07-testing-strategy.md
- docs/08-decision-log.md

Branch:
`feature/m1-app-shell-build-sqlite`

Prerequisite:
A standard SwiftUI macOS Xcode project named `WorkingMemorySnapshot` must exist in the repository. Do not hand-author a new `.pbxproj`. If it is absent, stop after reporting the exact Xcode creation steps from CODEX_START_HERE.md.

Scope:
- native SwiftUI macOS app shell
- shared WorkingMemorySnapshot scheme
- `.xcconfig` build configuration
- explicit Info.plist with NSAllowsLocalNetworking
- scripts/check.sh
- scripts/doctor.sh
- NavigationSplitView with project sidebar and detail
- SQLite database actor and numbered migration runner
- projects schema from docs/03-data-model.md
- project repository
- NSOpenPanel directory selection
- path-based project persistence with App Sandbox off for MVP
- project list and empty state
- database in Application Support
- unit tests for migration and project repository
- update `scripts/check.sh` only as needed to build and test the actual scheme

Do not implement:
- LM Studio settings
- sessions
- events
- observation
- snapshots
- model calls
- sandbox migration
- external Swift packages

Acceptance criteria:
- app launches
- user can select one project folder
- project is persisted
- project remains after app relaunch
- duplicate project selection is handled
- migration is idempotent
- tests and full check pass

Commit:
`feat: add app shell and project persistence`
