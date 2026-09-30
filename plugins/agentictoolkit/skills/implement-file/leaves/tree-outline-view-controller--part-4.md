<!-- leaf: implement-file/tree-outline-view-controller--part-4 · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller — continued (part 4)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `roots` | `FileBrowserRootsModel` | required (no default) | Supplies the ordered list of `FileTreeManager`s shown as top-level rows. |
| `directories` | `FileBrowserDirectories` | required (no default) | The root URLs used to resolve which root a clicked node's target-selection belongs to. |
| `selection` | `FileBrowserSelection` | required (no default) | Shared selected-node/selected-root object; supply one to let a host read or drive the selection. |
| `restoration` | `FileBrowserRestorationState` | required (no default) | Shared expanded-paths/selected-path object; supply one to restore or persist disclosure and selection across launches. |
| `documentStore` | `TextDocumentStore` | required (no default) | App-wide open-document registry; supplies the dirty state shown by each file row's unsaved-changes marker. |
| `onOpenRequest` | `((URL, DocumentDestination) -> Void)?` | `nil` | Set by a host to receive open requests — from a click, double-click, or context-menu choice — naming the file and where it should be shown. |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none defined in source) | `Scanning…` | Placeholder row text while a root manager is syncing, a literal `String`. |
| (none defined in source) | `Empty` | Placeholder row text for a root with no contents, a literal `String`. |
| (none defined in source) | `Open` | Context menu item title, a literal `String`. |
| (none defined in source) | `Open in a New Tab` | Context menu item title, a literal `String`. |
| (none defined in source) | `Open to the Side` | Context menu item title, a literal `String`. |
| (none defined in source) | `Reveal in Finder` | Context menu item title, a literal `String`. |
| (none defined in source) | `Copy Path` | Context menu item title, a literal `String`. |
| (none defined in source) | `Folder` | Icon accessibility description for a directory, a literal `String`. |
| (none defined in source) | `File` | Icon accessibility description for a file, a literal `String`. |
| (none defined in source) | `Unsaved changes` | Unsaved-changes marker accessibility description, a literal `String`. |

All ten strings above are assigned directly as `String` literals to AppKit
properties (`NSTextField`/`ThemedLabel` string values, `NSMenuItem.title`,
`accessibilityDescription:`) rather than through any localization key or
`NSLocalizedString` call — this is an AppKit file, so none of these literals
gets SwiftUI's automatic `LocalizedStringKey` treatment. No string-key scheme
exists for this component in source. File and directory names themselves are
user data, not chrome text, and are correctly excluded from this table.

## Accessibility Options

- **Reduce Motion**: Not applicable. Source contains no animation of any
  kind — every reload, expansion, collapse, and recolor is an immediate
  property or layout change, with no `NSAnimationContext`, transition, or
  opacity fade to substitute.
- **Increase Contrast**: Not applicable at this component's level. All
  non-git colors are semantic theme roles (`.primaryText`, `.secondaryText`,
  `.tertiaryText`, `.accent`, `.info`, `.warning`); `FileTreeOutlineViewController.swift`
  contains no contrast-specific branching of its own, so any adaptation lives
  in the theme/palette system, not here. Git-status colors are the one
  exception: the source comment describes them as "git's own vocabulary, not
  app chrome," kept as fixed system colors (`NSColor.systemOrange`, etc.)
  rather than being remapped onto theme roles.
- **Differentiate Without Color**: Supported. Git status is always shown as a
  status letter (`M`, `A`, `D`, `R`, `C`, `?`, `U`, `!`) in addition to color,
  never by color alone; the dirty marker is a shape whose presence or absence
  carries the meaning, not a color change on an otherwise-identical shape.

## Privacy

- **Data collected**: File and directory paths the user browses, expands, and
  selects on their own local filesystem; the presence of open documents and
  their dirty state, read from the injected `TextDocumentStore`. Nothing is
  collected automatically beyond what the user's own filesystem and open
  documents already contain.
- **Storage**: This component does not itself write to disk or
  `UserDefaults`. Disclosure and selection changes flow out through
  `FileBrowserRestorationState.onChange`, a closure the host supplies and
  which decides whether and where to persist them (see
  `FileBrowserRestorationState.swift`); this controller only calls
  `setExpanded(_:path:)` and `setSelectedPath(_:)` on that shared object.
- **Transmission**: None. `FileTreeOutlineViewController.swift` makes no
  network calls.
- **Retention**: Determined entirely by the host through
  `FileBrowserRestorationState.onChange`; this component keeps disclosure and
  selection state only in memory, for as long as the controller and its
  injected model objects live.

