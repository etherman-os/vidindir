# Vidindir

**Save. Organize. Share. Download.**

Vidindir is an open-source, native macOS video library and download manager.
The long-term product is a local-first home for media links: save them to an
inbox, organize them into collections, find them later, sync lightweight
metadata between Macs, and download a local copy whenever you need one.

[![CI](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml/badge.svg)](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-4f8f8b.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-1f2928.svg)](https://support.apple.com/macos)

> Vidindir is under active development. The current developer preview delivers
> the first vertical slice—safe MP4/MP3 downloads—while the library, persistent
> queue, engine packs, and sync architecture are being built.

## Why Vidindir?

Great videos disappear in browser tabs, bookmarks, and group chats. A downloaded
file solves only half the problem; a cloud bookmark with no local copy solves the
other half. Vidindir treats the media link and each device's local file as
separate things.

```text
SwiftUI Tutorial

Library             Saved ✓
MacBook Pro         Downloaded ✓
Mac mini            Not downloaded
```

The product is guided by three strict boundaries:

- The library does not depend on the downloader.
- The database does not depend on a cloud provider.
- The UI does not depend on `yt-dlp`.

## Current developer preview

Available today:

- Native SwiftUI macOS app
- Single-link MP4 video and MP3 audio downloads
- Public links supported by the installed `yt-dlp` extractor set, including
  YouTube and X/Twitter
- A separate remembered destination folder for each format
- Structured progress, speed, ETA, cancellation, technical details, and Finder reveal
- Local recent-download history
- Backend-neutral `DownloadBackend` and `DownloadEngineManaging` contracts
- Safe process invocation without a shell or URL argument injection
- Drag-to-Applications DMG packaging and optional signing/notarization workflow

Not implemented yet:

- Inbox, library, collections, favorites, search, or duplicate detection
- Persistent multi-item queue, pause/resume, playlists, or batch downloads
- Bundled, verified engine packs and automatic engine rollback
- iCloud sync, shared workspaces, comments, or team features

Those items are intentionally tracked in the product and architecture documents
instead of being presented as finished features.

## Product documentation

The source of truth is [PROJECT_MASTER_BRIEF.md](Docs/PROJECT_MASTER_BRIEF.md).
Derived specifications:

- [Product and release scope](Docs/PRODUCT.md)
- [Architecture and module boundaries](Docs/ARCHITECTURE.md)
- [Data model](Docs/DATA_MODEL.md)
- [Sync protocol](Docs/SYNC_PROTOCOL.md)
- [Download engine](Docs/DOWNLOAD_ENGINE.md)
- [Interface specification](Docs/UI_SPEC.md)
- [Design system](Docs/DESIGN_SYSTEM.md)
- [Rules for parallel contributors and agents](Docs/AGENT_RULES.md)

## Build from source

Requirements:

- macOS 15 or later
- Swift 6.0 or later
- Homebrew for the current developer-preview engine setup

```bash
git clone https://github.com/etherman-os/vidindir.git
cd vidindir
swift test
chmod +x Scripts/package_app.sh Scripts/create_dmg.sh
./Scripts/package_app.sh
./Scripts/create_dmg.sh
```

Outputs:

```text
dist/Vidindir.app
dist/Vidindir-0.1.0-macOS.dmg
```

Local builds are ad-hoc signed. Public releases require a Developer ID
certificate and Apple notarization. Without those credentials, the release
workflow keeps the architecture-labeled DMG as a maintainer-only workflow
artifact instead of publishing it as a GitHub Release.

### Current engine setup

The developer preview locates or prepares these separate tools:

```bash
brew install yt-dlp ffmpeg deno
```

Users should not need Homebrew in the public product. The planned Engine Pack
system will download a versioned package, verify its digest and signature, run a
health check, activate it atomically, and retain the previous version for
rollback. See [DOWNLOAD_ENGINE.md](Docs/DOWNLOAD_ENGINE.md).

## Safety and privacy

Vidindir has no analytics, advertising, tracking, or mandatory account. Pasted
URLs are sent directly to the selected media service by the local download
engine; they are not sent to a Vidindir server.

The app never passes pasted text to `/bin/sh` or `zsh -c`. Executables and
arguments are supplied separately to `Foundation.Process`, global `yt-dlp`
configuration is ignored, and the source URL appears after the `--` option
terminator.

Use Vidindir only for content you own, content under an open license, or content
you have permission to download. Platform terms and copyright law still apply.
Vidindir does not bypass DRM or access controls.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[AGENT_RULES.md](Docs/AGENT_RULES.md) before making changes. Architectural
changes require an ADR rather than an uncoordinated public API edit.

## Third-party software

Vidindir is independent and is not affiliated with YouTube, X, or any other
supported platform. The current preview invokes separately installed
[yt-dlp](https://github.com/yt-dlp/yt-dlp),
[FFmpeg](https://ffmpeg.org/), and [Deno](https://deno.com/). Their licenses are
separate from Vidindir's. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Vidindir is released under the [MIT License](LICENSE).
