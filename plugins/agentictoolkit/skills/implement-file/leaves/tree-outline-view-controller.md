<!-- leaf: implement-file/tree-outline-view-controller · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller

## Overview

`FileTreeOutlineViewController` is an `NSViewController` that draws the file
tree itself: one collapsible header row per root directory (a `FileTreeManager`),
and the files and folders under each one, in an `NSOutlineView` rather than a
SwiftUI `List`. It is hosted inside `FileBrowserViewController` (see the
`file-browser-view-controller` recipe), which owns the footer strip and the
per-root `FileTreeManager`s; this component owns only the tree surface: lazy
per-directory loading, expand/collapse and selection state kept in sync with
injected model objects (`FileBrowserSelection`, `FileBrowserRestorationState`,
`FileBrowserDirectories`), a "reveal the file the editor is showing" API, a
live unsaved-changes indicator sourced from `TextDocumentStore`, and a
right-click context menu for opening, revealing, and copying a path.

