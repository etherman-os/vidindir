# Third-party notices

Vidindir source code is MIT licensed. The generated app bundle includes the
Sparkle update framework. Download-engine tools are installed separately in the
current preview and are not bundled in the repository or app.

## Sparkle

Project: <https://github.com/sparkle-project/Sparkle>

Sparkle is distributed under the MIT License. Vidindir embeds Sparkle to check,
verify, and install application updates from its signed update feed.

## yt-dlp

Project: <https://github.com/yt-dlp/yt-dlp>

The yt-dlp source project is primarily released under the Unlicense. Some binary
distributions and optional components include software under additional terms.
Consult the license files shipped with the exact yt-dlp installation in use.

## yt-dlp EJS

Project: <https://github.com/yt-dlp/ejs>

Vidindir currently allows yt-dlp to fetch its matching external JavaScript
challenge component from npm when a supported site requires it. The project
source is released under the Unlicense; packaged distributions can also contain
ISC-licensed meriyah and MIT-licensed astring code. Consult the notices shipped
with the exact component version in use.

## FFmpeg

Project: <https://ffmpeg.org/>

FFmpeg licensing depends on the build configuration and may be LGPL or GPL.
Vidindir uses the separately installed Homebrew formula and does not redistribute it.

## Deno

Project: <https://deno.com/>

Deno is released under the MIT License. It is used by yt-dlp for supported
JavaScript challenge processing.

## Homebrew

Project: <https://brew.sh/>

Homebrew is released under the BSD 2-Clause License. Vidindir can ask Homebrew to
install missing formulae after an explicit user action. In the current preview,
Vidindir also asks Homebrew to refresh metadata and update its installed yt-dlp,
FFmpeg, and Deno formulae in the background.
