<!-- leaf: implement-general-view-1/disclosure-card-view · source: disclosure-card-view.md -->

# DisclosureCardView

## Overview

`DisclosureCardView`, at
`packages/apple/AgenticToolkit/macOS/UI/Cards/DisclosureCardView.swift`, is an
`@MainActor`, `NSView`-subclassed, `Themeable` card that folds: a rounded,
bordered surface with an elevated titlebar strip naming it (a title, an
optional leading accessory, an optional status symbol right after the title,
an optional trailing accessory, and a native disclosure triangle), and
whatever host content is added beneath that. Folding
the card hides its content and, if the card carries `summary` readings, shows
a single right-aligned line of them under the title instead; a folded card
with no summary is exactly its titlebar and nothing else. The card can also
show one status badge stamped on its top-right corner. Its own width never
changes between open and folded states, because both states' content is
measured and the wider is reserved regardless of which is currently drawn.
Tapping the disclosure triangle does not fold the card itself — it reports the
requested new state through `onToggle` and leaves layout untouched; the host
is expected to rebuild the card with a new `isCollapsed` value (typically via
the companion `CardFoldMemory` helper in the same directory, which persists
the folded set and rebuilds on toggle).

