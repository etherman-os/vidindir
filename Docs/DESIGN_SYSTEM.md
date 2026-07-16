# Vidindir Design System

Status: Foundation specification
Platform: macOS 15 and later
Design direction: **Native. Minimal. Fast. Calm. Mac-first.**

## 1. Purpose

This document defines the shared visual and interaction language for Vidindir. It applies to the main app, Settings, onboarding, system integrations, and release screenshots. It intentionally favors macOS conventions over a highly branded custom component library.

The design system should make a large media library feel quiet and navigable while keeping downloads trustworthy and legible. Brand expression belongs in the app icon, accent color, copy, and a few carefully chosen moments—not in custom replacements for standard Mac controls.

## 2. Principles

### 2.1 Native before novel

Start with SwiftUI and AppKit system components: `NavigationSplitView`, `Table`, `List`, `Grid`, `ToolbarItem`, `Inspector`, `Menu`, `Form`, `Settings`, `ProgressView`, `ContentUnavailableView`, standard sheets, alerts, and context menus. Customize only when a documented product need cannot be met accessibly with a native control.

### 2.2 Calm hierarchy

One surface should have one obvious primary action. Secondary metadata recedes through semantic foreground styles, spacing, and placement rather than tiny type or low contrast. Downloads may be active without making the entire app visually urgent.

### 2.3 Content leads

Thumbnails, titles, collections, and status are more important than decorative containers. Prefer grouped lists and whitespace over a wall of cards. Avoid wrapping every section in a rounded rectangle.

### 2.4 Honest state

Downloaded, synced, queued, failed, and unavailable are distinct states. Color supports these meanings but never carries them alone. Indeterminate work is not displayed as fake determinate progress.

### 2.5 Adaptive by default

Every component supports light and dark appearance, increased contrast, reduced transparency, reduced motion, text scaling, keyboard focus, and VoiceOver without a separate “accessible” variant.

## 3. Visual Foundation

### 3.1 Materials and surfaces

Use macOS semantic surfaces:

| Surface | Preferred treatment |
| --- | --- |
| Window content | `windowBackgroundColor` / SwiftUI semantic background |
| Sidebar | Native sidebar material and vibrancy |
| Inspector | Native inspector background or grouped form surface |
| Toolbar | System toolbar material |
| Sheets and popovers | System presentation background |
| Selection | System selection and accent treatment |
| Floating status overlay | Regular or thin material only when separation is necessary |

Rules:

- Do not place a full-window gradient behind routine product UI.
- Do not stack translucent materials; nested blur reduces clarity and performance.
- Respect Reduce Transparency by allowing the system to replace materials with opaque surfaces.
- Use separators to express structure before adding shadows.
- Shadows are reserved for floating or dragged content and should be subtle, never a permanent “web card” effect.

### 3.2 Color

Use semantic system colors for almost all UI. Brand colors supplement rather than replace system semantics.

#### Core tokens

| Token | Purpose | Implementation guidance |
| --- | --- | --- |
| `color.accent` | Primary actions, selected controls, brand details | Dynamic Vidindir teal; user accent compatibility must be evaluated |
| `color.primary` | Primary text and symbols | `.primary` |
| `color.secondary` | Supporting metadata | `.secondary` |
| `color.tertiary` | Optional/de-emphasized metadata | `.tertiary`; never for essential information |
| `color.separator` | Dividers and boundaries | Native separator color |
| `color.selection` | Selected rows and items | Native selection treatment |
| `color.success` | Completed/verified state | System-compatible green plus symbol/text |
| `color.warning` | Needs attention/interrupted | System-compatible orange plus symbol/text |
| `color.error` | Failed/destructive state | `.red`/system red plus symbol/text |
| `color.info` | Neutral informational state | Accent or system blue plus symbol/text |

The Vidindir accent should remain a restrained, medium teal inspired by the current identity. Define light, dark, high-contrast, and tinted-control variants in an asset catalog rather than scattering RGB values through feature code.

Color rules:

- Never use brand teal for errors, destructive actions, or all selected rows.
- Destructive controls use the platform destructive role.
- Do not use tinted text on tinted backgrounds unless contrast has been tested in every appearance.
- Status badges always include a label or recognizable symbol.
- Thumbnail artwork must not determine the legibility of overlay text; use a semantic material or scrim directly behind the label.

### 3.3 Typography

Use the San Francisco system family through semantic SwiftUI styles. Do not bundle a custom UI font.

| Role | Preferred style | Usage |
| --- | --- | --- |
| Window/destination title | `.title2` or toolbar title behavior | Major destination, sparingly |
| Section title | `.headline` | Inspector and content sections |
| Item title | `.body` with medium/semibold weight when selected by hierarchy | Media titles |
| Body | `.body` | Explanations, form content |
| Metadata | `.callout` or `.subheadline` | Creator, source, dates |
| Auxiliary | `.caption` | Duration, file size, compact status |
| Technical | `.callout.monospaced()` | Redacted logs, identifiers, engine versions |
| Numeric status | Semantic style with `.monospacedDigit()` | Progress, speed, counts, duration |

Rules:

- Weight establishes hierarchy; avoid oversized titles.
- Do not set tracking on body copy. Uppercase tracked section labels are discouraged for routine forms.
- Essential metadata should not be smaller than `.caption`.
- Limit titles by layout context, not with a global fixed line count. Inspector titles may wrap; dense rows usually remain one line.
- Format dates, duration, file sizes, and speed with locale-aware formatters.

### 3.4 Spacing

Use a 4-point base grid while allowing native controls to retain their intrinsic metrics.

| Token | Value | Typical use |
| --- | ---: | --- |
| `space.1` | 4 pt | Icon-label refinement, tight metadata |
| `space.2` | 8 pt | Related controls and row internals |
| `space.3` | 12 pt | Compact groups |
| `space.4` | 16 pt | Standard content grouping |
| `space.5` | 20 pt | Section padding |
| `space.6` | 24 pt | Major section separation |
| `space.8` | 32 pt | Empty-state and large-flow separation |

Use the smallest token that clearly communicates grouping. Prefer fewer nested stacks over compensating with arbitrary padding.

### 3.5 Shape and borders

- Standard controls keep native shapes.
- Media thumbnails use a continuous 8-point corner radius in grids and 4–6 points in compact rows.
- Custom containers use 8–12 points. Larger 16–20 point “dashboard card” radii require a documented reason.
- Pills are reserved for short status or tag tokens, not general buttons.
- Use a one-pixel semantic separator/border only when material or spacing does not provide enough separation.

### 3.6 Layout metrics

Recommended starting metrics:

| Element | Metric |
| --- | --- |
| Main window default | 1180 x 760 pt |
| Main window minimum | 820 x 560 pt |
| Sidebar | 220–280 pt |
| Inspector | 280–360 pt |
| Main content comfortable minimum | 440 pt |
| Grid thumbnail ratio | 16:9 |
| Grid minimum item width | 190–220 pt, tuned through testing |
| List thumbnail | Approximately 72 x 41 pt |
| Compact thumbnail | Approximately 44 x 25 pt |
| Primary content margin | 16–24 pt, contextual |

These are starting points, not reasons to fight standard split-view or table sizing behavior.

## 4. Iconography and Artwork

Use SF Symbols for interface icons.

| Meaning | Preferred symbol family |
| --- | --- |
| Inbox | `tray` |
| Library | `rectangle.stack` or `books.vertical` after visual testing |
| Favorites | `star` / `star.fill` |
| Downloads | `arrow.down.circle` |
| Collection | `folder` |
| Workspace | `person.2` |
| Add Link | `plus` or `link.badge.plus` |
| Local file verified | `checkmark.circle.fill` |
| Cloud/synced | `icloud` / `checkmark.icloud` |
| Failed | `exclamationmark.triangle` |
| Inspector | Platform-standard inspector symbol |
| Reveal in Finder | `folder` with explicit text in menus |

Rules:

- Use one symbol style and weight within a control group.
- Filled variants communicate selection or a confirmed state; they are not decorative.
- Icon-only buttons require accessibility labels, tooltips/help, and a minimum comfortable hit target.
- Do not invent custom line icons when an appropriate SF Symbol exists.
- The app mark may be custom. It should reproduce clearly at 16, 32, 128, and 1024 pixels and must not require detailed gradients to remain recognizable.
- Source logos are optional metadata, not primary navigation icons. Respect trademark and asset licensing requirements.

## 5. Components

### 5.1 Buttons

- One default button per sheet or focused task.
- Use bordered/prominent treatment only for the primary action.
- Use plain or bordered secondary controls for alternatives.
- Destructive actions use the destructive role and confirmation appropriate to impact.
- Button labels are verbs: Add, Download, Retry, Reveal in Finder.
- Disabled buttons retain an accessibility explanation when the reason is not obvious.

### 5.2 URL field

The Add Link field is a standard text field with URL-appropriate behavior:

- Clear placeholder: “Paste a video link…”
- Paste affordance only when useful.
- Inline validation below the field.
- Progress at the trailing edge during resolution without changing field width.
- Full keyboard editing and undo.
- No automatic replacement or normalization of visible user text while editing.

### 5.3 Media thumbnail

All thumbnail variants share:

- A stable aspect ratio to prevent layout jumps.
- Placeholder with a neutral source/media symbol.
- Asynchronous loading with cancellation and caching.
- Duration label at bottom trailing when known.
- No automatic animation or video playback on hover.
- An accessibility label based on the media title, not “image.”

### 5.4 Media row and grid item

The component owns display only. Actions are supplied by the feature layer.

Required visual states:

- Resting, hovered, selected, focused, unavailable, and loading.
- Favorite on/off.
- Local asset verified, not downloaded, missing, and downloading.
- Sync neutral, pending, and failed when sync is shipped.

Avoid more than two persistent corner badges on a thumbnail. Put additional status in metadata or the inspector.

### 5.5 Status label

A status label pairs symbol, text, and optional semantic color:

```text
[checkmark.circle.fill] Downloaded
[arrow.down.circle] Downloading 82%
[exclamationmark.triangle] Failed
[icloud] Synced
```

Use concise labels. Never show green “Ready” chrome on every screen when readiness is the expected state.

### 5.6 Progress

- Use `ProgressView` unless a documented need requires a custom style.
- Determinate progress uses monospaced percentage where space allows.
- Indeterminate progress includes a stage label such as Resolving or Post-processing.
- Progress animation respects Reduce Motion.
- Speed and time remaining are secondary and may update less often to reduce visual jitter.

### 5.7 Sidebar row

Sidebar rows use native label, selection, disclosure, drag target, and badge behavior. Counts align trailing. User-created collection names take available width before a count is truncated. Do not put persistent action buttons in every row; reveal collection actions through context menus or an active-row affordance.

### 5.8 Inspector section

Inspector sections use a heading, aligned key/value rows, and standard controls. Use separators or section spacing rather than independent cards. Destructive actions live at the end of the inspector or in an action menu, away from primary download controls.

### 5.9 Tags and collection tokens

Tokens are compact and wrap naturally. They use neutral fills by default; user-assigned tag colors may arrive in a later phase. Every token has a text label, an accessible remove action in editing mode, and a focus indicator.

### 5.10 Empty state

Use `ContentUnavailableView` where it fits. An empty state contains:

- One simple symbol or small illustration.
- A specific title.
- One sentence of explanation.
- At most one primary and one secondary action.

Do not use celebratory artwork for routine empty filters or completed queues.

### 5.11 Banner, toast, and notification

- **Inline banner:** persistent contextual state such as offline mode or sync action required.
- **Transient confirmation:** reversible, noncritical feedback such as “Added to Programming,” with Undo where appropriate.
- **Alert/sheet:** destructive or blocking decision.
- **System notification:** background completion or failure that matters outside the app.

Do not build a stack of custom toast notifications that duplicates Notification Center or obscures content.

### 5.12 Technical details view

Technical details use selectable monospaced text in a scroll view. Secrets, cookies, authorization headers, local usernames where unnecessary, and signed URL query values are redacted. Provide Copy Diagnostics and optionally Save Diagnostics after redaction.

## 6. Interaction States

Every data-backed component defines these states as applicable:

| State | Treatment |
| --- | --- |
| Loading | Preserve layout; use progress only when work is perceptible |
| Empty | Specific empty state and relevant action |
| Populated | Content-first presentation |
| Stale/offline | Keep cached content visible; identify unavailable actions |
| Failed | Human-readable message, recovery action, technical disclosure |
| Partial | Render available metadata; label missing capability honestly |
| Disabled | Explain why through adjacent copy or help |
| Destructive pending | State exact scope and offer Cancel |

Skeleton loading may be used for thumbnail-heavy content only if it reduces layout shifts. It must respect Reduce Motion and must not shimmer indefinitely.

## 7. Motion

Motion communicates cause and continuity, not personality for its own sake.

- Use system transitions and spring behavior where available.
- Typical custom state transition: 150–250 milliseconds.
- Selection should feel immediate; do not animate table selection.
- Animate insertion, removal, inspector reveal, and progress changes only when it clarifies the result.
- Avoid parallax, looping gradients, bouncing download icons, auto-playing previews, and large celebratory effects.
- With Reduce Motion, replace spatial transitions with short opacity changes or no animation.

## 8. Dark Mode and Appearance

- Use semantic colors and dynamic assets; never assume a white canvas or black text.
- Test sidebar vibrancy, inspector separators, thumbnail placeholders, overlays, focus rings, selection, and destructive controls in both appearances.
- Dark mode is not an inverted light palette. Brand teal may need lower saturation or adjusted luminance.
- Avoid pure black large surfaces unless supplied by the system.
- Thumbnail overlays use local material/scrims that work over both bright and dark artwork.
- Increased Contrast must strengthen boundaries and state differentiation without requiring a separate theme toggle.

## 9. Accessibility

Accessibility is part of each component’s definition of done.

- Maintain at least 4.5:1 contrast for essential normal text and 3:1 for large text and meaningful graphical controls when not guaranteed by system controls.
- Keep pointer targets comfortably at least 28 x 28 points; favor 32 x 32 or standard macOS control sizes for frequent icon actions.
- Preserve visible keyboard focus and native focus rings.
- Pair color with text, shape, or symbol.
- VoiceOver order follows visual reading order and avoids redundant thumbnail/status announcements.
- Group a media row meaningfully but expose its primary actions.
- Do not put important information only in hover UI or tooltips.
- Support Increase Contrast, Differentiate Without Color, Reduce Transparency, Reduce Motion, and system text-size changes.
- Progress announcements are throttled so VoiceOver is informative rather than noisy.
- Drag and drop always has an equivalent menu or keyboard action.

## 10. Content Style

Vidindir’s voice is direct, calm, and nontechnical.

- Use sentence case: “Download on This Mac,” not “DOWNLOAD ON THIS MAC.”
- Prefer familiar words: “link,” “video,” “download folder,” and “Show in Finder.”
- Avoid blaming the user or source.
- Explain consequences before destructive actions.
- Keep engine names out of primary flows unless the user opens Engine or Advanced settings.
- Error copy follows: outcome, likely cause, next action.
- Privacy statements are factual, not absolute beyond implementation: “No analytics” is valid only while the product actually sends none.

Examples:

| Avoid | Prefer |
| --- | --- |
| `ERROR: extractor returned 403` | “The video could not be accessed.” |
| `Execute download` | “Download” |
| `Delete` when scope is ambiguous | “Remove Local File” or “Delete from Library” |
| `Cloud item` | “Saved in your library” |
| `Success!` | “Download complete” |

## 11. Patterns to Avoid

Vidindir must not drift toward:

- A web analytics dashboard layout.
- Oversized statistic cards, hero panels, or marketing copy inside the working app.
- Excessive gradients, glass layers, glow, and permanent drop shadows.
- Custom sidebars, switches, tables, or menus that imitate native controls poorly.
- Huge rounded cards around every row or form section.
- Dense surfaces full of codec names and backend flags.
- Animation for routine hover, selection, and status updates.
- Color-only status, tiny low-contrast labels, or icon-only destructive actions.
- Persistent terminal output in the main UI.
- Source-specific branding that makes the app look YouTube-only.

## 12. Implementation and Review

- Shared tokens and reusable components belong in `Modules/DesignSystem` as the modular architecture is introduced.
- Feature modules may compose shared components but should not add global colors, spacing constants, or button styles locally.
- Use SwiftUI previews with representative light, dark, long-title, missing-thumbnail, loading, failed, selected, and accessibility-size states.
- A custom component requires a documented gap in native behavior, keyboard and VoiceOver verification, and visual review in all supported appearances.
- Design changes that alter product semantics—especially deletion, download state, sync state, or workspace scope—must update `Docs/UI_SPEC.md` and may require an ADR.

### Review checklist

- Does the screen have one clear primary action?
- Is content more prominent than its containers?
- Are local-file and library states visually and verbally distinct?
- Are all controls keyboard and VoiceOver accessible?
- Does the design survive dark mode, long localized strings, and missing artwork?
- Are loading, empty, offline, partial, failed, and destructive states covered?
- Is a standard macOS pattern available instead of the custom treatment?
- Have unnecessary gradients, cards, badges, and animations been removed?
