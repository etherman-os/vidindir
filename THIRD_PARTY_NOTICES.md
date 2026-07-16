# Third-party notices

Vidindir source code is MIT licensed. It invokes separately installed tools and does
not bundle their executable files in the repository or generated app bundle.

## yt-dlp

Project: <https://github.com/yt-dlp/yt-dlp>

The yt-dlp source project is primarily released under the Unlicense. Some binary
distributions and optional components include software under additional terms.
Consult the license files shipped with the exact yt-dlp installation in use.

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
install missing formulae after an explicit user action.
