# Repository Map

## Start here

- `README.md` — clone, build, run, LM Studio, privacy, and troubleshooting guide
- `CODEX_START_HERE.md` — current Codex handoff workflow
- `AGENTS.md` — durable repository implementation rules
- `docs/10-current-status.md` — delivered state, current task, and next milestone

## Application

- `WorkingMemorySnapshot.xcodeproj/` — shared Xcode project and scheme
- `WorkingMemorySnapshot/` — app source, resources, UI, persistence, observation, and local-AI boundaries
- `WorkingMemorySnapshotTests/` — automated unit, repository, model-contract, and feature tests
- `WorkingMemorySnapshotUITests/` — native UI test target
- `Config/` — shared Debug and Release build configuration

## Product and engineering documents

- `docs/00-product-prd.md`
- `docs/01-system-architecture.md`
- `docs/02-ui-spec.md`
- `docs/03-data-model.md`
- `docs/04-local-ai-spec.md`
- `docs/05-mvp-roadmap.md`
- `docs/06-codex-workflow.md`
- `docs/07-macos-build-compile.md`
- `docs/07-testing-strategy.md`
- `docs/08-decision-log.md`
- `docs/09-risk-register.md`
- `docs/10-current-status.md`
- `docs/11-m7-dogfood-checklist.md`
- `docs/12-app-state-dependency-map.md`
- `docs/13-m13-ui-polish-checklist.md`
- `docs/14-daily-rollup-lm-studio-smoke-test.md`
- `docs/99-external-references.md`

## Design references

- `docs/mockups/` — selected product-state references and mockup catalog
- `Design/WorkingMemoryIcon/` — maintained app-icon source
- `design-qa.md` — latest Daily Rollup visual acceptance record
- `outputs/logos/working-memory-icon/` — archived logo exploration and review provenance; not required to build or run the app

## Automation

- `.agents/skills/milestone-execution/SKILL.md`
- `.githooks/pre-commit`
- `scripts/install_hooks.sh`
- `scripts/check.sh`
- `scripts/doctor.sh`
- `.github/pull_request_template.md`

`scripts/bootstrap_repo.sh` and `prompts/00-bootstrap-repository.md` are retained as seed-history tooling. They are not part of setup for a normal clone.

## Historical implementation prompts

The numbered files under `prompts/` record the completed milestone sequence. Do not replay them on the current implementation. Use `prompts/99-task-template.md` for a new focused task.

## Local-only files

Build output, Xcode user state, local SQLite databases and journals, tokens, environment files, logs, and temporary files are intentionally excluded by `.gitignore`.
