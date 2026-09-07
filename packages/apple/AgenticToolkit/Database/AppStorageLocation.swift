import Foundation

/// Where an app keeps its own files, derived from its display name without
/// assuming that name is safe to put in a path.
///
/// A display name is chosen for menu bars, not filesystems: "Coffee Grinder"
/// has a space in it, and `~/.coffee grinder/` is the hostile default that
/// `ProjectDatabase.defaultPath` already argued against in prose while
/// producing it in code. The token is the name reduced to what a path can hold.
public enum AppStorageLocation {

    /// The fallback when a bundle carries no usable name — also what a test
    /// harness with no `CFBundleName` gets.
    public static let fallbackToken = "AgenticToolkit"

    /// `"Coffee Grinder"` -> `"CoffeeGrinder"`. Everything that is not a letter
    /// or a digit is dropped rather than substituted: a separator would only
    /// move the problem (`.coffee-grinder` vs `.coffee_grinder` is a coin toss
    /// that later has to be guessed correctly to find the file again).
    public static func token(for displayName: String) -> String {
        let stripped = displayName.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
        return stripped.isEmpty ? fallbackToken : stripped
    }

    /// The running app's token, from `CFBundleName`.
    public static var token: String {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return token(for: name ?? fallbackToken)
    }

    /// `~/.<token lowercased>` — the one directory all of this app's stores
    /// share. Each store picks its own filename inside it; they must not share
    /// a *file* (see `MarkdownStore.defaultPath`).
    public static func directory(inHome home: URL, token: String = AppStorageLocation.token) -> URL {
        home.appendingPathComponent(".\(token.lowercased())")
    }
}
