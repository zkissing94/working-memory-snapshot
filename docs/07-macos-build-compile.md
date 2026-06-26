# Working Memory Snapshot - macOS Build & Compile Spec

## Purpose

This document defines the macOS build, compile, signing, configuration, and validation rules for the Working Memory Snapshot app.

The goal is to prevent common Xcode/Codex failure modes:

- broken `.xcodeproj` configuration
- missing shared scheme
- accidental deployment-target changes
- code signing failures
- sandbox permission churn during MVP work
- local-only files committed by mistake
- build scripts that work on one machine only
- Codex changing project configuration while implementing unrelated features

Treat this document as a required build contract.

## Build Philosophy

The build should be boring, local-first, repeatable, minimally signed for development, explicitly configured, and easy for Codex to validate.

Avoid clever project configuration, unnecessary dependencies, and opportunistic build-setting upgrades.

## Toolchain Baseline

Required local tools:

- macOS
- Xcode
- Command Line Tools
- Git
- SQLite through macOS system libraries
- LM Studio for runtime AI generation

LM Studio is not required to compile the app. It is required only to manually test runtime snapshot generation.

Use Xcode 26 or newer with the Swift compiler provided by the installed Xcode. Apple's Xcode support page and App Store upload requirements should be treated as the current source of truth for distribution requirements.

For MVP development:

```text
Swift language version: Swift 5
Minimum deployment target: macOS 14.0
```

Do not upgrade Swift language mode or deployment target during feature work unless explicitly requested.

## Product Identity

Use these defaults:

```text
Product name: WorkingMemorySnapshot
Target name: WorkingMemorySnapshot
Scheme name: WorkingMemorySnapshot
Bundle identifier: com.broceps.WorkingMemorySnapshot
```

The app has exactly one primary app scheme for v0: `WorkingMemorySnapshot`.

The scheme must be shared and committed under:

```text
WorkingMemorySnapshot.xcodeproj/xcshareddata/xcschemes/
```

Do not rely on user-local schemes.

## Xcode Project Rules

The initial macOS app project should be created once with Xcode's macOS App template. After that, prefer editing Swift source, docs, scripts, plist files, and `.xcconfig` files.

Codex should not casually edit:

```text
WorkingMemorySnapshot.xcodeproj/project.pbxproj
```

Codex may edit it only when:

- adding required files/resources to the target
- adding or updating `.xcconfig` linkage
- linking a required system library
- adding a test target later
- explicitly instructed to update project configuration

If Codex edits `project.pbxproj`, it must mention that in its final summary.

## Build Configuration Files

Build settings live in checked-in `.xcconfig` files:

```text
Config/
  Shared.xcconfig
  Debug.xcconfig
  Release.xcconfig
```

`Shared.xcconfig` pins product identity, macOS deployment target, Swift language mode, versions, the explicit Info.plist path, app icon, automatic signing style with no shared development team, and system SQLite linking.

`Debug.xcconfig` keeps builds local and fast. `Release.xcconfig` enables hardened runtime for later internal release checks. App Sandbox remains off for MVP.

Do not enable warnings-as-errors during MVP work.

## Info.plist

Use an explicit checked-in plist:

```text
WorkingMemorySnapshot/Resources/Info.plist
```

It must include `NSAllowsLocalNetworking` for local LM Studio HTTP access and must not use `NSAllowsArbitraryLoads`.

The default LM Studio URL is:

```text
http://localhost:1234/v1
```

## Signing, Sandbox, and Entitlements

For MVP Debug builds:

```text
App Sandbox: OFF
Hardened Runtime: OFF
Compile signing requirement: disabled by scripts/check.sh
```

For Release builds:

```text
Hardened Runtime: ON
App Sandbox: OFF for internal non-distributed builds
```

Sandbox migration is deferred until there is a dedicated milestone. When App Sandbox is enabled later, the app will need security-scoped bookmarks, network client entitlement review, and a subprocess/file-access validation pass.

Do not enable App Sandbox during MVP feature work unless explicitly requested.

## SQLite Build Configuration

Use macOS system SQLite for v0.

The app links SQLite with:

```text
OTHER_LDFLAGS = $(inherited) -lsqlite3
```

Swift code may use:

```swift
import SQLite3
```

Do not add GRDB, SQLite.swift, SwiftData, Core Data, Realm, or another database dependency during MVP work unless explicitly approved.

## Local AI Build Boundary

The app must compile without LM Studio running.

The build must not download models, start LM Studio, call LM Studio, require LM Studio to be installed, or require internet access.

LM Studio failures are runtime/settings issues, not build failures.

## Required Scripts

Canonical validation:

```bash
./scripts/check.sh
```

Fast validation:

```bash
./scripts/check.sh --quick
```

Diagnostic environment report:

```bash
./scripts/doctor.sh
```

`doctor.sh` is never required for compile success.

`scripts/check.sh` must build the shared scheme with signing disabled:

```text
CODE_SIGNING_ALLOWED=NO
```

## Git Ignore Rules

Do not commit:

- `DerivedData/`
- `.derivedData/`
- `.build/`
- `build/`
- `Build/`
- `xcuserdata/`
- `*.xcuserstate`
- `*.sqlite`, `*.sqlite3`, `*.db`
- `.env` or `.env.*`
- logs and temporary files

Do commit:

```text
WorkingMemorySnapshot.xcodeproj/xcshareddata/xcschemes/
```

## Build Failure Playbook

If `xcodebuild` reports no scheme, share the `WorkingMemorySnapshot` scheme in Xcode and commit it under `xcshareddata/xcschemes`.

If signing requires a development team during compile checks, confirm `scripts/check.sh` passes `CODE_SIGNING_ALLOWED=NO`. Do not hardcode a personal team ID into shared config.

If `import SQLite3` fails, fix target linking to system SQLite. Do not replace the persistence layer.

If ATS blocks local LM Studio HTTP, confirm `Info.plist` contains `NSAllowsLocalNetworking`, not `NSAllowsArbitraryLoads`.

If project folder access fails during MVP, confirm App Sandbox is off and that the folder was selected through `NSOpenPanel`. Do not add security-scoped bookmarks unless the sandbox migration milestone is active.

## Codex Non-Negotiables

Codex must not:

- change bundle identifier, scheme name, Swift mode, or deployment target without explicit instruction
- enable App Sandbox without explicit instruction
- add external Swift packages without explicit approval
- replace SQLite with another persistence layer
- require LM Studio for compile
- commit local databases, DerivedData, user-specific Xcode files, logs, or secrets
- make broad refactors while fixing build configuration

The correct default loop is:

```text
small scoped change
build
diff review
commit
summary
```
