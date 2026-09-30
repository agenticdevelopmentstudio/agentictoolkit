<!-- leaf: implement-general-controller/document-editor-view-controller--test-vectors · source: document-editor-view-controller.md -->

# DocumentEditorViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| devc-001 | file-url-key-constant | Read `DocumentEditorViewController.fileURLKey` | Equals `"fileURL"` |
| devc-002 | own-file-selection | Construct two controllers with the same `store`; set `fileURL` on the first only | The second controller's `fileURL` is unaffected |
| devc-003 | coder-init-unsupported | Call `init(coder:)` | Calls `fatalError` (process traps rather than returning) — verified by code inspection; a trapping call cannot be asserted in XCTest |
| devc-004 | restore-on-construction | `store` has `fileURLKey` set to a path that exists on disk; construct a controller | `fileURL` equals that path immediately after construction |
| devc-005 | missing-file-restore | `store` has `fileURLKey` set to a path with no file on disk; construct a controller | `fileURL` is `nil`; `store.paneStateValue(forKey: fileURLKey)` is now `nil`; `paneTitle` is `"Untitled"` |
| devc-006 | restore-omits-redundant-write | `store` has `fileURLKey` set to an existing file's path; construct a controller, spying on `setPaneStateValue` | No call to `setPaneStateValue(_:forKey: fileURLKey)` occurs during construction |
| devc-007 | file-url-reflects-selection | No selection set | `fileURL` is `nil` |
| devc-008 | set-file-url-updates-selection | Set `fileURL = URL(fileURLWithPath: "/tmp/a/Readme.md")` | The selection's node URL equals that path |
| devc-009 | set-file-url-persists | Set `fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")` | `store.paneStateValue(forKey: fileURLKey)` equals `"/tmp/example/Readme.md"` |
| devc-010 | set-file-url-updates-breadcrumb | Set `fileURL` to a non-nil URL | The breadcrumb's `fileURL` equals the same URL |
| devc-011 | file-url-title-change | Install a closure on `onTitleChange`; set `fileURL` | The closure is called |
| devc-012 | directory-detected-via-resource-value | Set `fileURL` to a URL for an existing directory | The selection's node has `isDirectory == true` |
| devc-013 | clear-document-preserves-pane | Set `fileURL`, then call `clearDocument()` | `fileURL` is `nil`; `store.paneStateValue(forKey: fileURLKey)` is `nil`; the pane/controller itself still exists |
| devc-014 | pane-title-is-filename | Set `fileURL = URL(fileURLWithPath: "/tmp/example/Readme.md")` | `paneTitle` equals `"Readme.md"` |
| devc-015 | pane-title-untitled-when-empty | Construct a controller with an empty store | `paneTitle` equals `"Untitled"` |
| devc-016 | title-change-callback-bridge | Assign a closure to `onPaneTitleChange` | Reading `onTitleChange` returns the same closure |
| devc-017 | options-rows-order | Call `makePaneOptionRows()` | Returns 4 views: 3 `WindowOptionsToggle`s ("Show line numbers", "Show overview", "Show invisibles") then one `NSButton` titled "Reset to Defaults", in that order |
| devc-018 | toggle-initial-state-resolved | `options.showOverview` is `false` at call time; call `makePaneOptionRows()` | The "Show overview" row's `isOn` is `false` |
| devc-019 | toggle-change-writes-override | Toggle the "Show line numbers" checkbox | `options.setShowLineNumbers(_:)` is called with the checkbox's new value |
| devc-020 | reset-button-label-and-style | Call `makePaneOptionRows()` | The fourth row's `title` is `"Reset to Defaults"` and `bezelStyle` is `.rounded` |
| devc-021 | reset-button-enabled-matches-override | `options.isOverridden` is `false`; call `makePaneOptionRows()` | The reset button's `isEnabled` is `false` |
| devc-022 | reset-button-action | Click the reset button | `options.reset()` is called |
| devc-023 | reset-accessibility-identity | Inspect the reset button | Accessibility identifier is `document.options.reset`; accessibility label is `"Reset Editor Options to Defaults"` |
| devc-024 | toggle-accessibility-identifiers | Inspect the three toggle rows' checkboxes | Identifiers are `document.options.line-numbers`, `document.options.overview`, `document.options.invisibles` respectively |
| devc-025 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, keeping references; then call `options.setShowOverview(true)` | The kept "Show overview" row's `isOn` becomes `true`; the kept reset button's `isEnabled` becomes `true` |
| devc-036 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, keeping references, with no pane-local override present; then change the app-wide `UserSettings.editorShowLineNumbers` value | The kept "Show line numbers" row's `isOn` updates to the new app-wide value |
| devc-037 | rows-refresh-on-options-change | Build rows via `makePaneOptionRows()`, then let the popover close so the kept row references become `nil`; then call `options.setShowOverview(true)` | No crash occurs; `refreshOptionRows()`'s optional-chained writes to the released rows are no-ops |
| devc-026 | pane-override-isolated | Two controllers, each with its own `EditorOptionsOverride`; toggle "Show line numbers" on the first via its row | The first's `options.showLineNumbers` flips and `isOverridden` becomes `true`; the second's `options.showLineNumbers` and `isOverridden` are unchanged |
| devc-027 | reset-does-not-affect-other-panes-or-global | Override "Show line numbers" on both of two controllers, then click the first's reset button | The first's `isOverridden` becomes `false`; the second's `isOverridden` stays `true`; the app-wide `UserSettings.editorShowLineNumbers` value is unchanged |
| devc-028 | breadcrumb-above-content | Load the controller's view | The root stack's arranged subviews are `[breadcrumb, hostingView]`, `orientation == .vertical`, `spacing == 0` |
| devc-029 | breadcrumb-fixed-height | Load the controller's view | The breadcrumb's height constraint constant is `24` |
| devc-030 | content-spans-container-width | Load the controller's view | Both the breadcrumb's and the hosting view's leading/trailing constraints pin to the stack's leading/trailing anchors |
| devc-031 | root-view-initial-frame | Call `loadView()` | The returned root view's initial frame is `(0, 0, 520, 424)`; the stack's top/bottom/leading/trailing constraints pin to the root view |
| devc-032 | content-uses-themed-root | Inspect the hosted `NSHostingView`'s root view modifier chain | `.themedRoot()` is applied — verified by code inspection; a modifier chain cannot be introspected in XCTest |
| devc-033 | hosts-file-editor-view | Load the controller's view with a non-nil selection | The hosted content is a `FileEditorView` receiving that selection, `options`, `documentStore`, `saveScheduler`, and `languageServices` |
| devc-034 | breadcrumb-selection-routes-out | Install a closure on `onOpenRequest`; invoke the breadcrumb's `onSelect` with a URL | `onOpenRequest` is called with that URL; `fileURL` is unchanged |
| devc-035 | editor-open-request-routes-out | Install a closure on `onOpenRequest`; invoke the hosted content's `openFile` closure with a URL | `onOpenRequest` is called with that URL |
| devc-038 | construction-title-change | Install a closure on `onTitleChange`; construct a controller whose `store` has `fileURLKey` set to an existing file's path | The closure is called during construction |
