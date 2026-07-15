# Daily Rollup Design QA

- Source visual truth: `docs/mockups/global-daily-rollup-carry-forward-focus.png`
- Implementation evidence: locally captured at 1298 × 768 during the unlocked acceptance pass
- Comparison artifacts: ephemeral QA files were intentionally not committed; the durable findings are recorded below
- Source viewport: 1487 × 1058 (the supplied 1440 × 1024 direction rendered with its surrounding frame)
- Implementation viewport: 1298 × 768 (largest unlocked desktop capture available)
- State: generated historical Daily Rollup with five completed sessions, three projects, carry-forwards, history, and source-session links

**Full-view comparison evidence**

The source and unlocked SwiftUI capture were normalized to the same width and stacked in one comparison image. The implementation preserves the selected direction's two-column macOS shell, global Daily Rollup selection, restrained blue accent, generated-day header, brief-first hierarchy, project-thread column, emphasized carry-forward column, and closure note. All three project threads, every carry-forward, and the closure note remain visible without scrolling at 1298 × 768, which is smaller than the target viewport. No text is cropped and no persistent control is pushed off-screen.

The implementation intentionally renders Ready, Generating, and Stale as mutually exclusive screen states instead of the source board's bottom concept strip. Historical rollups also disable Refresh, which prevents rewriting a past day from the current-day generation action.

**Focused region comparison evidence**

The source and implementation content regions were cropped from the sidebar boundary through the right edge and stacked in one focused comparison. The generated header, project attribution, source-session controls, Open Project links, carry-forward attribution, dividers, and closure note use the same visual reading order as the source. The implementation's project summaries are longer realistic output, but the bounded model contract and native text wrapping keep the artifact comfortably scannable.

**Findings**

- No actionable P0, P1, or P2 differences remain.
- [P3] The implementation carry-forward surface uses the app's existing emphasized surface token, producing a subtle border rather than the mockup's slightly flatter gray fill. This is acceptable because it preserves the existing SwiftUI design system and does not weaken hierarchy.
- [P3] The source uses a larger viewport and includes a supporting-state concept strip. The implementation was verified at the available 1298 × 768 viewport, where the generated artifact is denser but still fully visible. The supporting states are implemented as separate mutually exclusive states as specified.

**Required fidelity surfaces**

- Fonts and typography: native system typography matches the existing app; title, date, metadata, section labels, body text, links, and attributed carry-forwards retain clear optical hierarchy with no truncation.
- Spacing and layout rhythm: the workspace uses the existing wide-workspace and spacing tokens; main and secondary columns stay balanced, 8-point surfaces remain consistent, and the closure note visibly ends the artifact.
- Colors and visual tokens: system window/control colors, semantic secondary text, separators, and the restrained system blue accent match the app shell and source direction in light mode.
- Image quality and asset fidelity: the source contains no content imagery. The implementation uses the existing app icon plus native SF Symbols for folders, history, refresh, and carry-forward affordances; all render sharply at the captured scale.
- Copy and content: realistic three-project founder/coder content remains grounded, attributed, and bounded. There are no scores, streaks, charts, invented metrics, or task-manager controls.
- Accessibility and interaction: the unlocked pass verified the Previous Rollups menu, a two-session source menu, and source-session drill-down to the existing historical detail. Native controls expose labels/hints, unavailable sources disable safely, and historical refresh is unavailable by design.

**Comparison history**

- Pass 1: the source was opened and the isolated seeded app launched, but macOS was locked. No rendered comparison was possible, so the result remained blocked.
- Pass 2: after unlock, a generated synthetic three-project artifact was captured at 1298 × 768. The full-view and focused comparisons found no actionable P0/P1/P2 mismatch. No product-code visual fix was required.

**Implementation checklist**

1. Full generated state compared at the available unlocked viewport — complete.
2. Header, project/source controls, carry-forwards, and closure note compared in a focused crop — complete.
3. History selection and source-session drill-down exercised — complete.
4. P0/P1/P2 findings resolved — none remaining.

**Follow-up polish**

- Consider a later P3 pass on the carry-forward fill after broader light/dark dogfooding; it is not a release blocker.

final result: passed
