# AgenticToolkitHTDV — native Hierarchical Topic Detail View

`AgenticToolkitHTDV` is a multi-platform (macOS 14+, iOS 26+) framework that renders a tree of "levels"
as side-by-side rails (regular width) or a navigation stack (compact width), with a detail pane for leaf
items. It depends on Foundation plus AppKit/UIKit only.

## Concepts

| Type | Role |
|---|---|
| `HTDVDataSource` | Vends `rootLevel()` and `child(for: path)`; implemented by feature modules. |
| `HTDVLevel` / `HTDVItem` | A titled list of rows. `item.leadsTo` is `.list` (another rail) or `.detail`. |
| `HTDVChild` | `.level`, `.detail(HTDVDetail)`, or `.empty`. |
| `HTDVDetail` | `make()` builds the detail view controller on the main actor. |
| `HTDVController` | `@MainActor` owner of `levels`, `selection`, `detail`, `loadingLevelIndex`, `error`. |
| `HTDVLayoutEngine` | Pure rails-vs-stack decision from width, level count, and size class. |
| `HTDVViewController` | AppKit/UIKit host wiring the controller to rails, breadcrumbs, and detail. |
| `FormSpec` + `FormState` + `FormViewController` | Declarative detail forms with validation, dirty tracking, save/revert/delete. |
| `MarkdownEditing` | Injectable markdown editor/viewer factory; `PlainTextMarkdownEditing` is the default. |
| `HTDVDetailHosting` | Detail VCs with unsaved state adopt it so the host confirms before replacing them. |

## Minimal use

```swift
final class PersonasSource: HTDVDataSource {
    func rootLevel() async throws -> HTDVLevel {
        HTDVLevel(id: "root", title: "Personas", items: [HTDVItem(id: "ada", label: "Ada", leadsTo: .detail)])
    }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let last = path.last else { return .empty }
        return .detail(HTDVDetail(id: last.id, title: last.label) {
            FormViewController(
                state: FormState(spec: FormSpec(sections: [
                    FormSection(fields: [.text(FormTextField(key: "name", label: "Name", isRequired: true))])
                ])),
                markdownEditing: PlainTextMarkdownEditing()
            )
        })
    }
}

let controller = HTDVController(dataSource: PersonasSource())
let host = HTDVViewController(controller: controller)
Task { await controller.load() }
```

`PersonasSource` needs no `@unchecked Sendable`: it holds no stored properties, so a `final class` conforms
to `HTDVDataSource`'s `Sendable` requirement on its own. Reach for `@unchecked Sendable` only when a data
source really does wrap mutable state (e.g. a lock-protected cache), and only around that lock.

On iOS, embed `HTDVViewController` in a `UINavigationController`; compact width pushes one screen per level.
The HTDV need not be that navigation controller's root — anything the host pushed below it is preserved.

### One host per controller

`HTDVController.onChange` and `FormState.onChange` are single-slot callbacks, not multicasts: each drives
exactly one host view controller, and the host assigns it when its view loads. Assigning `onChange` a second
time — a second `HTDVViewController` over the same controller, an inspector window alongside the main one, or
a debug observer — silently displaces the first observer, which then stops updating with no diagnostic. Give
each view its own `HTDVController` / `FormState`.

## Forms

Field kinds: `text`, `textArea`, `toggle`, `select`, `number`, `date`, `stringSet` (comma-separated entry),
`readOnly`, `markdown` (rendered via `MarkdownEditing`), `json` (validated on save). `FormValidator` messages
are user-facing. `FormState.blockedReason` disables saving and shows the reason (e.g. read-only members).

## Testing

`AgenticToolkitHTDVTests` (XCTest, macOS) covers the model, controller (including stale-result protection),
layout engine, validator, form state, plain-text markdown, rails, and `FormViewController`. iOS is verified
by building the scheme for `generic/platform=iOS Simulator`.

# AgenticToolkitHub

Depends on `AgenticToolkitHTDV` only. Holds `HubModules` (app-installed injection points such as
`markdownEditing`), `HubError`, `HubWorkspace` (+ `HubWorkspaceType`) — the shared, generated-code-free shape
the app maps the API's `Workspace` schema into, and passes to feature modules as their context — and, as
feature plans land, one `Features/<Name>/` folder per hub feature with `<Name>Models.swift`,
`<Name>DataSource.swift`, and `<Name>Module.swift`.
