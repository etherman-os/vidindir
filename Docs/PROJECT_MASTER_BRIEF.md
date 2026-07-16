# Vidindir Project Master Brief

**Status:** Product source of truth
**Last updated:** 2026-07-16
**Product:** Vidindir
**Primary platform:** Native macOS

## Authority and change policy

This document is the canonical source of truth for Vidindir's product intent. It defines what the product is, whom it serves, the principles that constrain it, and the long-term direction that implementation plans must preserve.

When another product document conflicts with this brief, this brief wins. Architecture documents may choose practical implementation details, but they may not weaken the immutable rules in this document. A material change to positioning, data ownership, privacy, platform, workspace semantics, or the separation between the library, sync, and download layers requires an explicit decision record and a corresponding update here.

Roadmaps are allowed to stage the vision. They are not allowed to silently redefine it. A feature listed for a future release is direction, not a claim that it exists today.

## Product definition

Vidindir is an open-source, native macOS application for saving video and media links, organizing them into a durable personal library, finding and sharing them later, and downloading a local copy on any Mac when needed.

It is not merely a YouTube downloader or a graphical shell around yt-dlp. Its intended category is:

> Video-first local media library + downloader + synchronized link workspace.

The core experience is:

> **Save → Organize → Find → Share → Discuss → Download**

The primary marketing line is:

> **Save. Organize. Share. Download.**

Supporting lines may include:

- **Your video library, everywhere.**
- **Stop losing great videos in group chats.**
- **The open-source workspace for saving, organizing, sharing, and downloading videos.**

The long-term evolution is deliberate:

> Downloader → Personal video library → Synchronized video library → Collaborative video workspace

At every stage, media links remain the core object.

## The problem

Useful videos are scattered across browser tabs, chats, bookmarks, playlists, and local download folders. Links disappear in message history. Downloads lose their source and context. A file on one Mac says nothing about what is available on another. Existing download tools often assume terminal knowledge, while generic bookmark managers do not understand local media assets or download state.

Vidindir gives the user one durable place to keep the link and its context. A link can exist in the library without being downloaded. A local file can be removed without deleting the library item. Lightweight library data can synchronize across devices while the large media file remains under the user's control on each device.

## Users and modes

### Simple user

The simple user wants a safe, understandable path from a media link to a file:

1. Paste a link.
2. Choose video or audio.
3. Choose a simple quality such as Best, 1080p, or 720p.
4. Choose a destination if necessary.
5. Download and reveal the result in Finder.

The user should not need Homebrew, Terminal, PATH configuration, Python, or knowledge of yt-dlp flags in a public release.

### Library user

The library user saves links before deciding whether to download them. They use Inbox, Collections, Favorites, tags, search, and duplicate detection. They may download the same library item independently on multiple Macs.

### Cross-device user

The cross-device user saves on one Mac and sees the item on another. Links, metadata, organization, and preferences synchronize; local video files and machine-specific paths do not. The user can select **Download on This Mac** when a local copy is needed.

### Team user

The future team user shares media items and collections in a workspace. Conversation stays attached to media through comments, timestamp comments, reactions, mentions, and activity. Vidindir does not attempt to replace the team's general-purpose chat application.

## Product principles

### Local-first

The local database is the primary working copy. The application must open the library, search it, organize it, and manage known local assets without a network connection. Cloud services are synchronization transports, not the owners of the product model.

### Privacy-first

Personal use requires no Vidindir account. Vidindir has no advertising, behavioral analytics, or tracking. A media URL is processed on the device and is not sent to a Vidindir-operated server. The selected source provider, sync provider, and download engine will necessarily receive the requests required to perform their explicit jobs; the UI and documentation must explain that boundary accurately.

A clear privacy view should communicate:

- No analytics
- No tracking
- No ads
- No mandatory Vidindir account for personal local use
- Local-first
- Open source

### Library and downloader are independent

A MediaItem represents a saved source and its metadata. A LocalAsset represents a file on one device. The presence of one never implies the presence of the other.

Removing a local file must not delete the library item. Deleting from the library must be a separate, clearly named operation. A synced item can be downloaded independently on any eligible Mac.

### Database and cloud provider are independent

SQLite is the authoritative local store. SyncCore works through a provider abstraction. CloudKit, Google Drive, a self-hosted service, or a future provider must not dictate the domain schema or become the only place the library can be read.

### UI and yt-dlp are independent

The user interface depends on application-owned domain and download abstractions, never directly on yt-dlp. yt-dlp is the first replaceable DownloadBackend. It may resolve metadata and formats, extract playlists, and perform downloads, but it does not own the library, queue, file tracking, error vocabulary, or UI state.

### Native, calm, and Mac-first

Vidindir should feel like a thoughtful macOS application: fast, minimal, legible, and at home with system conventions. It should use native navigation, toolbars, inspectors, context menus, commands, shortcuts, drag and drop, Quick Look, notifications, and Finder integration where they improve the task.

It should avoid a web-dashboard appearance, excessive gradients, oversized cards, gratuitous animation, and exposing hundreds of engine flags as the main experience.

### Progressive complexity

Common choices remain simple: Video or Audio; Best, 1080p, or 720p. Advanced format selection, engine diagnostics, and technical logs belong in secondary surfaces. Raw terminal output is never the primary error experience.

## Core experience

### Save

A user can add a supported HTTP or HTTPS media URL through Quick Add, paste, clipboard suggestion, drag and drop, or later a share extension. Saving does not require downloading. New links can go to Inbox or directly to a Collection.

### Organize

Collections are the primary durable organization mechanism. An item can belong to multiple Collections. Favorites, tags, and later Smart Collections add orthogonal organization without turning the product into a generic file manager.

### Find

Global search should cover title, creator, URL, Collection, tag, and eventually comments. Search and scrolling must remain responsive in libraries of at least 10,000 MediaItems.

### Share

Initially, sharing can mean opening or copying the source URL and synchronizing a personal library across the user's devices. In shared workspaces it means sharing media records, Collections, and context—not automatically uploading the downloaded video file.

### Discuss

Future collaboration is video-first. Comments, timestamp comments, reactions, mentions, and activity attach to a MediaItem. Selecting a timestamp can open the source or a local file at that moment when supported.

### Download

A saved item can be downloaded on the current Mac as video or audio at a simple quality. Playlist and batch workflows feed a persistent queue. Progress, speed, estimated time remaining, retry, cancel, pause where technically reliable, and Finder reveal are application-owned behaviors.

## Product boundaries

Vidindir is:

- A personal video-link library
- A local media download manager
- A cross-device library synchronization experience
- Eventually, a media-centered collaborative workspace
- Free and open source

Vidindir is not:

- A general-purpose chat product
- A Slack, Discord, or WhatsApp replacement
- A direct-message, voice-call, video-call, or screen-sharing product
- A task-management suite
- A cloud drive or large-file hosting service
- A social network
- A DRM bypass tool
- A promise that every site or protected source can be downloaded

The intended relationship with group chat is complementary: copy or share a useful link from chat into Vidindir, then organize it permanently.

## Platform and technology direction

The production target is a native macOS application built with:

- Swift 6.x
- SwiftUI
- Selective AppKit where native integration requires it
- Swift Concurrency
- A minimum target of macOS 15 or later

Electron and web wrappers are out of scope.

The intended modular project structure separates app composition, domain, persistence, synchronization, downloading, media processing, engine management, design system, system integration, feature modules, tests, tooling, and documentation. Tuist plus Swift Package Manager is the preferred project-generation and dependency approach so parallel contributors do not contend over a monolithic project file.

The current Developer Preview now builds in Swift 6 mode for macOS 15 and places yt-dlp behind application-owned backend and engine-management contracts. It is still a single Swift Package and still relies on Homebrew-installed tools, so it is a useful vertical slice rather than the final modular architecture or public installation experience.

## Core domain model

### Workspace

Every record belongs to a Workspace from the start. Personal use occurs in a **Personal Workspace**; future collaboration occurs in a **Shared Workspace**. This keeps personal and team experiences on one domain model without forcing team UI into early releases.

Minimum conceptual fields include a stable ID, name, type, creation and modification timestamps, and optional deletion timestamp.

### MediaItem

MediaItem is the central domain object. It represents a saved source independent of local download state. Its conceptual fields include:

- Stable ID and Workspace ID
- Original and canonical URLs
- Source type and provider-specific media ID
- Title, creator, description, duration, and thumbnail URL
- Creation, modification, and deletion timestamps
- Metadata resolution status
- Revision and modifying-device information where synchronization requires them

### Collection and membership

A Collection is a durable user-defined grouping such as Programming, Music, Watch Later, or Design Research. Membership is an independent relationship so one MediaItem can appear in multiple Collections and relationships can synchronize without rewriting the item.

### Tag and favorite

Tags provide many-to-many classification. Favorite state is syncable library metadata. Smart Collections later derive views such as Not Downloaded, Downloaded This Week, YouTube Videos, Favorites, Added by Team, and Failed Downloads.

### LocalAsset

LocalAsset records a device-specific file separately from MediaItem. It includes the MediaItem and device IDs, file URL, size, download date, verification date, and status. Local paths never synchronize as if they were valid on another machine.

### DownloadJob

DownloadJob is durable queue state, not transient view state. It records the MediaItem and device, state, progress, speed, estimated remaining time, requested format and quality, and lifecycle timestamps.

### Sync records

Syncable entities use stable UUIDs, revisions, modification timestamps, modifying-device IDs, and tombstones. Relationships are independent records. Scalar conflicts use a deterministic last-write policy initially; deletion uses tombstones. A large shared library.json file and an early heavyweight CRDT design are both rejected.

## Information architecture and key interactions

The primary macOS window uses a sidebar, main content area, and optional inspector.

The long-term sidebar includes:

- Inbox
- Library
- Favorites
- Downloads: Active, Completed, and Failed
- Collections
- Workspaces

Shared Workspace navigation may be visible as a prepared concept before collaboration ships, but unavailable features must never masquerade as working.

### Quick Add

Quick Add is a primary interaction, available through a native command such as Command-L or Command-N. After a link is detected, the application resolves a preview when possible and lets the user choose:

- Destination: Inbox or a Collection
- Action: Save only or Download now
- Format: Video or Audio
- Quality: a simple preset

### Library

Library supports Grid, List, and Compact views over time. A selected item opens an inspector with source metadata, Collections, tags, local status, and distinct actions including Download, Reveal in Finder, Open Source, Copy URL, Remove Local File, and Delete from Library.

### Capture integrations

Clipboard detection is optional and configurable. It offers a lightweight suggestion rather than silently saving. A URL can be dropped on the window, Dock icon, or a Collection. Later, browser, Services, menu-bar, and iPhone share integrations can feed the same application-owned capture path.

### Keyboard model

The intended command vocabulary includes shortcuts for Add Link, Search, Inbox, Library, Downloads, Settings, Preview, and Download. Final key assignments must follow macOS conventions and remain discoverable in menus.

## Download system

### State machine

Each download follows a durable state machine:

> Created → Resolving → Ready → Queued → Downloading → Post-processing → Completed

Side states include Paused, Failed, Cancelled, and Interrupted. Closing and reopening the application must not erase jobs. Interrupted jobs can be retried or resumed when the backend safely supports it.

### Layering

The required dependency direction is:

> App → DownloadCore → DownloadBackend → YTDLPBackend

DownloadCore owns normalized requests, jobs, queue policy, concurrency, state transitions, progress events, errors, and cancellation semantics. YTDLPBackend translates those abstractions into engine operations. No SwiftUI view imports or interprets yt-dlp behavior directly.

yt-dlp output must use structured, tagged output wherever available. Fragile parsing of presentation-oriented terminal text is not a product contract.

### Media processing

FFmpeg belongs to a separate MediaProcessing layer responsible for merge, audio extraction, conversion, metadata embedding, thumbnail embedding, and other post-processing. UI and library modules do not invoke FFmpeg directly.

### Engine packs

Application releases and download-engine releases are independent. Settings should be able to report App Version, Download Engine Version, and FFmpeg Version.

An engine update follows:

> Download → Verify → Install → Health Check → Activate

At least one known-good previous engine is retained for rollback. Engine versions live in versioned Application Support directories and are never activated before integrity verification and a health check succeed.

### Public installation experience

The intended public experience is:

> Download DMG → Drag to Applications → Open → Paste link → Download

A public V1 user must not be required to install Homebrew, run brew install, use pip, open Terminal, or edit PATH. The present Homebrew-backed preparation flow is acceptable only for the Developer Preview and must be replaced by a legally reviewed, verified, signed, and updateable engine-distribution approach before public V1.

### Supported sources and responsible use

The initial backend may work with sources supported by yt-dlp, including sources beyond YouTube, but compatibility changes over time and must not be marketed as universal. Vidindir does not bypass DRM or access controls. Users must download only content they own, content offered under a suitable license, or content they have permission to download, subject to applicable law and platform terms.

## Persistence and synchronization

The local database target is SQLite through GRDB. SwiftData is not the authoritative storage system because the domain must remain portable across sync providers.

The required flow is:

> Local Database → Change Journal → SyncCore → SyncProvider

SyncCore knows the Vidindir sync contract but no provider-specific API. Providers adapt that contract to CloudKit, Google Drive, self-hosted infrastructure, or future systems.

### Personal iCloud sync

The first planned provider for a Personal Workspace is iCloud through CloudKit. Syncable data includes MediaItems, Collections and memberships, tags, favorites, Workspace settings, and relevant preferences.

The following do not synchronize as library data:

- Downloaded video or audio files
- Local file paths
- Active byte-level progress
- Caches
- Temporary files

The same MediaItem can therefore be **Downloaded** on one Mac and **Not downloaded** on another.

### Future providers

Google Drive may later support personal synchronization. Self-hosted and other providers remain possible. Adding a provider must not modify the core domain to mirror that provider's private object model.

## Shared workspaces and collaboration

Shared workspaces extend the same Workspace and MediaItem model used by personal libraries. Members share links, metadata, Collections, comments, reactions, and activity. Downloaded media files stay local and are not automatically uploaded to the shared workspace.

In-scope collaboration capabilities are:

- Shared Collections
- Comments
- Timestamp comments
- Reactions
- Mentions
- Activity feed
- Team Inbox

Communication must remain associated with a MediaItem. The activity feed reports meaningful media events such as adding a video, placing it in a Collection, commenting at a timestamp, or reacting.

General chat, direct messages, calls, screen sharing, task management, and large-file hosting remain out of scope.

## Release horizons

Release labels describe complete user outcomes, not isolated code merges. Detailed gates live in PRODUCT.md.

### Foundation / Developer Preview

Validate the native download experience and establish the documents, interfaces, module boundaries, testing strategy, and release path required for the larger product. The existing Homebrew-backed MP4/MP3 downloader belongs here.

### Public V1

Deliver the best personal native macOS video library and downloader experience, including:

- Native application shell and Quick Add
- Single, playlist, and batch URL capture
- Video and audio download with simple quality selection
- Persistent queue, concurrency control, pause where reliable, cancel, retry, and recovery
- Inbox, Library, Collections, Favorites, and search
- Local file tracking and duplicate detection
- Personal iCloud synchronization of lightweight library data
- Clipboard detection and drag and drop
- Notifications and Finder integration
- Automatic application updates
- Verified automatic download-engine updates and rollback
- A simple DMG installation with no Homebrew or Terminal requirement

### V1.5

Deepen personal workflows with tags, Smart Collections, subtitle and thumbnail download, metadata controls, presets, advanced format selection, Safari or macOS Services integration, menu-bar capture, and timestamp notes.

### V2+

Add shared workspaces, invitations, shared Collections, comments, timestamp comments, reactions, mentions, activity, Team Inbox, additional personal sync providers, and provider options for shared workspaces.

Later possibilities include an iPhone share extension, browser extension, cross-device send-to-device, self-hosted sync, plugin APIs, custom post-processing, and experiments with native download backends.

## Quality bar

Vidindir should remain responsive with libraries of at least 10,000 MediaItems. Search should feel immediate, scrolling should remain smooth, thumbnail loading should use a bounded cache, and synchronization should be incremental.

Download coordination should use Swift Concurrency with isolated ownership of mutable queue state. UI presentation state is a projection of durable application state; it is not the source of truth for a running download.

Each module owns tests appropriate to its contract. Priority suites include persistence, migrations, synchronization conflicts, download state transitions, URL canonicalization, duplicate detection, engine updates and rollback, and integration boundaries. Real-network yt-dlp tests must be isolated from deterministic unit tests.

Errors shown to users must be actionable and provider-neutral. A failure should explain likely categories such as private, sign-in required, unavailable, unsupported, network, disk, or engine problems. Raw technical details remain available in an Advanced diagnostics surface.

## Settings direction

Settings should grow into these clear groups:

- General
- Downloads
- Library
- Sync
- Engine
- Integrations
- Privacy
- Advanced

Advanced may expose engine versions, engine location, logs, reset, health check, and rollback. Technical controls must not dominate the default workflow.

## Repository and contributor model

Parallel work must be organized around owned paths and stable public interfaces. Work packages define owned paths, public interfaces, acceptance criteria, required tests, and forbidden paths. Contributors do not casually change another module's public API; cross-cutting changes require coordination and, when architectural, a decision record.

Before broad parallel feature implementation, the repository should establish and maintain:

- PRODUCT.md
- ARCHITECTURE.md
- DATA_MODEL.md
- SYNC_PROTOCOL.md
- DOWNLOAD_ENGINE.md
- UI_SPEC.md
- DESIGN_SYSTEM.md
- AGENT_RULES.md

## Immutable rules

The following rules are non-negotiable unless this master brief is deliberately revised:

1. **The library does not depend on the downloader.**
2. **The database does not depend on the cloud provider.**
3. **The UI does not depend on yt-dlp.**
4. **Video files are local; links and lightweight metadata are syncable.**
5. **A MediaItem and a device's LocalAsset are different records with different lifecycles.**
6. **Personal and team experiences share the Workspace model.**
7. **Collaboration revolves around MediaItems, not general-purpose chat.**
8. **Personal local use does not require a Vidindir account.**
9. **Public V1 does not require Homebrew, Terminal, pip, or manual PATH configuration.**
10. **Provider-specific and engine-specific behavior stays behind replaceable interfaces.**
11. **Unavailable future features are never presented as already shipped.**
12. **Vidindir does not bypass DRM and does not encourage unauthorized downloading.**

## One-sentence destination

> Vidindir is the open-source, local-first Mac workspace for saving, organizing, finding, sharing, discussing, and downloading video links while keeping downloaded files under the user's control.
