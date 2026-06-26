$milestone-execution

Implement M7 only: resume, recovery, and usability polish.

Required reading:
- AGENTS.md
- docs/00-product-prd.md
- docs/02-ui-spec.md
- docs/05-mvp-roadmap.md
- docs/07-testing-strategy.md
- docs/09-risk-register.md

Branch:
`feature/m7-resume-recovery-polish`

Scope:
- make latest Resume Brief and next action immediately visible
- active-session recovery polish
- stale/lost project-access recovery
- model and connection empty/error states
- keyboard navigation
- accessibility labels
- preserve all user-entered text across failure states
- manual dogfood checklist
- fix only defects discovered in the core loop

Do not implement:
- dashboards
- analytics
- snapshot search
- small-model janitor
- voice input
- new observation sources
- visual redesign beyond native calm UI

Acceptance criteria:
- launch-to-resume context is one click or less
- interrupted session is recoverable
- lost folder access can be restored
- all primary controls are keyboard reachable
- VoiceOver labels exist for controls and state
- five-session dogfood checklist is documented
- tests and full check pass

Commit:
`feat: polish resume and session recovery`
