$milestone-execution

Implement M4 only: placeholder snapshot vertical slice.

Required reading:
- AGENTS.md
- docs/00-product-prd.md
- docs/01-system-architecture.md
- docs/02-ui-spec.md
- docs/03-data-model.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md

Branch:
`feature/m4-placeholder-snapshot`

Scope:
- snapshots migration and repository
- deterministic placeholder generator using only mission and brain dump
- placeholder must clearly be deterministic and must not invent decisions
- snapshot detail view
- latest Resume Brief and next action on project detail
- retry-safe save/replace behavior
- tests for snapshot persistence and latest-snapshot query
- full manual vertical-slice path

Placeholder rules:
- `what_changed`: summarize only explicit brain-dump content or state that no change was captured
- `decisions`: always `[]`
- `open_loops`: use one explicit unfinished statement only when present; otherwise `[]`
- `next_action`: use an explicit next action from the brain dump; otherwise “Review the prior mission and choose the first verification step.”
- `resume_brief`: combine mission and brain dump without adding facts

Do not implement:
- observation
- Git service
- file watcher
- active-app service
- LM Studio chat completion

Acceptance criteria:
- project → session → brain dump → placeholder snapshot → relaunch → resume works
- snapshot persists
- latest brief is visible within one click
- no unsupported decision is generated
- tests and full check pass

Commit:
`feat: add placeholder snapshot vertical slice`
