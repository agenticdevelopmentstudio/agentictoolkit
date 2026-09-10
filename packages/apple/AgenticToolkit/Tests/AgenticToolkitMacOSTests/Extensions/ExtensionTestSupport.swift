import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Doubles and fixtures shared by the extension suites in this folder.
///
/// One copy, not three. The doubles that exist elsewhere live in
/// `AgenticToolkitCoreTests` and in the AgenticDeveloperToolkit submodule's own
/// test target, and neither is reachable from this bundle — but that argument
/// covers *other targets*, and said nothing about three byte-for-byte copies in
/// this one.

/// An in-memory `ThemeStorage`. The protocol is three requirements on an
/// `AnyObject`, and nothing in these suites needs a disk or a settings domain.
@MainActor
final class ExtensionTestThemeStorage: ThemeStorage {
    var customThemes: [ColorTheme] = []
    var activeThemeID: String?
    /// Never invoked: `onExternalChange` fires for writes that bypass
    /// `ThemeStore`, and these suites make none.
    var onExternalChange: (() -> Void)?
}

/// Files on disk that the extension subsystem reads for real.
enum ExtensionFixtures {

    /// A theme file `VSCodeThemeImporter` accepts. `editor.foreground` differs
    /// from `editor.background` (the importer refuses a theme where they match)
    /// and all sixteen ANSI keys are present, because the importer throws
    /// naming the missing ones.
    ///
    /// Its `name` deliberately matches no label any test declares, so a test
    /// asserting that the manifest's label wins cannot pass by coincidence.
    static let goodThemeJSON = """
    {
        "name": "The Theme File's Own Name",
        "type": "dark",
        "colors": {
            "editor.foreground": "#D8DEE9",
            "editor.background": "#2E3440",
            "editorCursor.foreground": "#FF00FF",
            "editor.selectionBackground": "#4C566A",
            "terminal.ansiBlack": "#000000",
            "terminal.ansiRed": "#010000",
            "terminal.ansiGreen": "#020000",
            "terminal.ansiYellow": "#030000",
            "terminal.ansiBlue": "#040000",
            "terminal.ansiMagenta": "#050000",
            "terminal.ansiCyan": "#060000",
            "terminal.ansiWhite": "#070000",
            "terminal.ansiBrightBlack": "#080000",
            "terminal.ansiBrightRed": "#090000",
            "terminal.ansiBrightGreen": "#0A0000",
            "terminal.ansiBrightYellow": "#0B0000",
            "terminal.ansiBrightBlue": "#0C0000",
            "terminal.ansiBrightMagenta": "#0D0000",
            "terminal.ansiBrightCyan": "#0E0000",
            "terminal.ansiBrightWhite": "#0F0000"
        }
    }
    """

    /// Valid JSON, but not a theme: no `colors` at all. The point must treat
    /// this as one file's problem, never as a syntax error it could not have
    /// anticipated.
    static let malformedThemeJSON = #"{ "name": "Broken" }"#

    static func makeTemporaryDirectory(_ label: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `contents` at `relativePath` under `directory`, creating any
    /// intermediate folders the path names.
    static func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        // `appendingPathComponent`, deliberately not `URL(fileURLWithPath:
        // relativeTo:)`: that is how the code under test resolves a declared
        // path, and a fixture that arrives at its path by the subject's own
        // route can only ever agree with it. The first round of this task shows
        // what that costs — the fixture writer dropped `isDirectory: true`,
        // eleven tests failed, and the tell was the one test that *passed*,
        // because it wrote and read through the same wrong resolution.
        let url = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A `ColorTheme` carrying `id` and `attribution`, to stand in for a row a
    /// previous launch left in the user's store.
    ///
    /// Built by parsing the same fixture the subject parses, because
    /// `ColorTheme` has no cheap literal form and inventing one here would be a
    /// second answer to what a theme is.
    @MainActor
    static func colorTheme(id: String, attribution: String?, in directory: URL) throws -> ColorTheme {
        let name = "seed-\(UUID().uuidString).json"
        try write(goodThemeJSON, to: name, in: directory)
        var theme = try VSCodeThemeImporter.parse(
            contentsOf: directory.appendingPathComponent(name),
            label: "Seeded",
            uiTheme: "vs-dark"
        )
        theme.id = id
        theme.attribution = attribution
        return theme
    }
}

/// Runs `body` against a `UserSettings.shared` backed by memory, and puts the
/// process-wide one back afterwards.
///
/// Synchronous on purpose, and the suites that call it are `@MainActor` with
/// synchronous test bodies: that is what makes the swap and the restore one
/// uninterrupted main-actor block. A single `await` inside here would let
/// another `@MainActor` suite in this 65-suite target observe the temporary
/// settings, and the failure would surface as a flake somewhere else entirely.
@MainActor
func withInMemorySettings<Result>(_ body: () throws -> Result) rethrows -> Result {
    let previous = UserSettings.shared
    UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
    defer { UserSettings.shared = previous }
    return try body()
}
