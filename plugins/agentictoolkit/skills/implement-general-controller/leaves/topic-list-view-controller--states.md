<!-- leaf: implement-general-controller/topic-list-view-controller--states · source: topic-list-view-controller.md -->

# TopicListViewController

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected, enabled item row) | `itemFont`, `primaryTextColor` label, `accentColor`-tinted icon; row background follows `windowBackgroundColor`. |
| Disabled item row | `itemFont`, `tertiaryTextColor` label, `tertiaryTextColor`-tinted icon; identical selection/press behavior to an enabled row (see **disabled-item-selectability**). |
| Selected row | `ThemedTableRowView.drawSelection(in:)` fills a 4pt-corner-radius rect, inset 2pt horizontally / 1pt vertically, with `palette.nsColor(.selection)`. |
| Group header row | `headerFont`, `secondaryTextColor`, `isGroupItem == true`; not selectable; no disclosure control. |
| Pressed | Not applicable: this file defines no visual state distinct from Selected for a row's press — a click or `AXPress` both resolve directly to `selectRowIndexes`, with no separate transient "pressed" appearance. |
| Focused | Not applicable beyond AppKit's own default keyboard-focus-ring behavior on the outline view; source sets no custom focus-ring color, width, or override. |
| Loading | Not applicable: `setItems`/`setSections` apply their row model synchronously; source defines no async load and no loading/pending indicator. |
