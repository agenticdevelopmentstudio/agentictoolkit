//
//  LSPCompletionEntry.swift
//  AgenticToolkit
//

import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import SwiftUI

/// One row in `CodeEditSourceEditor`'s completion window, backed by an LSP
/// `CompletionItem`.
///
/// `CodeSuggestionEntry` is a protocol with no default implementations, and the
/// two types in the package that conform to it are `JumpToDefinitionLink` and
/// the Example app's mock — neither can carry a `CompletionItem`. So this is
/// the toolkit's own conformance, and it keeps the item it was built from
/// because applying a completion needs the item's `textEdit`, `insertText` and
/// `insertTextFormat`, not just its label.
struct LSPCompletionEntry: CodeSuggestionEntry {

    /// The server's item, kept whole: `LSPCompletionDelegate` reads
    /// `textEdit`/`insertText`/`insertTextFormat` off it when the user picks
    /// this row.
    let item: CompletionItem

    /// The document range this entry's request was made against — the server's
    /// own `textEdit` range when it sent one, otherwise the identifier prefix
    /// the request started at.
    ///
    /// It has to be carried on the entry because the range cannot be recovered
    /// later: `completionWindowApplyCompletion` is handed the *live* cursor,
    /// which has moved by however much the user typed while the window was
    /// open. See `LSPCompletionDelegate.completionWindowApplyCompletion`.
    let requestRange: LSPRange

    /// What `completionOnCursorMove` filters on: LSP says `filterText` when the
    /// server sent one, otherwise the label.
    var filterKey: String { item.filterText ?? item.label }

    // MARK: - CodeSuggestionEntry

    var label: String { item.label }

    var detail: String? { item.detail }

    var documentation: String? {
        switch item.documentation {
        case .optionA(let text): return text
        case .optionB(let markup): return markup.value
        case nil: return nil
        }
    }

    // `pathComponents`, `targetPosition` and `sourcePreview` are the
    // jump-to-definition half of `CodeSuggestionEntry` — the package reuses the
    // completion window to disambiguate several jump targets, and those three
    // are what a `JumpToDefinitionLink` fills in. A completion has no target
    // file, no target position and no source line to preview, so they are `nil`
    // deliberately, not by omission.
    var pathComponents: [String]? { nil }
    var targetPosition: CursorPosition? { nil }
    var sourcePreview: String? { nil }

    var image: Image { Image(systemName: Self.symbolName(for: item.kind)) }

    var imageColor: SwiftUI.Color { Self.color(for: item.kind) }

    /// This version of `LanguageServerProtocol` exposes only the deprecated
    /// *boolean* on `CompletionItem` — `CompletionItemTag` exists as an enum
    /// but `CompletionItem` has no `tags` array to read it from — so there is
    /// one signal to honour, not two.
    var deprecated: Bool { item.deprecated ?? false }

    // MARK: - Kind mapping

    /// SF Symbol per `CompletionItemKind`, with one neutral default for the
    /// kinds not worth naming individually. Reversible and low blast radius:
    /// nothing but the icon in a popover row depends on any of these.
    private static func symbolName(for kind: CompletionItemKind?) -> String {
        switch kind {
        case .method, .function: return "function"
        case .constructor: return "hammer"
        case .field, .property: return "list.bullet.rectangle"
        case .variable: return "v.square"
        case .class: return "c.square"
        case .interface: return "i.square"
        case .struct: return "s.square"
        case .enum: return "e.square"
        case .enumMember: return "e.circle"
        case .typeParameter: return "t.square"
        case .module: return "shippingbox"
        case .constant, .value: return "number.square"
        case .keyword: return "k.square"
        case .operator: return "plusminus"
        case .snippet: return "curlybraces"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .folder: return "folder"
        case .reference: return "link"
        case .event: return "bolt"
        case .unit: return "ruler"
        case .text: return "text.alignleft"
        case nil: return "dot.square.fill"
        }
    }

    /// Colors come from `NSColor`'s system set rather than the app palette:
    /// these entries are built by a delegate that has no access to the
    /// toolkit's `themePalette` environment value, and they are rendered inside
    /// the package's own popover, which has no access to it either. The system
    /// colors already follow light/dark, which is the part that matters.
    private static func color(for kind: CompletionItemKind?) -> SwiftUI.Color {
        switch kind {
        case .method, .function, .constructor: return SwiftUI.Color(nsColor: .systemPurple)
        case .variable, .field, .property: return SwiftUI.Color(nsColor: .systemTeal)
        case .class, .struct, .interface, .enum, .typeParameter: return SwiftUI.Color(nsColor: .systemBlue)
        case .constant, .value, .enumMember: return SwiftUI.Color(nsColor: .systemOrange)
        case .keyword, .operator: return SwiftUI.Color(nsColor: .systemPink)
        case .module, .file, .folder, .reference: return SwiftUI.Color(nsColor: .systemGray)
        default: return SwiftUI.Color(nsColor: .secondaryLabelColor)
        }
    }
}
