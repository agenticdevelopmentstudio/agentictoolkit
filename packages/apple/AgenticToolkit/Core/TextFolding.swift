//
//  TextFolding.swift
//  AgenticToolkit
//

import Foundation

/// Case- and diacritic-insensitive, locale-independent folding for substring
/// filters.
///
/// Extracted from `CommandPaletteModel.folded(_:)`
/// (`macOS/Features/CommandPalette/CommandPaletteModel.swift`), which had the
/// only `diacriticInsensitive` in the package before `ExtensionQuickPickModel`
/// needed the same fold for its own filter. It lives in `AgenticToolkitCore`
/// rather than beside either caller because the body needs only Foundation,
/// and the tier map's rule is the lowest tier that can hold it.
public enum TextFolding {

    /// Case- and diacritic-insensitive, locale-independent folding for
    /// substring filters.
    ///
    /// `locale: nil` keeps the folding the same everywhere a caller uses it —
    /// neither an id nor a title is localised, and a Turkish locale's
    /// dotless-i rule would otherwise make a filter answer differently on one
    /// machine than another.
    public static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
