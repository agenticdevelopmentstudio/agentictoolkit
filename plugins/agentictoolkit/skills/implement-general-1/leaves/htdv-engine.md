<!-- leaf: implement-general-1/htdv-engine · source: htdv-engine.md -->

# HTDV Engine

## Overview

The HTDV engine is the non-UI logic that `AgenticToolkitHTDVViewController` and
`FormViewController` render: it owns no view and draws nothing. It is four
cooperating pieces, all under `packages/apple/AgenticToolkit/HTDV/`:

- **`HTDVController`** (`Controller/HTDVController.swift`) — the `@MainActor`
  navigation/selection/loading state machine that walks an `HTDVDataSource`
  tree one level at a time and exposes `levels`, `selection`, `detail`,
  `loadingLevelIndex`, and `error` to a host view.
- **The data model** (`Model/HTDVModel.swift`, `Model/HTDVCellContent.swift`)
  — `HTDVItem`, `HTDVLevel`, `HTDVDetail`, `HTDVChild`, `HTDVBadge`,
  `HTDVCreateAction`, the `HTDVDataSource` protocol the host implements, and
  `HTDVCellContent`, the platform-neutral row projection both the AppKit and
  UIKit rail cells render from.
- **`HTDVLayoutEngine`** (`Layout/HTDVLayoutEngine.swift`) — a pure function
  from available width, level count, and compactness to a rails-vs-stack
  layout `Mode`, called by both platform view controllers on resize.
- **The Forms subsystem** (`Forms/FormSpec.swift`, `Forms/FormValue.swift`,
  `Forms/FormState.swift`, `Forms/FormValidator.swift`) — the declarative
  shape of a detail form (`FormSpec`), its field value type (`FormValue`),
  its mutable, dirty-tracked, save-lifecycle model (`FormState`), and its
  per-field validation rules (`FormValidator`).

`MarkdownEditing.swift` (`Markdown/MarkdownEditing.swift`) is included because
it is the injectable factory contract the Forms subsystem's `markdown` field
kind depends on (per `docs/htdv.md`'s Concepts table: "`markdown` (rendered
via `MarkdownEditing`)"); its default, `PlainTextMarkdownEditing`, is itself
logic (`String` in, `String` out via a callback) even though the concrete
`PlainTextEditorViewController`/`PlainTextViewerViewController` it vends are
platform view controllers — see Design Decisions.

`AgenticToolkitHTDVViewController` (macOS/iOS) and `FormViewController`
(macOS/iOS) are the presentation layer that consumes this engine; they are
out of this recipe's given sources and are not described here except where a
doc comment in a given source states what the presentation layer is
responsible for.

