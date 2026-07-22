# Vidindir UI Specification

Status: Foundation specification
Platform: macOS 15 and later
Primary framework: SwiftUI, with selective AppKit integration
Product promise: **Save. Organize. Share. Download.**

## 1. Purpose

This document defines the target user experience for Vidindir. It is a product and interaction contract, not a statement that every described feature is currently implemented. Availability by release phase is defined in [Section 17](#17-phased-availability).

Vidindir is a native, local-first video library and download manager. It must feel like a well-made Mac app rather than a terminal wrapper or web dashboard. A first-time user should be able to paste a link and download it without understanding `yt-dlp`, FFmpeg, formats, codecs, or PATH configuration. A returning user should be able to save, find, organize, and download the same media link on any of their Macs.

The primary product loop is:

```text
Save -> Organize -> Find -> Share -> Discuss -> Download
```

The first release emphasizes the personal loop:

```text
Save -> Organize -> Find -> Download
```

## 2. Experience Principles

1. **The link is the library item; the file is a local asset.** A saved item can exist without being downloaded, and deleting a local file must not silently delete the library record.
2. **Simple choices first.** The primary format choices are Video or Audio. The primary quality choices are Best, 1080p, and 720p. Technical format controls belong in Advanced Settings.
3. **Native behavior is the default.** Use standard macOS navigation, toolbars, menus, inspectors, selection, context menus, keyboard shortcuts, drag and drop, alerts, and notifications.
4. **Local-first and useful offline.** The library opens and remains manageable without a network connection. Network-dependent actions explain when they are unavailable.
5. **Privacy is visible and credible.** No account is required for local use. Clipboard inspection is optional. Media URLs are not sent to Vidindir-operated servers.
6. **Progressive disclosure.** New users see one clear action. Advanced users can reach queue controls, engine details, tags, and provider settings without crowding the main flow.
7. **Source-neutral language.** The UI says “media link,” “source,” and “video” where possible. It must not imply that Vidindir only supports YouTube; actual compatibility is determined by the installed download backend.

## 3. Application Shell

### 3.1 Window

The main window uses a three-column `NavigationSplitView`:

```text
Sidebar | Main content | Inspector
```

- Recommended default size: 1180 x 760 points.
- Minimum usable size: 820 x 560 points.
- Sidebar default width: 230 points; resizable within native constraints.
- Inspector default width: 300 points; resizable and independently hideable.
- Preserve window size, position, sidebar selection, inspector visibility, and Library view mode between launches.
- Allow multiple windows only after selection and download coordination semantics are defined. V1 uses one primary library window.

At compact widths, the inspector collapses first. The sidebar follows standard macOS split-view behavior. Hiding a column must never destroy selection or draft state.

### 3.2 Toolbar

The toolbar contains, from leading to trailing where applicable:

- Sidebar toggle.
- Back/forward navigation when the current feature has navigation history.
- Current destination title.
- Add Link button (`plus`), which opens Quick Add.
- Search field or search affordance.
- Library view picker for Grid, List, and Compact modes.
- Inspector toggle.

Only controls relevant to the selected destination are shown. Avoid a permanently crowded toolbar.

### 3.3 Three-column behavior

- **Sidebar:** chooses a query, collection, workspace, or download status.
- **Main content:** presents the selected destination and owns primary selection.
- **Inspector:** presents details and actions for the selected item. With no selection, it is hidden or shows a quiet instructional placeholder.
- Double-clicking a media item performs the most context-appropriate safe action: open the local file when available; otherwise open its details. It must not start an unconfirmed download.
- `Space` opens Quick Look for a local asset. If no local asset exists, it opens a lightweight media preview/details view when supported, or explains that the item must be downloaded.

## 4. Information Architecture

### 4.1 Sidebar structure

The canonical sidebar order is:

```text
Inbox
Library
Favorites

Downloads
  Active
  Completed
  Failed

Collections
  Programming
  Music
  Watch Later

Workspaces
  Personal
  Design Team
```

Settings is opened through `Vidindir > Settings…` (`Command-,`), not as a required sidebar row.

### 4.2 Destination semantics

- **Inbox:** saved items not yet intentionally organized. An unread/new count may be shown when cross-device sync is enabled.
- **Library:** every non-deleted `MediaItem` visible in the current workspace.
- **Favorites:** a filtered view, not a separate copy of an item.
- **Downloads / Active:** resolving, ready, queued, downloading, paused, interrupted, or post-processing jobs.
- **Downloads / Completed:** completed jobs and their local assets on this Mac.
- **Downloads / Failed:** failed jobs with retry and technical-detail actions.
- **Collections:** durable, user-managed many-to-many groupings. Moving between collection views must not move or duplicate underlying media records.
- **Workspaces:** scopes library data. Personal is always present. Shared workspace rows remain hidden until the feature is available, unless a development build deliberately exposes them.

Counts use monospaced digits and appear only when useful. Do not show decorative zero badges.

### 4.3 Selection and workspace scope

Changing workspace changes the scope of Inbox, Library, Favorites, Collections, and Search. Local download jobs remain device-specific but retain their workspace and media context. A destructive action must name its scope when ambiguity is possible.

## 5. Quick Add

Quick Add is the fastest path from a copied URL to a saved or downloaded item.

### 5.1 Entry points

- `Command-L`: canonical Add Link command.
- `Command-N`: equivalent New Media Item command in V1.
- Toolbar Add Link button.
- `File > Add Link…`.
- A supported URL dropped on the window, Dock icon, or collection.
- Clipboard suggestion, when enabled.

If Quick Add is already open, invoking the command focuses and selects the URL field. It does not create a second sheet.

### 5.2 Presentation

Present Quick Add as a focused sheet attached to the primary window. It must remain usable from the keyboard and must not resemble a multi-step installer.

Initial state:

```text
Add Media

[ Paste a video link…                              ]

                                      [Cancel] [Add]
```

The primary action is disabled until at least one syntactically valid `http` or `https` URL is present. A Paste button may appear when the clipboard contains a URL. Never overwrite user-entered text without an explicit paste action.

Resolved state:

```text
Add Media

[ https://example.com/video                       ]

[Thumbnail]  Video title
             Creator · 18:34 · Source

Save to      [Inbox                              v]

Action       ( ) Save only   (o) Download now
Format       [Video                             v]
Quality      [Best                              v]

                                      [Cancel] [Add]
```

### 5.3 Resolution states

URL resolution is asynchronous and cancellable. The sheet supports these explicit states:

- **Empty:** no URL entered.
- **Validating:** local syntax validation; no spinner for imperceptibly short work.
- **Resolving:** source metadata is being requested; keep the form stable and show an inline progress indicator.
- **Resolved:** thumbnail, title, creator, duration, and source are shown when available.
- **Partial metadata:** the link can be saved even if some metadata is unavailable. Use the hostname and a neutral placeholder rather than blocking Save only.
- **Unsupported:** explain that the current engine cannot handle the source. Offer Copy Link and View Technical Details; do not show raw process output in the primary message.
- **Sign-in required/private/unavailable:** show a human-readable cause and recovery action when known.
- **Offline:** allow Save only; disable Download now and explain why.
- **Duplicate:** show when the item was added and where it lives, with Open Existing as the primary action and Add Anyway as a deliberate secondary action.

Closing the sheet cancels metadata work but does not cancel an already-created download job.

### 5.4 Destinations and actions

- The default destination is Inbox unless a drop target or user preference supplies a collection.
- Save only creates or updates the library item without creating a local asset.
- Download now saves the item first, then creates a persistent `DownloadJob` for this Mac.
- Format defaults to the last successful choice, unless a preset or source capability requires a safe fallback.
- Quality defaults to the remembered choice for that format. If unavailable, select the best lower compatible quality and state the adjustment before download begins.
- The download folder is device-local and remembered through Settings. It is not synced as a raw file path.

### 5.5 Batch links and playlists

When multiple URLs are pasted, show the detected count and create one reviewable batch. When a playlist is detected, show the playlist title and item count before adding. V1 may use a concise summary instead of resolving every thumbnail in the sheet. Users must be able to cancel before jobs are created.

## 6. Library and Inbox

### 6.1 Shared behavior

Inbox, Library, Favorites, and Collections share the same media browser component and differ by query and available actions. They support:

- Single and multiple selection.
- Type-to-select where native controls allow it.
- Sort by Date Added, Date Modified, Title, Creator, Duration, and Local Status.
- Filter by source and local status in V1; richer tag and smart filters later.
- Context menus for Download on This Mac, Reveal in Finder, Open Source, Copy URL, Favorite, collection membership, Remove Local File, and Delete from Library.
- Dragging selected items onto a collection to add membership.
- A user collection exposes “Download Collection”. The app loads the complete collection rather than only the visible/search-filtered page, confirms the item count, skips items whose local asset still resolves to a regular file, then creates one FIFO `--no-playlist` job per remaining media item using the current format, quality, and destination. The first queued job anchors the durable batch relationship; cancelling an active batch job also cancels its queued siblings.

Search updates promptly without moving keyboard focus unexpectedly. “No results” is distinct from an empty library.

### 6.2 Grid mode

Grid mode prioritizes visual browsing:

- Adaptive thumbnail cells with a consistent 16:9 media frame.
- Title limited to two lines; creator uses one secondary line.
- Duration overlays the thumbnail using a legible material-backed label.
- Favorite and local-status indicators are visible but quiet.
- Hover reveals only high-value actions; every hover action also exists in a context menu and is keyboard accessible.

### 6.3 List mode

List mode prioritizes scanning and management. Columns are:

```text
Thumbnail | Title | Creator | Duration | Collection | Local Status | Added
```

- Columns are sortable and resizable.
- Optional columns are managed through the header context menu.
- Title is the primary column and must retain a useful minimum width.
- Use native table selection and row density.

### 6.4 Compact mode

Compact mode is a dense single-column browser for large libraries:

- Small thumbnail or source icon.
- One-line title.
- Creator and duration as secondary metadata where width allows.
- Local status at the trailing edge.
- No card background per row.

### 6.5 Empty states

Empty states are calm, specific, and actionable:

- Empty Inbox: “Your inbox is clear.” Secondary text explains that saved links can land here.
- Empty Library: “Build your video library.” Primary action: Add Link.
- Empty Collection: “No videos in this collection.” Primary action: Add Link; secondary hint explains drag and drop.
- No search results: “No results for ‘query’.” Offer Clear Filters, not Add Link as the only action.
- Offline with existing data: show the data normally and place a non-blocking offline indicator in the toolbar or relevant action area.

## 7. Media Inspector

When one media item is selected, the trailing inspector shows:

```text
[Thumbnail]

Title
Creator

Source          YouTube
Duration        18:34
Added           Jul 15, 2026

Collections
Programming, Watch Later

Tags
Swift, Architecture

Local Status
Downloaded on this Mac

[Download on This Mac]
[Reveal in Finder]

Open Source
Copy URL
Remove Local File…
Delete from Library…
```

Rules:

- Use inspector sections and disclosure groups, not a stack of oversized cards.
- Editable title, collections, tags, and favorite state save predictably and expose validation errors inline.
- “Download on This Mac” is shown when no verified local asset exists.
- “Reveal in Finder” and local playback actions are shown only for a verified local asset.
- **Remove Local File** deletes only this Mac’s file and `LocalAsset`; it keeps the `MediaItem`, collections, comments, and synced metadata.
- **Delete from Library** tombstones the `MediaItem` in its workspace. Its confirmation explains whether a local file will be kept or removed and provides an explicit choice when supported.
- With multiple selection, show a summary and only safe batch actions. Never display the first selected item as though it were the only selection.

## 8. Downloads

### 8.1 Job state model

UI state reflects the persistent download state machine owned by DownloadCore:

```text
Created -> Resolving -> Ready -> Queued -> Downloading -> Post-processing -> Completed
```

Side states are Paused, Failed, Cancelled, and Interrupted. UI views do not invent or infer state from progress text.

### 8.2 Active and queued rows

An active row contains:

```text
[Thumbnail] Video title                         82%
            Downloading · 12.4 MB/s · About 14 sec
            [======================-----]
                                      [Pause] [Cancel]
```

- Progress is determinate only when total work is known. Otherwise use an indeterminate indicator and a truthful stage label.
- Speed and time remaining are supplementary and may be hidden when unstable.
- Post-processing has its own stage label and must not appear frozen at 100%.
- Pause appears only when the backend can safely resume the job. Otherwise offer Cancel and Retry without pretending pause is supported.
- Cancelling asks for confirmation only when meaningful partial work or a batch is affected.
- Queue order can be changed through native drag reordering when no dependency prevents it.
- The Downloads toolbar exposes concurrency control in an unobtrusive menu, not as a dashboard widget.

### 8.3 Completed and failed rows

Completed jobs show Show in Finder, Open, and the completed date. If the file has moved or disappeared, replace success with “File missing” and offer Locate or Download Again.

Failed jobs show a short user-facing explanation and Retry. “View Technical Details” reveals a selectable, redacted diagnostic view. Raw logs never replace the friendly explanation.

Example:

```text
Download failed

The video could not be accessed. It may be private,
require sign-in, or no longer be available.

[View Technical Details]                    [Retry]
```

### 8.4 App lifecycle

- Closing the main window does not silently abandon persistent jobs; behavior follows the user’s quit/background preference.
- On relaunch, incomplete jobs become Interrupted until the coordinator verifies whether they can resume.
- Completion notifications are grouped for large batches.
- The Dock progress indicator may summarize active work without becoming the only progress signal.

## 9. Clipboard Integration

Clipboard detection is off until explained and consented to, or is enabled through an explicit Settings choice. It runs only in contexts allowed by current macOS privacy behavior, such as app activation, and must not continuously poll in the background.

When a supported-looking URL is detected, show a lightweight, dismissible suggestion:

```text
Video link detected
Save “SwiftUI Architecture” to Inbox?

[Ignore] [Save]
```

- Do not resolve the URL over the network before the user chooses Save unless the user has enabled automatic preview resolution.
- Ignore applies to the current clipboard value and must not repeatedly nag.
- Never replace clipboard content.
- Never send clipboard contents to Vidindir-operated analytics or servers.

## 10. Drag and Drop

Accepted drop forms are URL objects and plain text containing valid `http` or `https` URLs.

- Drop on the window/main content: open Quick Add populated with the links.
- Drop on Inbox: prepare Save to Inbox.
- Drop on a collection: preselect that collection.
- Drop existing library items on a collection: add membership directly and provide undo.
- Drop on the Dock icon: activate Vidindir and open Quick Add.
- Unsupported data produces a brief explanation; it is not silently discarded.
- Show standard macOS insertion/highlight feedback and announce the target to VoiceOver.

External file drops are out of V1 scope unless a dedicated local-file import feature is approved.

## 11. Search

`Command-F` focuses global search for the current workspace. Search covers title, creator, URL, collection, and, as those features ship, tags and comments.

- Results update incrementally and remain responsive with 10,000 or more media items.
- Search terms and active filters are visible and independently clearable.
- Search never performs a remote source search in V1; it searches the local library database.
- Keyboard navigation moves from the search field into results without requiring pointer input.

## 12. Settings

Use a native Settings scene with these sections:

```text
General
Downloads
Library
Sync
Engine
Integrations
Privacy
Advanced
```

Only shipped capabilities appear in release builds. Planned providers are not presented as enabled controls.

Important settings include:

- Default save destination and download behavior.
- Download folder, format, quality, and concurrency.
- Clipboard suggestions and notifications.
- Library view defaults and thumbnail cache management.
- Sync provider status and conflict/help information.
- App update and download-engine update channels.
- Privacy summary: no analytics, no tracking, no ads, no mandatory account, local-first, open source.
- Advanced engine versions, engine path, logs, health check, reset, and rollback.

Engine details belong in Settings, not in the main download flow.

## 13. Keyboard Commands

Commands must appear in the menu bar so users can discover them.

| Shortcut | Command | Context |
| --- | --- | --- |
| `Command-L` | Add Link | Global |
| `Command-N` | New Media Item / Add Link | Global in V1 |
| `Command-F` | Search | Current workspace |
| `Command-1` | Inbox | Main window |
| `Command-2` | Library | Main window |
| `Command-3` | Downloads | Main window |
| `Command-,` | Settings | Global |
| `Space` | Quick Look / Preview | Media selection |
| `Command-Return` | Download on This Mac | Media selection or Quick Add |
| `Command-Shift-C` | Copy Source URL | Media selection |
| `Command-Option-I` | Toggle Inspector | Main window |
| `Delete` | Contextual remove action | Requires clear scope and confirmation |
| `Escape` | Cancel/dismiss current transient UI | Sheets, search, menus |

Do not override platform-standard text editing shortcuts. If a shortcut conflicts with an active text field, text editing wins.

## 14. Feedback, Errors, and Undo

- Use inline validation for recoverable form issues.
- Use sheets or alerts for destructive, security-sensitive, or blocking decisions.
- Use brief in-app confirmations for actions such as adding to a collection; provide Undo where feasible.
- Use Notification Center for completed background work, not routine foreground events.
- User-facing errors state what happened, the likely reason when known, and the next available action.
- Technical details are selectable, redacted, and one disclosure away.
- Do not expose `yt-dlp`, FFmpeg, stack traces, shell commands, or exit codes in primary error copy.

## 15. Accessibility and Localization

Vidindir must be fully usable with keyboard navigation, VoiceOver, increased contrast, reduced motion, and text-size changes supported by macOS.

- Every icon-only control has an accessibility label and help text.
- Do not encode download, sync, or failure state by color alone; pair it with text or a symbol.
- Maintain a minimum 4.5:1 contrast ratio for essential text and controls where system colors do not already provide the guarantee.
- Use native focus rings and predictable focus order: sidebar, toolbar, content, inspector.
- Progress indicators expose the job title, stage, percentage when known, and cancellation availability.
- Thumbnails have useful labels derived from the media title; decorative artwork is hidden from accessibility.
- Respect Reduce Motion and Reduce Transparency.
- Support system text expansion without clipping essential labels. Avoid fixed-height text containers.
- All user-facing strings are localization-ready. Do not concatenate translated fragments.
- Dates, durations, file sizes, speeds, and remaining time use locale-aware formatters.

## 16. Key Textual Wireframes

### 16.1 Main library window

```text
+--------------------------------------------------------------------------------+
| [Sidebar]  Library                         [Search] [Grid/List] [Inspector] [+] |
+------------------+--------------------------------------+----------------------+
| Inbox          3 | [Thumbnail] [Thumbnail] [Thumbnail] | Thumbnail            |
| Library          | Title       Title       Title       | Video Title          |
| Favorites        | Creator     Creator     Creator     | Creator              |
|                  |                                      |                      |
| Downloads        | [Thumbnail] [Thumbnail] [Thumbnail] | Source      YouTube  |
|   Active       2 | Title       Title       Title       | Duration       18:34 |
|   Completed      | Creator     Creator     Creator     |                      |
|   Failed       1 |                                      | Collections          |
|                  |                                      | Programming          |
| Collections      |                                      |                      |
|   Programming    |                                      | Local Status         |
|   Music          |                                      | Not downloaded       |
|   Watch Later    |                                      |                      |
|                  |                                      | [Download on Mac]    |
| Workspaces       |                                      | Open Source          |
|   Personal       |                                      | Copy URL             |
+------------------+--------------------------------------+----------------------+
```

### 16.2 Download queue

```text
+--------------------------------------------------------------------------+
| Downloads                                             [2 at a time v]    |
| Active | Completed | Failed                                               |
+--------------------------------------------------------------------------+
| [Thumb] Video title                                              82%     |
|         Downloading · 12.4 MB/s · About 14 sec                           |
|         [=====================================--------] [Pause] [Cancel] |
|                                                                          |
| [Thumb] Another video                                                    |
|         Queued · Next                                                    |
+--------------------------------------------------------------------------+
```

### 16.3 Local versus synced status

```text
SwiftUI Tutorial

Library
Synced to iCloud                 Yes

This Mac
Local file                       Downloaded
Last verified                    Today, 14:32

Other devices never expose raw local file paths here.
```

## 17. Phased Availability

The navigation and data model may anticipate later phases, but production UI must not present nonfunctional controls.

| Phase | User-visible capabilities |
| --- | --- |
| **V1** | Native app shell; Quick Add; single, playlist, and batch URL intake; video/audio and simple quality selection; persistent queue; pause where supported, cancel, retry; Inbox, Library, Collections, Favorites, Search; local file tracking; duplicate detection; iCloud personal sync; clipboard suggestion; drag and drop; notifications; Show in Finder; app and engine updates. |
| **V1.5** | Tags; smart collections; subtitles and thumbnails; metadata controls; presets; Safari and Services integrations; menu bar capture; timestamp notes; advanced format selection. |
| **V2** | Shared workspaces; invitations; shared collections; comments and timestamp comments; reactions; mentions; activity feed; team inbox; Google Drive personal sync; shared-workspace providers. |
| **Later** | iPhone Share Extension; browser extension; send to device; self-hosted sync; plugin API; custom post-processing workflows; experimental native backend. |

When a future feature must be referenced for architectural testing, label it clearly in development builds. Do not use “Coming soon” rows to fill production navigation.

## 18. Acceptance Checklist

A feature UI is ready for review when:

- It works using native keyboard navigation and VoiceOver.
- It has loading, empty, offline, success, failure, and cancellation behavior where applicable.
- It does not equate a `MediaItem` with a `LocalAsset`.
- It does not call or parse `yt-dlp` or FFmpeg directly.
- It presents human-readable errors with optional redacted technical details.
- It remains coherent in light mode, dark mode, increased contrast, reduced motion, and reduced transparency.
- It uses shipped capability flags and does not expose dead future controls.
- It includes previews or fixtures for meaningful states and automated tests for non-visual interaction logic.
