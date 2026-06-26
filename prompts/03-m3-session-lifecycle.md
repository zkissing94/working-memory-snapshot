$milestone-execution

Implement M3 only: session lifecycle.

Required reading:
- AGENTS.md
- docs/00-product-prd.md
- docs/01-system-architecture.md
- docs/02-ui-spec.md
- docs/03-data-model.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md

Branch:
`feature/m3-session-lifecycle`

Scope:
- sessions migration and repository
- one-active-session database invariant
- required mission form
- active-session screen
- elapsed count-up timer
- complete session flow
- cancel session flow
- end-session brain-dump form
- save brain dump before later generation
- recovery sheet when an active session exists on app launch
- tests for state transitions and active-session constraint

Do not implement:
- events or observation
- snapshots
- LM Studio generation
- Pomodoro intervals
- notifications

Acceptance criteria:
- user can start, complete, and cancel a session
- empty mission is rejected
- second active session is rejected
- brain dump persists
- active session is recoverable after relaunch
- project access is resolved for session start
- tests and full check pass

Commit:
`feat: implement project session lifecycle`
