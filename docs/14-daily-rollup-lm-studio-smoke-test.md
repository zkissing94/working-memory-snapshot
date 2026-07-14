# Daily Rollup LM Studio Smoke Test

Use this checklist for the live local-runtime boundary. Automated tests must not require LM Studio.

1. Start the LM Studio local server and load the model already selected in Working Memory Snapshot Settings.
2. Complete two or three sessions across at least two projects on the same local calendar day; leave one session without a generated snapshot but include a brain dump or block capture.
3. Open the global Daily Rollup and confirm the Ready counts match completed sessions and participating projects.
4. Generate the rollup. Confirm the Generating state states that source sessions remain saved.
5. Confirm the result contains a grounded whole-day brief, one thread per participating project, attributed carry-forwards, a closure note, and source-session links.
6. Open one project and one source session, then return to Daily Rollup.
7. Complete another session or regenerate a source snapshot. Confirm the existing rollup becomes stale and remains readable.
8. Stop LM Studio and refresh. Confirm the previous artifact remains visible with a recovery message.
9. Restart LM Studio and refresh. Confirm the latest artifact updates and Previous Rollups retains both same-day runs with distinct generation times.
10. Review for invented work, productivity judgments, scores, cropped text, or unsupported carry-forwards. Record any failure before changing prompt or limits.
