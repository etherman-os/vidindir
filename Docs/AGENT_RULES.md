# Vidindir Agent Rules

Status: Required collaboration policy
Applies to: human contributors, coding agents, documentation agents, and release automation

## 1. Purpose

Vidindir is designed for parallel development across independent modules. Parallelism is useful only when ownership, contracts, and verification are explicit. These rules define how work is scoped, changed, tested, reviewed, and integrated without turning shared files into conflict zones or eroding the product architecture.

Normative terms are used deliberately:

- **MUST / MUST NOT:** required for merge.
- **SHOULD / SHOULD NOT:** expected unless a documented reason justifies an exception.
- **MAY:** optional.

## 2. Non-negotiable Architecture Rules

Every change must preserve these invariants:

> The library does not depend on the downloader.

> The database does not depend on a cloud provider.

> The UI does not depend on `yt-dlp` or FFmpeg.

> Video files are local. Links and metadata are syncable.

> Personal and shared experiences use the same Workspace model.

> Collaboration revolves around media items; Vidindir is not a general-purpose chat product.

Consequences:

- A `MediaItem` and a `LocalAsset` are separate entities.
- Saving a link must not require downloading a file.
- Removing a local file must not implicitly delete the library item.
- Download progress is device-local and is not treated as shared library state.
- Sync providers adapt to SyncCore; they do not shape the domain model.
- Download backends implement DownloadCore protocols; they do not define feature UI.
- Feature views receive typed state and actions from feature/domain layers. They never construct shell commands or parse process output.

## 3. Source-of-Truth Hierarchy

When sources conflict, the higher item wins:

1. The maintainer’s latest explicit decision and the user-approved `Docs/PROJECT_MASTER_BRIEF.md`.
2. `Docs/PRODUCT.md` for product scope, principles, and release phase.
3. Specialized foundation documents for their domains:
   - `Docs/ARCHITECTURE.md`
   - `Docs/DATA_MODEL.md`
   - `Docs/SYNC_PROTOCOL.md`
   - `Docs/DOWNLOAD_ENGINE.md`
   - `Docs/UI_SPEC.md`
   - `Docs/DESIGN_SYSTEM.md`
   - this document
4. Accepted Architecture Decision Records in `Docs/ADRs/`.
5. Published module interfaces, schema migrations, and cross-module contract tests.
6. Feature acceptance criteria and tests.
7. Current implementation and inline comments.

An ADR may refine the architecture but must not silently contradict the product brief. If two documents at the same level conflict, stop the affected work, identify the conflict to the integration owner, and resolve it in documentation before adding another implementation interpretation.

Implementation is evidence of current behavior, not permission to preserve an accidental design forever.

## 4. Work Package Contract

No agent starts feature implementation without a bounded work package. Every package must state:

```text
Objective
Owned Paths
Public Interfaces
Acceptance Criteria
Required Tests
Forbidden Paths
Dependencies / Inputs
Expected Deliverables
```

### 4.1 Owned Paths

Owned Paths are the only paths the agent may edit without additional coordination. Ownership includes new files within the listed directories unless explicitly excluded.

Rules:

- Do not “helpfully” clean up files outside Owned Paths.
- Read-only inspection outside Owned Paths is allowed when needed to understand contracts.
- If the correct change requires an unowned file, request a scope change from the integration owner before editing it.
- Shared manifests, generated projects, lockfiles, foundation docs, migrations, localization catalogs, and CI workflows require an explicit owner for that task.
- If another agent has active ownership of an overlapping path, coordinate or split the work before editing.

### 4.2 Public Interfaces

Public Interfaces list protocols, models, errors, events, commands, migrations, fixtures, and UI inputs/outputs that other modules may rely on.

An agent:

- MUST implement against the agreed contract.
- MUST NOT make a source-breaking or semantic change to another package’s interface without approval.
- SHOULD propose interface changes as a small contract patch before building dependent implementation.
- MUST document thread-safety, isolation, error, cancellation, persistence, and ownership semantics where they are not obvious.

### 4.3 Acceptance Criteria

Acceptance criteria describe observable outcomes, including failure and cancellation behavior. “Builds successfully” is necessary but is not a sufficient criterion for a feature.

### 4.4 Required Tests

Required Tests identify exact suites or behaviors. The package is incomplete until those tests exist and pass, or the integration owner records a specific approved exception.

### 4.5 Forbidden Paths

Forbidden Paths are explicit boundaries, not suggestions. They commonly include another module’s source directory, `Package.swift`, Tuist manifests, generated `.xcodeproj` files, release/signing files, and unrelated docs.

## 5. Module Boundaries

The target modular layout is:

```text
App/MainApp

Modules/Domain
Modules/Persistence
Modules/SyncCore
Modules/SyncCloudKit
Modules/SyncGoogleDrive
Modules/DownloadCore
Modules/DownloadYTDLP
Modules/MediaProcessing
Modules/EngineKit
Modules/DesignSystem
Modules/SystemIntegration

Features/QuickAdd
Features/Inbox
Features/Library
Features/Collections
Features/Downloads
Features/Search
Features/Workspaces
Features/Settings
```

Until migration to this structure is complete, new code must still follow the same logical dependency direction.

### 5.1 Allowed responsibilities

- **Domain:** provider-neutral entities, value types, validation, canonical identity rules, and domain errors. No SwiftUI, GRDB, CloudKit, Google APIs, `Process`, `yt-dlp`, or FFmpeg.
- **Persistence:** SQLite/GRDB repositories, migrations, and change journal. It depends on Domain and provider-neutral protocols. It does not import cloud-provider implementations.
- **SyncCore:** provider-neutral synchronization contracts, change sets, conflict resolution, revisions, tombstones, and orchestration.
- **SyncCloudKit / SyncGoogleDrive:** provider adapters. They translate remote records to SyncCore contracts and must not become alternate databases.
- **DownloadCore:** download requests, backend protocol, persistent job state machine, queue policy, cancellation/resume capabilities, progress events, and normalized errors.
- **DownloadYTDLP:** `yt-dlp` metadata/format/download adapter and structured event translation. It contains backend-specific arguments and behavior.
- **MediaProcessing:** FFmpeg abstraction for merge, extraction, conversion, and metadata operations.
- **EngineKit:** signed/checksummed engine installation, versioning, health checks, activation, rollback, and retention.
- **DesignSystem:** semantic visual tokens and reusable, domain-agnostic components.
- **SystemIntegration:** clipboard, drag and drop, Finder, notifications, Services, menu bar, and platform bridges.
- **Features:** presentation state and user workflows assembled from public interfaces. Features must not know backend executable paths or provider record formats.
- **MainApp:** composition root, dependency wiring, app commands, scenes, and top-level navigation. Business logic does not accumulate here.

### 5.2 Dependency direction

The intended flow is:

```text
App / Features
      |
      v
Domain + use-case protocols
      |
      +--> Persistence
      +--> SyncCore ----> provider adapters
      +--> DownloadCore -> backend adapters
      +--> MediaProcessing
      +--> SystemIntegration
```

Concrete adapters are injected at the composition root. A lower layer must never import a feature to obtain state or callbacks.

### 5.3 UI and process isolation

UI code MUST NOT:

- Import or invoke `yt-dlp` or FFmpeg.
- Construct command-line flags.
- Inspect executable paths.
- Parse standard output or standard error.
- Infer the durable state machine from progress strings.
- Present raw backend errors as primary user copy.

Backend adapters emit typed, normalized events and errors. DownloadCore owns state transitions. Feature code maps typed state to localized presentation.

## 6. Architecture Decision Records

Create an ADR when a proposed decision:

- Changes a module boundary or dependency direction.
- Adds or replaces a persistent storage, sync, download, media, update, or security mechanism.
- Changes a public interface used by more than one independently owned package.
- Changes database identity, migration, conflict, tombstone, or file-ownership semantics.
- Introduces a third-party runtime dependency or executable.
- Changes supported platforms, minimum OS, packaging, sandbox, signing, or update trust model.
- Makes a product-level tradeoff not already settled by the foundation docs.

ADRs live at:

```text
Docs/ADRs/ADR-NNN-short-kebab-title.md
```

Each ADR contains:

```text
Title
Status: Proposed | Accepted | Superseded | Rejected
Date
Owners
Context
Decision
Alternatives Considered
Consequences
Migration / Rollout
References
```

Rules:

- Write a Proposed ADR before the dependent implementation spreads across modules.
- Obtain maintainer or architecture-owner acceptance before treating it as a contract.
- Do not rewrite accepted history to disguise a changed decision. Add a superseding ADR.
- Small internal refactors that preserve public contracts and behavior do not require an ADR.
- Update affected foundation docs after an ADR is accepted; do not leave two conflicting sources of truth.

## 7. Parallel Workflow

### 7.1 Before editing

1. Read the work package and every directly relevant foundation document.
2. Inspect current repository status and active ownership notes.
3. Confirm Owned and Forbidden Paths.
4. Identify upstream interfaces and use fixtures/mocks if their implementation is not ready.
5. Send interface questions to the owning agent; do not guess silently when a guess would affect another module.

### 7.2 Interface-first sequencing

When several agents depend on a new contract:

1. The owning agent proposes the smallest useful interface and examples.
2. Consumers review naming, isolation, errors, and cancellation semantics.
3. The interface and contract tests land or are frozen for the work cycle.
4. Implementations proceed independently behind the contract.
5. Integration tests verify composition.

Temporary mocks must conform to the real interface. Do not build a second “temporary architecture” inside a feature.

### 7.3 Shared files

Only the designated integration owner edits high-conflict shared files during a parallel work cycle, including:

- `Package.swift`, `Package.resolved`, Tuist manifests, and generated project files.
- App composition and root navigation files.
- Database migration ordering/index files.
- Localization catalogs.
- CI, signing, packaging, and release configuration.
- Foundation documents and cross-module fixtures.

Other agents provide a focused patch, dependency declaration, string list, or integration note to the owner.

### 7.4 Handoff

Every handoff includes:

- Outcome and affected paths.
- Public interface additions or changes.
- Tests run and their results.
- Known limitations or follow-up work.
- Migration, fixture, or integration instructions.
- Confirmation that no secrets or unrelated changes were included.

An agent must distinguish “implemented,” “verified,” and “not tested in this environment.”

## 8. Git Hygiene

- Inspect the working tree before and after work.
- Preserve unrelated user and agent changes. Never discard, reset, or rewrite work you do not own.
- Do not use destructive commands such as `git reset --hard` or broad checkout/restore operations.
- Do not force-push shared branches.
- Keep commits small, intentional, and scoped to one work package or contract.
- Use imperative commit subjects, for example `Add persistent download state transitions`.
- Do not mix mechanical formatting, generated output, dependency updates, and behavior changes in one commit.
- Format only touched code unless a formatting-only task was assigned.
- Do not commit build products, local caches, downloaded media, engines, logs, personal settings, credentials, or signing artifacts.
- Do not edit generated `.xcodeproj` or `.pbxproj` files by hand when Tuist owns generation.
- Lockfile changes must correspond to an intentional dependency change and be owned by the integration task.
- Branch and pull-request history must not contain tokens even if a later commit deletes them. Rotate any exposed credential immediately.

## 9. Testing Rules

### 9.1 Baseline

Every behavior change must have proportionate automated coverage. Every bug fix should first capture the failure in a deterministic test where feasible.

- Unit tests must not require live network access, a real cloud account, a user’s clipboard, or an installed global `yt-dlp`/FFmpeg.
- Use protocol fakes, temporary directories, controlled clocks, deterministic UUIDs, and committed legal fixtures.
- Tests must be safe to run concurrently and must clean their own temporary state.
- Do not weaken assertions, add sleeps, or disable suites to make a change pass.
- Performance-sensitive library queries should include representative large-fixture benchmarks or performance tests.

### 9.2 Required coverage by area

| Area | Minimum expected coverage |
| --- | --- |
| Domain | Validation, URL canonicalization, identity, equality, duplicate detection |
| Persistence | Repository behavior, transactions, migrations forward from every supported version, tombstones |
| SyncCore | Incremental journal behavior, deterministic conflicts, retries, deletion propagation, idempotency |
| DownloadCore | Every legal/illegal state transition, queue ordering, concurrency, cancellation, interruption, recovery |
| DownloadYTDLP | Argument construction, structured event decoding, error normalization, capability detection |
| MediaProcessing | Argument construction, safe paths, cancellation, normalized results |
| EngineKit | Verification, failed health check, atomic activation, rollback, retained previous version |
| Features | Reducer/view-model behavior, loading/empty/error/offline flows, action routing |
| UI | Critical keyboard commands and accessibility identifiers; targeted UI tests for core journeys |

### 9.3 Integration tests

Real backend, provider, or network tests belong in clearly named opt-in suites. They must:

- Use maintainer-approved, stable, downloadable test media or local fixtures.
- Avoid copyrighted or private content without explicit permission.
- Skip with an explicit reason when credentials or tools are unavailable.
- Never print secrets, cookies, signed URLs, or access tokens.
- Avoid depending on a user’s normal Downloads or Application Support directory.

The primary CI suite must remain deterministic without external service availability.

## 10. Secrets and Privacy

Secrets include GitHub personal access tokens, signing certificates/passwords, CloudKit and Google credentials, OAuth refresh tokens, cookies, browser profiles, authorization headers, signed URLs, and private source URLs.

- Never commit, paste into source, add to fixtures, print, snapshot, or include secrets in diagnostics.
- Use Keychain for user credentials and approved encrypted CI secret storage for automation.
- `.env` files are local-only and must be ignored; provide redacted example files when configuration is necessary.
- Do not read browser cookies or profiles without a separately approved, explicit user flow.
- Redact URL query parameters and headers in logs when they may contain authorization data.
- Media URLs, clipboard content, library records, and download history are private user data.
- No feature may add analytics, tracking, advertising, telemetry, or Vidindir-operated URL resolution without an explicit product decision and corresponding privacy documentation.
- Clipboard observation requires user-visible control and follows current macOS privacy behavior.
- Sync providers receive only the data required by the documented sync protocol. Local file paths, active progress, cache, and media files are not synced by default.

If a secret is exposed, stop distribution of the affected output, notify the maintainer, rotate/revoke the credential, and remove it from history using an approved incident process. Deleting it only in the next commit is insufficient.

## 11. Download and Process Safety

Vidindir downloads media only for content the user is authorized to save. The product must not add DRM circumvention or promise access to private/restricted content.

### 11.1 URL input

- Accept remote media input only through explicitly supported schemes, normally `https` and `http`.
- Treat URLs, titles, creator names, filenames, metadata, playlist entries, and backend output as untrusted input.
- Canonicalization must preserve the source identity rules and must not execute or resolve arbitrary local schemes.
- Do not render untrusted HTML in privileged web views.

### 11.2 Subprocess execution

- Launch executables directly with argument arrays using `Process` or a reviewed abstraction.
- Never interpolate URLs, paths, titles, or options into a shell command string.
- Never invoke `/bin/sh -c`, `bash -c`, or `zsh -c` for download/media work.
- Set a controlled environment and executable path. Do not trust arbitrary `PATH` entries for bundled engine execution.
- Capture standard output and error without deadlock, enforce cancellation, and bound retained logs.
- Prefer structured machine-readable output. Parsing human console prose with broad regular expressions is not an accepted backend contract.
- Normalize backend errors before they cross into DownloadCore or UI.

### 11.3 Filesystem safety

- Resolve destination paths through a dedicated file policy.
- Sanitize proposed filenames while preserving meaningful extensions.
- Prevent `..` traversal, absolute-path injection, unsafe control characters, and writes through unexpected symbolic links.
- Write partial output to an app-controlled temporary location and move it atomically after verification where feasible.
- Never overwrite an existing user file without an explicit, tested collision policy.
- Security-scoped bookmark access must be minimal, balanced, and renewed according to platform rules.
- Cancellation and failure clean only temporary artifacts owned by that job; never recursively delete an unverified path.
- “Remove Local File” must verify the exact tracked asset and must not broaden deletion to its containing folder.

### 11.4 Engine updates

- App updates and engine updates are separate trust domains and version streams.
- Engine packages must come from configured trusted endpoints, use HTTPS, and be verified with approved signatures or pinned checksums before installation.
- Install to versioned Application Support directories.
- Health-check before activation and activate atomically.
- Retain the last known-good engine for rollback.
- Never execute a newly downloaded engine before verification.
- Never silently fall back to a global Homebrew/Python binary in production if the documented distribution model requires a managed engine.

## 12. Database and Sync Safety

- SQLite/GRDB is the local source of truth; a provider is not the database.
- All schema changes use ordered, tested migrations. Never edit a migration that has shipped.
- Every syncable entity uses stable identity, revision/modified metadata, and tombstone semantics as defined in the data and sync specs.
- Sync operations must be idempotent and safe to retry.
- Conflict resolution must be deterministic. Device clock assumptions and tie-breakers must be documented and tested.
- Relationships sync as independent records where specified; do not serialize the entire library into one mutable `library.json` blob.
- Real media files, local paths, caches, temporary files, and active download progress must not enter sync payloads unless a future approved protocol explicitly changes that rule.
- Destructive local operations and sync deletions require distinct tests.

## 13. Dependencies and Licensing

- Prefer Apple frameworks and existing approved packages.
- A new runtime dependency requires a stated need, license/security review, maintenance assessment, and ADR when it changes architecture or distribution.
- Pin dependencies according to the release policy; do not add an unbounded branch dependency.
- Record required attribution and license text in the appropriate notices.
- Do not copy code, icons, thumbnails, media, fixtures, or design assets without compatible licensing.
- `yt-dlp` and FFmpeg integration must preserve their licensing and distribution obligations; packaging changes require release-owner review.

## 14. Documentation Rules

- Public interfaces and non-obvious invariants receive concise documentation comments.
- Foundation docs describe durable decisions, not line-by-line implementation.
- User-facing docs use English for the public repository unless a localization task explicitly adds translations.
- Update the relevant doc in the same work package when behavior or a contract changes.
- Do not mark planned features as implemented.
- Examples must use non-secret, non-private, legally reusable placeholder data.
- Links to external documentation should prefer primary sources.

## 15. Definition of Done

A work package is done only when all applicable statements are true:

- Changes remain within Owned Paths, or expanded ownership was approved.
- Acceptance criteria are met, including error and cancellation paths.
- Public interface changes were coordinated and documented.
- Required automated tests pass.
- Relevant build, lint, and targeted integration checks pass.
- No UI layer depends on `yt-dlp`, FFmpeg, provider record types, or shell output.
- Local-file, library, workspace, and sync scope remain distinct.
- Accessibility, localization, dark mode, offline state, and privacy were considered for user-facing work.
- No credentials, private URLs, downloaded media, logs, or unrelated changes are present.
- Documentation and ADRs are updated where required.
- The handoff reports exactly what was and was not verified.

## 16. Stop and Escalate Conditions

Stop the affected work and contact the integration owner when:

- The task requires editing a Forbidden Path or another active owner’s files.
- Two source-of-truth documents conflict.
- A required public interface is missing or semantically unsafe.
- A schema, sync, engine trust, sandbox, signing, or minimum-platform decision lacks an accepted ADR.
- Tests reveal potential user-data loss, deletion outside a tracked asset, credential leakage, or nondeterministic sync conflicts.
- Completing the task would require bypassing security controls, weakening tests, force-pushing, or discarding unrelated work.
- Licensing or authorization for a dependency, fixture, media item, or distribution method is unclear.

Escalation is a normal way to protect shared architecture and user data. It should include the observed facts, affected contract, options considered, and the smallest decision needed to continue.
