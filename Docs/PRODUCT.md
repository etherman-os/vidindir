# Vidindir Product Plan

**Status:** Working roadmap
**Last updated:** 2026-07-16
**Product source of truth:** PROJECT_MASTER_BRIEF.md

## Purpose

This document turns the full Vidindir vision into release gates that can be built and verified in sequence. It does not reduce the vision. It separates what exists today from what must be true before the product can honestly use the labels Developer Preview, Public V1, V1.5, and V2+.

The product promise is:

> **Save → Organize → Find → Share → Discuss → Download**

The first public release focuses on the complete personal loop. Shared discussion is designed into the domain model from the beginning and delivered later, after the personal library, local download, and sync foundations are reliable.

## Current status

Vidindir is currently a focused native SwiftUI download prototype. It is useful as a Developer Preview and as evidence that the basic local download interaction can work. It is not yet the personal media library described by the master brief, and it is not ready to be positioned as Public V1.

### Implemented in the current prototype

- A native SwiftUI macOS window
- Paste and validate one HTTP or HTTPS media link
- MP4 video and MP3 audio choices
- A separately remembered destination folder for each format
- yt-dlp command construction with structured progress and final-path events
- FFmpeg-backed merge or audio conversion through yt-dlp
- Live progress, speed, estimated time remaining, cancellation, and Finder reveal
- A small local download history stored in user defaults
- Detection of yt-dlp, FFmpeg, and Deno
- User-initiated installation of missing tools through Homebrew when Homebrew is present
- A responsible-use notice and local technical log
- Process execution without passing a pasted URL through a shell
- Product-owned `DownloadBackend` and `DownloadEngineManaging` contracts with yt-dlp behind an adapter
- Swift 6 language mode with a macOS 15 deployment target
- Unit tests around command construction, binary discovery, event decoding, process framing, preferences, and tool setup
- Basic packaging and continuous-integration scripts

### Partial or Developer Preview quality

- Source support is inherited from yt-dlp, so some non-YouTube links may work, but Vidindir has no product-level compatibility catalog, metadata preview, or support guarantee.
- Packaging produces an ad-hoc-signed app and a verified drag-to-Applications DMG; a public release still requires Developer ID signing and notarization.
- Errors and logs exist, but the product-level error taxonomy and recovery experience are incomplete.
- History records downloads, but it is not a MediaItem library and does not establish durable local-asset tracking.
- The current package uses the intended Swift 6 and macOS 15 baseline, but remains a single-package prototype rather than the planned Tuist and multi-module workspace.

### Not implemented yet

- Inbox, Library, Favorites, Collections, tags, or global search
- Workspace-based domain records
- SQLite and GRDB persistence, migrations, or change journal
- URL canonicalization and product-level duplicate detection
- Save-only behavior independent of download
- Metadata preview and simple quality selection
- Playlist or batch capture
- A persistent multi-job queue, concurrency control, pause, retry, or restart recovery
- Device-aware LocalAsset records and file verification
- Clipboard suggestions, drag and drop, or broader capture integrations
- iCloud or any other sync provider
- Engine packs, integrity verification, health checks, rollback, or engine updates
- Automatic application updates
- A public installation path that does not require Homebrew or Terminal
- Shared workspaces or collaboration

### Honest release label

The correct current label is **pre-release Developer Preview prototype**. The Homebrew-backed tool setup is intentionally not the intended Public V1 engine experience. Public V1 must be a signed, notarized application that can prepare and update its verified engine without asking an ordinary user to install Homebrew, use Terminal, run pip, or edit PATH.

## Product outcomes

Vidindir succeeds when a person can:

1. Save a useful media link before it disappears.
2. Organize and find it later without depending on the original chat or browser tab.
3. Decide independently whether a local copy is needed on each Mac.
4. Download it with a simple, native experience and understand failures without reading terminal output.
5. Keep lightweight library data consistent across their Macs while large media files remain local.
6. Eventually share the item and discuss specific moments with a team without turning Vidindir into general chat.

## Primary user stories

### Fast downloader

As a person who does not use command-line tools, I want to paste a permitted media link, choose Video or Audio and a simple quality, and receive a file in a remembered folder.

### Save-first researcher

As a person collecting tutorials, references, or music, I want to save a link to Inbox without downloading it, then classify and find it later.

### Multi-Mac user

As a person with more than one Mac, I want a saved item and its organization to appear on my other Mac while deciding separately where the actual media file is downloaded.

### Future collaborator

As a teammate, I want to add a video to a shared Collection and discuss a specific timestamp so useful context does not disappear in group chat.

## Product-wide non-goals

- Bypassing DRM, access controls, paywalls, or provider restrictions
- Guaranteeing that every website or every yt-dlp extractor always works
- General-purpose chat, direct messages, voice or video calls, or screen sharing
- Task and project management
- Hosting or automatically synchronizing downloaded media files
- Becoming a generic cloud drive, social network, or browser replacement
- Reproducing the full yt-dlp option surface in the primary UI
- Requiring an account for personal local use
- Sending URLs, behavior, or library activity to Vidindir-operated analytics systems

## Measurement without surveillance

Vidindir has no behavioral analytics or tracking. Product quality is measured through automated tests and benchmarks, controlled usability sessions, explicit opt-in feedback, locally exportable diagnostics, and public issue reports. No release metric justifies silent telemetry.

## Milestone 0 — Foundation / Developer Preview

### Goal

Validate the simple link-to-file experience, establish trustworthy process execution, and prepare the architectural and documentation contracts needed to grow into a library without coupling the product to yt-dlp or Homebrew.

### Audience

Contributors, technically comfortable early testers, and reviewers who understand that Homebrew dependencies and ad-hoc packaging are temporary Developer Preview constraints.

### Scope

- Preserve and harden the current single-link MP4/MP3 flow.
- Keep format-specific destination memory, progress, cancellation, final-path handling, and Finder reveal reliable.
- Maintain shell-free process invocation and structured engine event parsing.
- Establish the product, architecture, data model, sync, download engine, UI, design system, and contributor rule documents before broad parallel implementation.
- Evolve the existing backend and engine-management contracts into a dedicated DownloadCore module without leaking engine details into feature or UI modules.
- Define Workspace, MediaItem, LocalAsset, DownloadJob, Collection, and sync-record semantics before persistence implementation.
- Decide the legally and operationally viable public engine-pack distribution model.
- Keep real-network smoke tests separate from deterministic unit tests.

### Developer Preview user stories

- As an early tester, I can download an authorized URL as MP4 or MP3.
- As an early tester, I can select different default folders for video and audio and see those choices remembered.
- As an early tester, I can see progress, cancel a running job, and reveal the completed output.
- As a contributor, I can change command construction and event decoding with deterministic test coverage.
- As an architect, I can implement library features against application-owned interfaces instead of importing yt-dlp details into UI code.

### Acceptance criteria

- The package builds and its deterministic test suite passes on the documented Developer Preview toolchain.
- A manual smoke test with content the tester is authorized to download completes for both MP4 and MP3.
- A pasted URL is always passed as an opaque process argument after an option terminator and never evaluated by a shell.
- Cancellation leaves the app responsive and records a terminal job state.
- The final output path reflects post-processing rather than a guessed filename.
- Missing-tool setup is explicitly initiated by the user and accurately explains its Homebrew dependency.
- The app never presents Homebrew setup as the final Public V1 installation experience.
- Foundation documents define ownership, dependency direction, state machines, migration strategy, sync contract, and release boundaries sufficiently for parallel modules to proceed.
- A decision and prototype exist for verified engine installation, health checking, activation, and rollback before Public V1 engine work is declared unblocked.

### Exit criteria

Foundation is complete only when the prototype remains stable and the new library, persistence, sync, and engine modules can be implemented without placing yt-dlp calls in UI code, cloud types in the domain model, or local files inside sync payloads.

### Current milestone status

**In progress.** The single-download core, backend adapter boundary, Swift 6/macOS 15 baseline, safety tests, and foundation documents exist. The broader module split, domain persistence, public engine distribution, and production signing are not yet complete.

### Non-goals for this milestone

- Consumer-ready installation
- A claim of Public V1 quality
- Library or cross-device sync
- Playlist, batch, or persistent multi-job queue
- Shared workspaces

### Success measures

- All deterministic tests pass in continuous integration.
- Ten consecutive authorized manual smoke runs for each format complete without app crashes on the supported Developer Preview setup.
- Cancellation, invalid URL, missing binary, unwritable folder, and post-processing failure paths each have a reproducible test or manual test case.
- A new contributor can build and test from the documented repository steps without undocumented project configuration.

## Milestone 1 — Public V1: Personal Library + Downloader

### Goal

Deliver the best personal, native macOS video-library and downloader experience: easy to install, useful offline, privacy-preserving, and synchronized across a person's Macs without synchronizing the downloaded media files.

### Audience

Ordinary Mac users as well as advanced users. Terminal knowledge is not assumed.

### Delivery sequence

Public V1 is one release gate, but implementation should proceed through independently testable vertical slices:

1. **Local library foundation:** Workspace, MediaItem, Collection, Favorite, LocalAsset, DownloadJob, SQLite/GRDB migrations, repositories, and offline app shell.
2. **Capture and organization:** Quick Add, Save only, Download now, Inbox, Collections, Favorites, canonicalization, duplicate handling, and search.
3. **Durable download system:** metadata and format resolution, simple quality presets, batch and playlist intake, persistent queue, bounded concurrency, restart recovery, retry, cancel, and pause where the backend can make an honest guarantee.
4. **Public engine experience:** versioned engine packs, cryptographic verification, health checks, activation, rollback, and no Homebrew requirement.
5. **Personal sync:** change journal, SyncCore, CloudKit provider, conflict rules, tombstones, and device-aware local status.
6. **Mac integration and release hardening:** drag and drop, optional clipboard suggestions, notifications, Finder actions, app updates, accessibility, signing, notarization, and DMG distribution.

### Public V1 user stories

- As a new user, I can install Vidindir from a DMG, move it to Applications, open it, and perform the first save or download without Terminal or Homebrew.
- As a quick-download user, I can paste a link, choose Video or Audio and Best, 1080p, or 720p, then download to a remembered destination.
- As a save-first user, I can add a link to Inbox or a Collection without downloading it.
- As a researcher, I can browse Grid, List, or a practical initial subset, search by title, creator, URL, or Collection, favorite an item, and place one item in multiple Collections.
- As a user pasting the same source twice, I receive an **Already in Library** explanation based on canonical URL or source media ID and can open the existing item.
- As a playlist user, I can review and enqueue a playlist without the UI freezing or creating invisible jobs.
- As a batch user, I can submit multiple URLs and see each as an independent durable job.
- As a user with a running queue, I can inspect Active, Queued, Completed, and Failed jobs, cancel or retry, and safely recover interrupted work after relaunch.
- As a user with two Macs, I can save and organize on one Mac, see the library item on the other, and choose **Download on This Mac** there.
- As a privacy-conscious user, I can understand which information remains local, which library records synchronize through iCloud, and which external provider receives a request when I download.
- As a user managing disk space, I can remove a local file without deleting the library item, or delete the library item through a separate, clearly destructive action.

### Public V1 functional scope

#### Library and organization

- Personal Workspace created automatically
- Inbox, Library, Favorites, Collections, and global search
- MediaItem metadata and resolution status
- Many-to-many Collection membership
- Canonical URL and provider media-ID duplicate detection
- Grid and List presentation, with Compact allowed to follow if necessary without weakening core navigation
- Inspector with source, metadata, organization, local status, and distinct local-file/library deletion actions
- Offline read, search, and organization

#### Downloading

- Single links, playlists, and batches
- Video and audio
- Simple quality choices: Best, 1080p, and 720p when the source exposes them
- Persistent DownloadJobs and state transitions
- Queue and bounded concurrency
- Progress, speed, estimated time, cancel, retry, and interrupted recovery
- Pause only when its semantics can be reliable; otherwise the UI must use an honest stop-and-resume or cancel-and-retry term
- Clear post-processing state
- Device-aware LocalAsset creation and verification
- Notifications and Finder reveal

#### Synchronization

- Incremental local change journal
- Provider-neutral SyncCore
- CloudKit provider for Personal Workspace
- Deterministic scalar conflict handling, independent relationship records, and tombstones
- Sync of links, metadata, Collections, memberships, favorites, Workspace settings, and relevant preferences
- Explicit exclusion of media files, local file paths, active byte progress, caches, and temporary files
- Visible per-device local status that never implies a remote file exists locally

#### Capture and Mac integration

- Quick Add available from a native keyboard command
- Paste and drag URLs into the window and appropriate Collection targets
- Optional, user-controlled clipboard suggestion
- Open Source, Copy URL, Reveal in Finder, and suitable context menus
- Native sidebar, toolbar, inspector, menus, shortcuts, notifications, and accessibility semantics

#### Updates and distribution

- Developer ID signing and Apple notarization
- A simple DMG with drag-to-Applications guidance
- Automatic application updates with integrity validation
- Automatic download-engine updates independent of app updates
- Versioned engine storage, verification, health check, activation, and rollback
- No required Homebrew, Terminal, pip, or PATH configuration

### Public V1 acceptance criteria

#### Installation and first run

- A clean supported macOS account with no Homebrew, yt-dlp, FFmpeg, or Deno installed can install from the release DMG and reach a working Quick Add flow.
- Gatekeeper accepts the notarized application without a bypass procedure.
- The engine is installed or made available through an explicit in-app flow, integrity-checked, health-checked, and reported with a version.
- The first successful save requires no account. The first authorized download requires no command-line action.

#### Data integrity

- Every library record belongs to a Workspace and uses a stable identifier.
- A MediaItem remains usable after its LocalAsset is removed.
- Deleting a MediaItem cannot be triggered accidentally by the remove-local-file action.
- Database migrations are forward-tested from every shipped schema version represented in fixtures.
- A forced quit during download or post-processing does not erase the DownloadJob; relaunch classifies it as interrupted and offers a safe recovery action.
- Duplicate detection is deterministic for covered URL canonicalization fixtures.

#### Download behavior

- Single, batch, and playlist jobs enter the same application-owned state machine.
- No UI view parses raw yt-dlp terminal presentation output or constructs engine flags.
- Queue concurrency never exceeds the configured limit.
- Cancel and retry have deterministic terminal and restart behavior.
- Completed LocalAssets point to existing files and are reclassified if verification later finds the file missing.
- Provider failures are translated into understandable categories with optional technical details.

#### Sync behavior

- Two test Macs or isolated test identities converge after offline edits, reconnect, and incremental sync for the supported conflict matrix.
- Concurrent edits resolve deterministically and relationship changes do not overwrite unrelated scalar fields.
- Deletions propagate through tombstones without resurrecting deleted records during the supported retention window.
- No downloaded media bytes or machine-local file path appear in sync payload tests.
- Sync unavailability never prevents access to the local library.

#### Performance and accessibility

- A fixture library of 10,000 MediaItems opens, scrolls, and searches within the agreed performance budgets on the baseline supported Mac.
- Search results update with a target p95 query time of 100 ms after text input settles against the 10,000-item fixture.
- Common library scrolling remains visually smooth under the same fixture and thumbnail cache bounds are testable.
- The main save, organize, search, download, cancel, retry, and deletion flows are keyboard accessible and have meaningful VoiceOver labels.
- App launch to interactive local library has a target p95 of two seconds on the baseline supported Mac with a warm local database.

#### Privacy and release readiness

- A repository and binary audit finds no analytics, advertising SDK, or hidden account requirement.
- Privacy copy distinguishes Vidindir services from requests made to a source provider, iCloud, and download-engine update host.
- Release artifacts include licenses and notices for distributed components.
- Update signatures, engine signatures or hashes, rollback, and compromised-update response are documented and tested.
- All release-blocking automated suites pass, and the signed artifact completes a clean-machine smoke matrix.

### Public V1 non-goals

- Shared Workspaces and team invitations
- Comments, reactions, mentions, or activity feed
- Google Drive or self-hosted sync
- iPhone or browser extensions
- Large media-file cloud synchronization
- General-purpose chat
- Plugin API or native extractor replacement
- Exhaustive advanced format controls in the primary flow

### Public V1 success measures

- At least 90% of participants in controlled first-run testing complete a save and an authorized download within three minutes without assistance or Terminal.
- The clean-machine installation matrix passes on every supported macOS release and representative Apple silicon hardware.
- The curated authorized source-compatibility smoke suite reports a clear success or correctly classified unsupported/access error for every case; no case fails with an unexplained raw-terminal-only state.
- The 10,000-item performance budgets pass in continuous performance testing.
- The offline/concurrent/deletion sync matrix converges in all deterministic integration cases.
- A 100-cycle engine update test never activates an unverified or unhealthy engine and successfully rolls back every injected bad update.
- No release-blocking crash, data-loss issue, or security regression remains open at release candidate approval.
- During the initial public stabilization window, issue reports are triaged by severity and published known limitations remain accurate; this process uses no silent product analytics.

## Milestone 1.5 — Personal Workflow Depth

### Goal

Make a proven personal library faster to capture into, richer to organize, and more flexible for advanced download needs without cluttering the simple default experience.

### Scope

- Tags and tag search
- Smart Collections such as Not Downloaded, Downloaded This Week, Favorites, source-based groups, and Failed Downloads
- Subtitle and thumbnail download
- Metadata controls and embedding options
- Download presets
- Advanced format selection behind an Advanced surface
- Safari integration and macOS Services where viable
- Menu-bar Quick Capture
- Timestamp notes for personal use
- Refined Compact view if not included in Public V1

### User stories

- As a researcher, I can apply several tags and build a Smart Collection from useful criteria.
- As an advanced downloader, I can save a preset with subtitle, metadata, and format choices without forcing those controls on every user.
- As a browser user, I can send the current page to Vidindir with minimal interruption.
- As a viewer, I can save a private note at a timestamp and return to that moment in the source or local file.

### Acceptance criteria

- Tags and Smart Collections synchronize through provider-neutral records and do not require schema-specific CloudKit logic in UI or domain code.
- Smart Collection evaluation remains within the V1 search and scrolling performance budgets on the 10,000-item fixture.
- Presets validate against backend capabilities and degrade with a clear explanation when a source lacks the requested format or subtitle.
- Advanced controls remain outside the primary Quick Add path unless a user explicitly chooses a preset.
- Safari, Services, and menu-bar capture routes all use the same canonicalization and duplicate-detection pipeline as in-app Quick Add.
- Timestamp notes remain useful offline and open a source or valid LocalAsset at the intended time when the player or source supports deep linking.

### Non-goals

- Team collaboration
- General browser automation
- Synchronizing downloaded media files
- Exposing arbitrary unvalidated command-line arguments

### Success measures

- Common Quick Add completion time does not regress by more than 10% in controlled V1-versus-V1.5 usability tests.
- Smart Collection and tag queries meet the existing 10,000-item performance budgets.
- Every new capture integration passes the same duplicate and URL-safety test corpus as the main application.
- Advanced preset failures are categorized and recoverable without editing raw command arguments.

## Milestone 2+ — Shared Video Workspaces

### Goal

Extend the proven personal model into a video-first collaborative workspace where teams save links, organize references, and discuss specific moments without moving general chat or large files into Vidindir.

### Scope

- Shared Workspaces and member invitations
- Roles and access control appropriate to shared library records
- Shared Collections and Team Inbox
- Comments and timestamp comments
- Reactions and mentions
- Media-centered activity feed
- Open Source at Timestamp and Open Local Video at Timestamp where supported
- Additional provider work, beginning with Google Drive for personal sync only if its security and conflict model meet the same core contract
- Future provider options for shared workspaces without coupling the domain to one vendor

### User stories

- As a team member, I can add a video link to a Team Inbox with context.
- As a teammate, I can place it in a shared Collection and comment at 12:48.
- As another teammate, I can open the source at 12:48 or download the item on my own Mac.
- As a team lead, I can understand who added, organized, commented on, or reacted to an item through a media-centered activity feed.
- As a privacy-conscious team, we can collaborate on links and metadata without Vidindir automatically uploading downloaded media files.

### Acceptance criteria for the first shared-workspace release

- Personal Workspace behavior and offline personal libraries remain fully functional without joining or signing into a Shared Workspace.
- Authorization is enforced at the sync or service boundary, not only by hiding UI controls.
- Every comment, reaction, mention, and activity record is associated with a MediaItem or an explicit media-library action.
- Timestamp comments preserve their intended time independent of whether a teammate has a LocalAsset.
- A teammate can download a shared MediaItem locally without causing the resulting file or path to synchronize.
- Membership removal prevents future shared synchronization according to the documented security model and does not silently delete unrelated personal data.
- Conflict, deletion, and offline-edit tests cover shared membership and collaboration records.
- No general-purpose chat, direct-message, call, screen-sharing, or large-file-hosting surface is introduced.

### V2+ success measures

- In controlled team studies, participants can retrieve a previously shared reference faster from a Workspace than from a seeded group-chat history.
- At least 90% of timestamp-comment tasks result in the intended source or local playback position in the supported test matrix.
- Shared conflict and authorization integration suites pass with no cross-Workspace data leakage.
- Adding collaboration does not regress the Public V1 personal-library performance and offline acceptance gates beyond agreed budgets.

### Later opportunities, not commitments

- iPhone share extension
- Browser extension
- Cross-device Send to Device
- Self-hosted synchronization
- Plugin API
- Custom post-processing workflows
- Native download-backend experiments

Each opportunity requires its own product and security proposal. Listing it here does not commit it to a release.

## Cross-cutting product requirements

### Trust and legal use

Vidindir supports lawful, authorized uses. It does not bypass DRM. Product copy must avoid implying affiliation with YouTube or any source provider and must not promise universal compatibility. The user should see responsible-use guidance without being blocked by repetitive legal dialogs after informed acknowledgement.

### Error language

Primary errors use product terms and recovery actions. Examples include private or sign-in-required media, unavailable source, unsupported source, network interruption, disk permission or capacity, post-processing failure, and engine failure. Raw engine output is optional technical detail, never the only explanation.

### Data lifecycle

The product must make these actions distinct:

- Remove Local File: removes or forgets the device's LocalAsset while retaining MediaItem.
- Delete from Library: tombstones the MediaItem and its relevant relationships according to sync rules.
- Cancel Download: ends the current DownloadJob without implying either library deletion action.

### Security

- URLs and filenames are untrusted input.
- Engine arguments are constructed without a shell.
- Downloads and post-processing obey explicit destination and file-access rules.
- App and engine updates are independently verified before activation.
- Secrets and provider credentials use platform security facilities and never enter logs.
- Diagnostics redact tokens, cookies, credentials, and sensitive query data by default.

### Performance

The 10,000-item library fixture is the minimum scale target, not an aspirational afterthought. Persistence, search, thumbnail caching, sync, and UI work must include representative scale tests before Public V1.

## Key dependencies and risks

### Engine distribution and licensing

Public V1 depends on a legally reviewed way to distribute or acquire yt-dlp, FFmpeg, Deno, and related components, include required notices, verify integrity, update safely, and roll back. The current Homebrew flow proves functionality but does not resolve public distribution.

### Source volatility

Providers change markup, APIs, access requirements, and anti-abuse systems. Engine updates must be faster and safer than full app releases. Compatibility messaging must remain modest and precise.

### Sandboxing, signing, and file access

Native file access, long-running subprocesses, application sandbox choices, hardened runtime, signing, and notarization must be validated early because they constrain engine packaging and destination bookmarks.

### CloudKit behavior

iCloud availability, quotas, account state, partial failures, and schema deployment create product risk. SyncCore requires deterministic local behavior and provider-neutral fixtures so CloudKit failures do not threaten local data.

### Scope pressure

The full vision is large. Public V1 should not absorb collaboration, browser extensions, or arbitrary advanced engine features. Release gates protect the central personal loop from being diluted.

### Privacy measurement tension

The product needs quality evidence without hidden analytics. Controlled testing, benchmarks, CI, opt-in diagnostics, and public issue processes must be planned and staffed rather than using surveillance as a shortcut.

## Release decision framework

A milestone is complete only when all of the following are true:

- Its user outcome works end to end in the shipped artifact.
- Its acceptance criteria have recorded evidence.
- Required automated, migration, integration, performance, accessibility, security, and clean-install suites pass.
- Documentation describes actual behavior and known limitations.
- Privacy and responsible-use claims match the implementation.
- No critical or release-blocking data-loss, security, installation, update, or crash issue remains open.
- Deferred capabilities are clearly labeled and do not appear enabled.

Shipping a partial feature behind a development flag can be useful, but it does not satisfy a release gate.

## Product decisions that require a master-brief update

The following cannot be changed only in a roadmap ticket:

- Replacing the local-first model with cloud-authoritative storage
- Synchronizing downloaded media files by default
- Requiring a Vidindir account for personal local use
- Coupling domain storage to CloudKit, Google Drive, or another provider
- Coupling UI directly to yt-dlp or FFmpeg
- Turning collaboration into general-purpose chat
- Moving away from a native macOS product to a web wrapper
- Adding analytics, tracking, advertising, or DRM bypass behavior

Any such proposal must first revise PROJECT_MASTER_BRIEF.md through an explicit, reviewed product decision.
