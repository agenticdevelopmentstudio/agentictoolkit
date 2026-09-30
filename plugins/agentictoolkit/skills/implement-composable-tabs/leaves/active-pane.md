<!-- leaf: implement-composable-tabs/active-pane · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane

## Overview

`ComposableTabsActivePane` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsActivePane.swift`)
is a `@MainActor` singleton that tracks, independently for each open `NSWindow`,
which composable-tabs pane the user is currently working in — the one they
last clicked in, or, with the `activePaneFollowsMouse` user setting on, the one
under the pointer. AppKit has no "the first responder changed" notification
and a pane's own content swallows mouse events before a pane could see them
itself, so the tracker installs one local `NSEvent` monitor for the whole app
(`leftMouseDown`, `rightMouseDown`, `mouseMoved`) instead of every pane
installing a monitor of its own, and answers "which pane is this point in"
with one hit test rather than a second implementation of it living in a
tracking area.

The same file also defines `ComposableTabsPaneBackgroundView`, an `NSView`
that is a pane's backdrop and draws the "this is the pane you are working in"
border. It is one view — not an overlay — so the border can never end up
under the pane's own content, and it registers its arrival and departure with
`ComposableTabsActivePane` as it moves in and out of a window, and repaints
whenever the tracker, the window's key state, or the highlight setting
changes.

Neither type renders or exposes anything else: no title, no icon, no
interactive control of its own. The chrome a pane wears beyond this backdrop
(title bar, gear menu, content identifier) belongs to
`ComposableTabsPaneViewController` and its own sources, not to this file, and
is out of scope for this ingredient.

