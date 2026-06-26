# Start Here: Importing This Project into Codex

All documents referenced by the prompts are already included in this repository seed.

## 1. Unpack and open the repository

1. Unzip this bundle into the directory where the project should live.
2. Open that directory as a project in the Codex app, Codex CLI, or Codex IDE extension.
3. Codex will automatically discover the root `AGENTS.md`.
4. The repository-scoped `$milestone-execution` skill is located at:
   `.agents/skills/milestone-execution/SKILL.md`

## 2. Seed Git before application work

Paste the contents of:

```text
prompts/00-bootstrap-repository.md
```

This initializes Git when needed, installs the local hooks, validates the bundle, and creates the documentation seed commit. It does not implement the app.

## 3. Create the blank Xcode project once

Use Xcode for the initial project-file generation rather than asking an agent to hand-author a `.pbxproj`.

Create a new project in this repository root:

- Template: **macOS App**
- Product Name: `WorkingMemorySnapshot`
- Interface: **SwiftUI**
- Language: **Swift**
- Include Tests: **Yes**
- Data storage template: **None**
- Create Git repository: **No** if M0 already initialized Git
- Deployment target: **macOS 14.0 or later**

Do not create a second nested repository.

Share the `WorkingMemorySnapshot` scheme and commit it under:

```text
WorkingMemorySnapshot.xcodeproj/xcshareddata/xcschemes/
```

After the scaffold exists, apply the build contract from:

```text
docs/07-macos-build-compile.md
```

Commit the generated Xcode scaffold on a focused branch, or let the M1 prompt incorporate it after inspecting the diff.

## 4. Implement serially through the vertical slice

Run these prompts in order:

```text
prompts/01-m1-app-shell-and-projects.md
prompts/02-m2-lm-studio-settings.md
prompts/03-m3-session-lifecycle.md
prompts/04-m4-placeholder-snapshot.md
```

After M4, this end-to-end path must work:

```text
project → session → brain dump → placeholder snapshot → resume
```

## 5. Parallelize only the isolated leaf services

After M4 is merged into `main`, the following tasks may run in separate Codex worktrees:

```text
prompts/05a-m5-git-service.md
prompts/05b-m5-file-observation.md
prompts/05c-m5-active-app-observation.md
prompts/05d-m5-lm-studio-generation-client.md
```

Base every worktree on the same clean `main` commit. Do not let two threads modify the same files.

## 6. Integrate serially again

After the M5 leaf branches are reviewed and merged:

```text
prompts/06-m6-real-snapshot-integration.md
prompts/07-m7-resume-and-recovery-polish.md
```

## Operating rule

Use the repository skill explicitly for implementation work:

```text
$milestone-execution
```

Codex may create local branches and commits. It must not push, merge, delete branches, rewrite history, or open a pull request unless explicitly instructed.
