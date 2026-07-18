# Vidindir

Vidindir is a native, open-source macOS app for downloading public video and
audio links. Paste a link, choose MP4 or MP3, choose where to save it, and let
the app handle the download locally.

[![CI](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml/badge.svg)](https://github.com/etherman-os/vidindir/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-4f8f8b.svg)](LICENSE)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-1f2928.svg)](https://support.apple.com/macos)

Built by [etherman-os](https://github.com/etherman-os) · [etherman.org](https://etherman.org)

## Project status

Vidindir is in pre-release development. There is no stable end-user release yet;
the first stable GitHub release is being held until the Public V1 experience is
ready. Tagged test builds may appear under GitHub Releases as clearly labelled
prereleases.

The downloader foundation works today. It includes MP4 and MP3 downloads,
remembered destination folders, progress and speed reporting, cancellation,
recent-download history, Finder reveal, engine preparation, and automatic
engine maintenance. The app is native SwiftUI rather than an Electron or web
wrapper.

The broader library experience is still under development. Public V1 is intended
to make Vidindir a personal, local-first home for media links: save links to an
inbox, organize them into collections, search and find them later, manage a
persistent download queue, track which files exist on the current Mac, and sync
lightweight library data between Macs. The actual downloaded media will remain
on the user's device.

## Using the current preview

Once a contributor build is running:

1. Paste a public video or audio link.
2. Choose **MP4** for video or **MP3** for audio.
3. Choose a destination folder. Vidindir remembers a different folder for each
   format.
4. Select **Download**.

Vidindir shows progress, transfer speed, estimated time remaining, and technical
details. An active download can be cancelled, and a completed file can be shown
in Finder.

The current preview uses Homebrew for its download engine. If the tools are not
ready, select **Prepare Engine** in the app. This is a one-time preparation, not
something users repeat for every update.

## Automatic updates

Vidindir treats the app and its download engine as two independent update
channels.

### Download-engine updates

The current preview checks its Homebrew-managed engine automatically. A
successful check is performed at most once every 24 hours while Vidindir is
running; failed checks can be retried later. The updater refreshes Homebrew's
package information and asks Homebrew to upgrade only the outdated Vidindir
formulae: `yt-dlp`, FFmpeg, and Deno. Homebrew may also update a required
dependency when one of those formulae needs it.

It does not uninstall and reinstall the app, and it never touches downloaded
media. If the Mac is off or Vidindir is closed when a check would have happened,
the app checks after it is opened again.

For Public V1, the goal is to replace this Homebrew dependency with managed,
versioned engine packages. A new engine will be verified and health-checked
before activation, while the previous working version is retained for rollback.

### Vidindir app updates

Vidindir checks for app updates in the background. Every update is verified
before installation, and the app waits for active downloads and engine work to
finish before restarting. The public update channel will stay empty until Public
V1 passes its release checks.

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

Vidindir stores preferences and recent download details locally on the Mac. It
connects to the pasted media website to resolve and download a link, to GitHub
for app updates, and—in the current preview—to Homebrew and the engine's required
component sources, including npm-hosted yt-dlp challenge code, when preparing or
updating download tools.

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
