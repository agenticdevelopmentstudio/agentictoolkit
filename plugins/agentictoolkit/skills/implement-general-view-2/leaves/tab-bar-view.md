<!-- leaf: implement-general-view-2/tab-bar-view · source: tab-bar-view.md -->

# TabBarView

## Overview

`TabBarView` is a `@MainActor` `NSView`
(`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabBarView.swift`)
that renders the edge-aligned tab strip for `MultiTabbedViewController`: one
pill-style button per tab, laid out inside an `NSStackView` whose orientation
follows the bar's `Edge` (top/bottom lay tabs out in a row, left/right in a
column). It owns no selection or ordering policy of its own — `items` and
`selectedID` are handed to it by `setItems(_:selectedID:)`, and it reports user
intent back to its owner purely through three closures (`onSelect`, `onClose`,
`onReorder`) so it stays decoupled from `MultiTabbedViewController`'s public
API. Two private helper types live in the same file and are described here
because neither has a recipe of its own within this file's scope:
`TabItemHostView`, which wraps a hosted `.viewController` item's view so a
click anywhere on it selects the tab, and `TabButton`, the pill control that
renders a `.title` item with its own close icon.

