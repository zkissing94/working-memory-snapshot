We are seeding a new repository. All product and workflow documents already exist in this folder.

Read:
- AGENTS.md
- CODEX_START_HERE.md
- MANIFEST.md
- docs/00-product-prd.md
- docs/01-system-architecture.md
- docs/05-mvp-roadmap.md
- docs/06-codex-workflow.md

Do not implement application code.

Tasks:
1. Inspect the repository root and verify the manifest files exist.
2. Run `git status --short` and determine whether this is already a Git repository.
3. If it is not a Git repository, initialize it with `main` as the initial branch.
4. Install the repository hooks by running `./scripts/install_hooks.sh`.
5. Run `./scripts/check.sh --quick`.
6. Review the seed diff.
7. Stage only the seed files in MANIFEST.md.
8. Commit them with:
   `docs: seed product and Codex workflow`
9. Return the standard final report from AGENTS.md.

Safety:
- Do not overwrite unrelated files.
- Do not push or create a remote.
- Do not create application source files.
- If Git identity is not configured, leave the files staged, report the exact failure, and do not invent identity values.
