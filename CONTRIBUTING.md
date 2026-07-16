# Contributing to Vidindir

Thanks for helping improve Vidindir. Small, focused pull requests are easiest to
review and maintain.

## Development

```bash
swift test
swift run Vidindir
```

To create an app bundle:

```bash
chmod +x Scripts/package_app.sh
./Scripts/package_app.sh
```

## Pull request checklist

- Explain the goal and the user-visible effect of the change.
- Add tests for new behavior.
- Confirm that `swift test` passes.
- Check interface changes in both light and dark appearances.
- Do not construct shell commands; invoke external tools with
  `Process.executableURL` and separate arguments.
- Do not add DRM bypasses or authorization circumvention. Playlist and batch
  downloads must require an explicit user action and enforce documented limits.

## Bug reports

Include the macOS and Vidindir versions, selected format, and a process log with
personal information removed. Do not paste links to copyrighted content into a
public issue.
