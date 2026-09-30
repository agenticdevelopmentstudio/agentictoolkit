<!-- leaf: implement-general-view-1/breadcrumb-view · source: breadcrumb-view.md -->

**Rules** (cite as `implement-general-view-1/breadcrumb-view#<slug>`):

- `render-one-crumb-per-title` MUST
- `chevron-between-crumbs` MUST
- `clear-strip-when-file-nil` MUST
- `rebuild-on-every-file-assignment` MAY
- `relative-titles-inside-root` MUST
- `single-crumb-outside-root` MUST
- `crumb-directory-cumulative` MUST
- `last-crumb-directory-is-containing-folder` MUST
- `crumb-truncates-middle` MUST
- `crumb-yields-width-before-container` MUST
- `crumb-borderless-inline-style` MUST
- `crumb-small-system-font` MUST
- `crumb-accessibility-identifier` MUST
- `chevron-decorative` MUST
- `chevron-fallback-image` MUST
- `click-opens-popover` MUST
- `popover-transient` MUST
- `single-popover-at-a-time` MUST
- `popover-selection-invokes-callback` MUST
- `popover-cancel-closes-without-callback` MUST
- `track-only-the-open-popover` MUST
- `select-crumb-by-index` MUST
- `ignore-out-of-range-crumb-index` MUST
- `no-filesystem-access` MUST
- `native-keyboard-activation` MUST

# Breadcrumb View

## Overview

`BreadcrumbView` is a VS Code-style breadcrumb strip shown above a document editor: a horizontal row of buttons, one per path segment between the project root and the open file, separated by chevrons, so a user can see where the current file sits and jump to any ancestor directory. Setting `fileURL` rebuilds the strip; clicking a crumb opens a popover listing that directory's siblings (handled by `BreadcrumbPopoverViewController`), and choosing an entry there — or calling `selectCrumb(at:)` directly — reports a URL back through `onSelect`: the file chosen in the popover, or the crumb's own directory when `selectCrumb(at:)` is called directly. The view itself is limited to path arithmetic and layout; it performs no filesystem access of its own.

## Behavioral Requirements

- **render-one-crumb-per-title**: The component MUST render exactly one button for each entry in the current crumb-title list, in the same left-to-right order as that list (root first, leaf last).
- **chevron-between-crumbs**: The component MUST insert a chevron separator between each pair of adjacent crumb buttons, and MUST NOT place a chevron before the first crumb.
- **clear-strip-when-file-nil**: The component MUST remove every crumb and chevron, leaving the strip empty, when `fileURL` is set to `nil`.
- **rebuild-on-every-file-assignment**: The component MAY recompute the crumb titles, recompute the crumb directories, and rebuild the displayed crumbs every time `fileURL` is assigned, including when the newly assigned value is unchanged from the previous one — the current implementation does this unconditionally, since `fileURL`'s `didSet` observer runs on every assignment with no equality check against the previous value (see the corresponding Design Decision).
- **relative-titles-inside-root**: The component MUST derive the crumb titles from `fileURL`'s path components with `rootURL`'s path components removed from the front, when `fileURL`'s standardized path begins with `rootURL`'s standardized path.
- **single-crumb-outside-root**: The component MUST derive a single crumb whose title is `fileURL`'s last path component when `fileURL`'s standardized path does not have strictly more path components than `rootURL`'s standardized path, or when `rootURL`'s path components are not a prefix of `fileURL`'s path components — checked component-wise, not as a raw string prefix, so a path like `/Users/x/project2/...` is correctly treated as outside `/Users/x/project` even though it shares a string prefix with it. This includes the case where `fileURL` equals `rootURL`.
- **crumb-directory-cumulative**: For every crumb before the last, the component MUST associate it with the absolute directory formed by the file's path components from the root up to and including that crumb's own segment.
- **last-crumb-directory-is-containing-folder**: The component MUST associate the last crumb (the file's own crumb) with the directory that contains the file, not with the file's own path.
- **crumb-truncates-middle**: The component MUST truncate a crumb button's displayed title in the middle, not at the end, when the title does not fit the available width.
- **crumb-yields-width-before-container**: The component MUST give every crumb button a horizontal content compression resistance priority of `.defaultLow` (250), so a crumb's text shrinks before the containing view is forced to grow.
- **crumb-borderless-inline-style**: The component MUST render every crumb as a borderless button using the inline bezel style.
- **crumb-small-system-font**: The component MUST render crumb title text in the system font at the small system font size.
- **crumb-accessibility-identifier**: The component MUST assign each crumb button the accessibility identifier `breadcrumb.crumb.<index>`, where `<index>` is the crumb's zero-based position in the strip.
- **chevron-decorative**: The component MUST render each chevron separator with no accessibility description, so it is not announced as a distinct element.
- **chevron-fallback-image**: The component MUST substitute an empty image for a chevron when the `chevron.right` symbol cannot be resolved, rather than leaving the image view without an image.
- **click-opens-popover**: The component MUST open a popover, anchored to the clicked crumb button, listing the contents of that crumb's directory, when a crumb button is clicked.
- **popover-transient**: The component MUST configure every popover it presents with `.transient` behavior, so the popover dismisses itself when the user clicks outside it.
- **single-popover-at-a-time**: The component MUST close any popover that is already open before presenting a new one.
- **popover-selection-invokes-callback**: The component MUST close the popover and invoke `onSelect` with the chosen file when the popover reports a chosen file.
- **popover-cancel-closes-without-callback**: The component MUST close the popover without invoking `onSelect` when the popover is cancelled.
- **track-only-the-open-popover**: The component MUST clear its reference to the active popover only when the popover reporting its own closure is the one currently tracked as active.
- **select-crumb-by-index**: The component MUST invoke `onSelect` with the directory of the crumb at a given index when `selectCrumb(at:)` is called with an index inside the current crumb range.
- **ignore-out-of-range-crumb-index**: The component MUST NOT invoke `onSelect`, or take any other action, when `selectCrumb(at:)` or a crumb click reports an index outside the current crumb range.
- **no-filesystem-access**: The component MUST NOT read the file system to compute crumb titles or directories; all path arithmetic MUST operate only on the `URL` values already given to it.
- **native-keyboard-activation**: The component MUST support standard AppKit keyboard focus and activation on every crumb, because crumbs are instances of `NSButton` rather than custom-drawn views: when Full Keyboard Access is enabled, Tab moves focus to each crumb button in order, and Space or Return activates the focused button. (macOS only moves Tab focus to a push button when Full Keyboard Access is on; that is AppKit's own system-wide behavior, not something this component controls.)

## Appearance

- **Corner radius**: None. No corner radius is set on the view or on any crumb button.
- **Padding**: Crumb stack inset 8pt from the leading edge, at most 8pt from the trailing edge (an upper bound, not a fixed value), 2pt from the top edge, and 2pt from the bottom edge. 2pt of stack spacing separates each crumb from its neighboring chevron.
- **Font**: Crumb titles — system font at `NSFont.smallSystemFontSize`. Chevron symbol — 9pt point size, regular weight.
- **Background**: None. No background color is set on the view or on any crumb button.
- **Foreground/Text**: Crumb button title — the default `NSButton` title color (system label color). Chevron — `NSColor.secondaryLabelColor`.
- **Border**: None. Crumb buttons are borderless (`isBordered = false`) with the `.inline` bezel style.
- **Shadow**: None specified in source.
- **Min/Max size**: None specified. No crumb button has a minimum or maximum width or height constraint; a crumb may shrink to its truncated content because of its low horizontal compression resistance priority (see **crumb-yields-width-before-container**), and the stack's trailing constraint is an upper bound (`lessThanOrEqualTo`), not a fixed width.

## Accessibility

- **Identifier**: Each crumb button carries the accessibility identifier `breadcrumb.crumb.<index>` (via `accessibilityID`), set from the crumb's zero-based position in the strip — an identifier for automation, not the label VoiceOver announces.
- **Label**: `NSButton`'s accessibility label derives from its `title`, which is the full crumb title text. `lineBreakMode = .byTruncatingMiddle` changes only the rendered glyphs, not `title`, so VoiceOver announces the complete crumb title even when the visible text is truncated.
- **Role**: Crumb buttons keep the default `NSButton` "button" accessibility role; no custom role or trait is set. The chevron separators are `NSImageView`s created with `accessibilityDescription: nil` — a deliberate decorative marking, so VoiceOver does not present them as a separate stop.
- **Assistive technology**: `rebuild()` replaces every crumb view whenever `fileURL` changes without posting an accessibility notification (such as a layout-changed or announcement notification) around that replacement. A VoiceOver user tracking the strip is told the path changed only if AppKit's own automatic detection of the view-tree change surfaces it; the source itself makes no explicit announcement.
- **Minimum tap target**: Not applicable: `BreadcrumbView` targets macOS pointer and trackpad input, not touch. The source sets no minimum width or height on a crumb button — each button sizes to its (possibly truncated) title — and macOS's HIG does not mandate a minimum click-target dimension for inline chrome controls the way iOS mandates a touch-target minimum.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | `URL` | required, set at init | The project root that crumb titles and directories are computed relative to. It is fixed at initialization and cannot be changed afterward. |
| `fileURL` | `URL?` | `nil` | The file the strip currently describes. Setting it recomputes and rebuilds the crumbs (**rebuild-on-every-file-assignment**); `nil` clears the strip (**clear-strip-when-file-nil**). |
| `onSelect` | `((URL) -> Void)?` | `nil` | Callback invoked with a URL — the file a popover's user chose, or the crumb's own directory when `selectCrumb(at:)` is called directly. |
| `crumbTitles` | `[String]` (read-only) | `[]` | The crumb labels, root to leaf; empty when there is no file. |
| `selectCrumb(at:)` | Method | n/a | Reports the directory of the crumb at `index` through `onSelect`, exactly as if that crumb's popover had opened and its listener acted on the directory itself; an out-of-range index is ignored. |

