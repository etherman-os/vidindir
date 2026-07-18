# Vidindir

Vidindir is a native, open-source media library and downloader for macOS. Save
video links before they disappear, organize them into collections, find them
later, and download a local MP4 or MP3 whenever you need it.

> **Save. Organize. Find. Download.**

[![CI](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml/badge.svg)](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-4f8f8b.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-1f2928.svg)](https://support.apple.com/macos)

Built by [etherman-os](https://github.com/etherman-os) · [etherman.org](https://etherman.org)

## Project status

Vidindir is in active pre-release development. The native library is already in
place, but there is no stable end-user release yet. We are holding the first
release until installation, engine packaging, queue controls, and cross-device
sync meet the same standard as the core library.

The current build includes:

- A local-first Inbox, Library, Favorites, Collections, and instant search
- Grid, list, and compact views with a native macOS inspector
- Save-only and download-now flows from the same Quick Add window
- MP4 video and MP3 audio with Best, 1080p, and 720p choices
- Link metadata previews, duplicate detection, and canonical URLs
- Durable SQLite storage for media, collections, downloads, and local files
- Restart-safe download history, progress, cancellation, and Finder reveal
- Clipboard link suggestions and drag-and-drop capture
- Remembered download folders and automatic engine maintenance
- Automatic application-update checks through a signed update feed
- No account, advertising, analytics, or tracking

Downloaded files stay on the Mac. The library remains useful even when a file
has not been downloaded or the download engine is unavailable.

## Using the current preview

Once a preview build is running:

1. Press <kbd>⌘L</kbd> or choose **Add Link**.
2. Paste a supported public media link.
3. Choose Inbox, Library, or one of your Collections.
4. Select **Save only** or **Download now**.
5. For a download, choose Video or Audio, quality, and a destination folder.

Saved links are available immediately in the local library. Vidindir resolves a
title, creator, duration, and thumbnail when the source provides them. Downloads
show progress, speed, estimated time remaining, and optional technical details.
Completed files can be revealed in Finder.

The current preview uses Homebrew for its download engine. If the tools are not
ready, select **Prepare Engine** in the app. This is a one-time preparation, not
something users repeat for every update.

## Automatic updates

Vidindir treats the app and its download engine as two independent update
channels.

### Download-engine updates

The current preview checks its Homebrew-managed engine automatically. A
successful check is performed at most once every 24 hours while Vidindir is
running; failed checks use a shorter retry schedule. The updater refreshes
Homebrew's package information and upgrades only outdated Vidindir components:
`yt-dlp`, FFmpeg, and Deno. Homebrew may also update a required dependency when
one of those formulae needs it.

It does not uninstall and reinstall the app, and it never touches downloaded
media. If the Mac is off or Vidindir is closed when a check would have happened,
the app checks after it is opened again.

The public release will use managed, versioned engine packages instead of asking
people to install Homebrew. A new engine must be verified and health-checked
before activation, with the previous working version retained for rollback.

### Vidindir app updates

Vidindir checks for app updates in the background. Every update is verified
before installation, and the app waits for active downloads and engine work to
finish before restarting. The public update channel will remain empty until the
first release passes its qualification checks.

GitHub prereleases are not offered through the stable automatic-update channel.
Anyone testing a prerelease should install a newer preview manually.

macOS may block a preview build the first time it is opened. If you trust the
download, try to open it once, then go to **System Settings → Privacy & Security**
and choose **Open Anyway**.

## Supported websites

Vidindir currently uses [yt-dlp](https://github.com/yt-dlp/yt-dlp) as its download
backend. It can therefore handle public links from many supported services,
including:

- YouTube videos and Shorts
- Public video posts on X/Twitter
- Many other public video and audio websites supported by yt-dlp

No downloader can guarantee that every link will work forever. Private media,
sign-in-only content, removed posts, regional restrictions, DRM-protected
streams, and sudden website changes can prevent a download. Vidindir does not
bypass DRM, authentication, or access controls.

## Privacy and responsible use

Vidindir has no advertising, analytics, tracking, or mandatory account. Downloads
run locally. Pasted URLs go from the local engine to the media service; they are
not sent to a Vidindir server.

Vidindir stores the library, download records, local-file status, and preferences
on the Mac. It connects to a pasted media website to resolve or download the
link, to GitHub for app updates, and—in the current preview—to Homebrew and the
engine's required component sources when preparing or updating download tools.

Use Vidindir only for media you own, media offered under a suitable license, or
media you have permission to download. Users remain responsible for the source
website's terms and applicable copyright law.

## Build from source

Source builds are currently the supported way for contributors to try Vidindir.
You need macOS 15 or later, Swift 6 or later, and Homebrew for the preview engine.
Release packaging targets both Apple silicon and Intel Macs.

```bash
git clone https://github.com/etherman-os/vidindir.git
cd vidindir
swift test
swift run Vidindir
```

To create a local app bundle and DMG for testing:

```bash
chmod +x Scripts/package_app.sh Scripts/create_dmg.sh
./Scripts/package_app.sh
./Scripts/create_dmg.sh
```

Generated packages are written to `dist/`. Local packages are ad-hoc signed and
are not public releases.

## Troubleshooting the preview

If Vidindir reports that its engine is not ready, select **Prepare Engine**. If
an installed component fails its health check, select **Repair Engine** instead;
Vidindir will reinstall only the unhealthy Homebrew-managed component and will
verify the complete engine before downloads are enabled again.

If the app says a component needs manual repair, make sure
[Homebrew](https://brew.sh) is available, then run only the matching command and
select **Recheck Engine** in Vidindir:

```bash
brew reinstall yt-dlp
brew reinstall ffmpeg
brew reinstall deno
```

When a previously working website starts failing but the engine is healthy,
leave the app open for its automatic engine check and try again later; the site
may require a newer yt-dlp release.

The preview is designed for accessible public links. It does not automatically
import browser cookies or credentials. When reporting an issue, include the
macOS and Vidindir versions, the source website, and the visible technical
details. Never post private URLs, cookies, access tokens, or personal file paths.

## Contributing

Contributions and bug reports are welcome. Please read the
[contribution guide](CONTRIBUTING.md) before changing public interfaces or major
module boundaries, and use [GitHub Issues](https://github.com/etherman-os/vidindir/issues)
for reproducible bugs and focused feature proposals.

Vidindir is independent and is not affiliated with YouTube, X, or any other
supported platform. Third-party components keep their own licenses; details are
available in the repository's third-party notices.

## License

Vidindir is released under the [MIT License](LICENSE).
