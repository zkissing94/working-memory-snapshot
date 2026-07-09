# M13 UI Motion And Polish Review

Use this checklist to validate the shared UI system without changing the product workflow.

## Environment matrix

Review every state at both `900 x 650` and `1440 x 900` in:

- Light appearance
- Dark appearance
- Reduce Motion enabled
- Increase Contrast enabled

For each configuration, confirm keyboard focus remains visible, VoiceOver labels describe icon-only actions, text does not clip, and animation never delays input or resets a draft.

## State matrix

- [ ] 1. Empty library and no projects
- [ ] 2. Add project folder picker
- [ ] 3. Project dashboard with latest memory and no active session
- [ ] 4. Start session form
- [ ] 5. Active session with active focus block
- [ ] 6. Paused focus block
- [ ] 7. Between blocks
- [ ] 8. End-session brain dump and local generation
- [ ] 9. Snapshot generation failure with retry
- [ ] 10. Snapshot detail
- [ ] 11. Historical session detail with blocks and observed context
- [ ] 12. Recovery sheet with accessible project folder
- [ ] 13. Recovery sheet with missing project folder
- [ ] 14. Project folder access lost
- [ ] 15. Settings ready or successful
- [ ] 16. Settings connection problems

## Motion acceptance

- [ ] Workspace replacement uses a brief fade, small vertical offset, and subtle scale without overlapping controls.
- [ ] Live timers use numeric transitions and remain readable once per second.
- [ ] Progress movement is smooth but never continuous or distracting.
- [ ] Active, paused, and between-block changes preserve form and focus state.
- [ ] Increment insertion and inline completion forms animate once without moving unrelated controls.
- [ ] The focus-block completion halo plays once after confirmation and does not replay on ordinary navigation.
- [ ] Reduce Motion removes offsets, scale, and the completion halo.
- [ ] No ambient looping animation, particles, confetti, sound, or gamified effects appear.

## Final validation

```bash
./scripts/check.sh
```

Record any visual defect with the state number, appearance, window size, and accessibility configuration.
