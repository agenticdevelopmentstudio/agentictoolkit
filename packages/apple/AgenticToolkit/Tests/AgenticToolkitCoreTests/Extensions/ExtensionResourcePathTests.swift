import Foundation
import Testing
@testable import AgenticToolkitCore

/// The one containment rule every extension-declared path goes through.
///
/// The four call sites — snippets, themes, a theme's `include` and the host's
/// entry point — have their own suites, and each proves the rule is *wired in*
/// there. This one proves the rule itself, on the cases those suites cannot
/// reach through a manifest: an exactly-equal path, a symlinked base, a base
/// that never announced itself as a directory.
@Suite
struct ExtensionResourcePathTests {

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionResourcePathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Resolution

    @Test("a path inside the directory resolves to a canonical URL")
    func resolvesInsideTheDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try ExtensionResourcePath.resolve("./themes/dark.json", inside: directory)

        let expected = directory.appendingPathComponent("themes/dark.json")
            .resolvingSymlinksInPath().standardizedFileURL
        #expect(resolved.path == expected.path)
    }

    @Test("a path written without a ./ prefix resolves too")
    func resolvesWithoutDotSlash() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try ExtensionResourcePath.resolve("snippets/x.code-snippets", inside: directory)
        #expect(resolved.lastPathComponent == "x.code-snippets")
        #expect(resolved.deletingLastPathComponent().lastPathComponent == "snippets")
    }

    @Test("a base with no is-directory flag still resolves inside it, not beside it")
    func resolvesAgainstAFlaglessBase() throws {
        // `URL(fileURLWithPath:relativeTo:)` resolves against the base's
        // *parent* unless the base is known to be a directory, and a URL
        // restored from stored JSON or built before the folder existed arrives
        // flagless. That is an escape by itself: every declared file is read
        // one level up.
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let flagless = URL(fileURLWithPath: directory.path, isDirectory: false)
        try #require(!flagless.hasDirectoryPath)

        let resolved = try ExtensionResourcePath.resolve("./themes/dark.json", inside: flagless)

        #expect(resolved.deletingLastPathComponent().deletingLastPathComponent().path
            == directory.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    @Test("an escaping path is refused, naming what it declared and where it landed")
    func refusesAnEscape() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let landing = parent.appendingPathComponent("outside/secret.json")
            .resolvingSymlinksInPath().standardizedFileURL

        #expect(throws: ExtensionResourcePathError.escapesExtensionDirectory(
            declared: "../outside/secret.json",
            resolved: landing.path
        )) {
            _ = try ExtensionResourcePath.resolve("../outside/secret.json", inside: directory)
        }
    }

    @Test("the refusal describes itself to a person")
    func refusalIsASentence() throws {
        let error = ExtensionResourcePathError.escapesExtensionDirectory(
            declared: "../x.json", resolved: "/tmp/x.json"
        )
        // `SnippetFileFailure` and `ThemeImportFailure` both record
        // `error.localizedDescription` and show it to an extension author, so
        // the conformance is the difference between a sentence and Foundation's
        // "The operation couldn't be completed. (… error 0.)".
        #expect(error.localizedDescription.contains("../x.json"))
        #expect(error.localizedDescription.contains("/tmp/x.json"))
    }

    // MARK: - Two bases

    @Test("relativeTo and containedIn come apart for a nested file reaching upward")
    func resolvesRelativeToOneDirectoryContainedInAnother() throws {
        // A theme's `include`: written relative to the including file's folder,
        // bounded by the extension's.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let themes = root.appendingPathComponent("themes", isDirectory: true)
        try FileManager.default.createDirectory(at: themes, withIntermediateDirectories: true)

        let resolved = try ExtensionResourcePath.resolve(
            "../base.json", relativeTo: themes, containedIn: root
        )
        #expect(resolved.path == root.appendingPathComponent("base.json")
            .resolvingSymlinksInPath().standardizedFileURL.path)

        // One hop further is outside the root, and the wider base does not
        // license it.
        #expect(throws: ExtensionResourcePathError.self) {
            _ = try ExtensionResourcePath.resolve(
                "../../base.json", relativeTo: themes, containedIn: root
            )
        }
    }

    // MARK: - The containment primitive

    @Test("a sibling whose name merely starts with the base's name is not inside it")
    func siblingWithSharedNamePrefixIsNotInside() {
        // The reason this compares path *components* and not string prefixes.
        // The attacker picks the sibling's name.
        let base = URL(fileURLWithPath: "/tmp/ext", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/tmp/ext-evil/web.js")
        #expect(sibling.path.hasPrefix(base.path))
        #expect(!ExtensionResourcePath.url(sibling, isContainedIn: base))
    }

    @Test("the directory itself does not count as inside itself")
    func theBaseIsNotInsideItself() {
        // Strictly below, so a declared path of "." — which resolves to the
        // directory — cannot be handed to a file reader as if it were a file.
        let base = URL(fileURLWithPath: "/tmp/ext", isDirectory: true)
        #expect(!ExtensionResourcePath.url(base, isContainedIn: base))
    }

    @Test("a descendant several levels down is inside")
    func aDeepDescendantIsInside() {
        let base = URL(fileURLWithPath: "/tmp/ext", isDirectory: true)
        let deep = URL(fileURLWithPath: "/tmp/ext/a/b/c.json")
        #expect(ExtensionResourcePath.url(deep, isContainedIn: base))
    }

    @Test("a symlinked base and an unsymlinked candidate still compare")
    func symlinkedBaseCompares() throws {
        // On macOS the temp directory alone is a symlink (`/var` →
        // `/private/var`), so normalizing one side and not the other would
        // refuse every legitimate path — or, resolved the other way, would
        // accept an escape through a symlink planted inside the extension.
        let real = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: real) }
        let link = real.deletingLastPathComponent()
            .appendingPathComponent("link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: link) }

        // Declared through the link, bounded by the real directory: the same
        // file, so it is inside.
        let resolved = try ExtensionResourcePath.resolve(
            "./themes/dark.json", relativeTo: link, containedIn: real
        )
        #expect(resolved.path == real.appendingPathComponent("themes/dark.json")
            .resolvingSymlinksInPath().standardizedFileURL.path)
    }

    @Test("a symlink inside the directory pointing out of it is refused")
    func aSymlinkOutOfTheDirectoryIsRefused() throws {
        // The escape a `"../"` string check misses entirely: the declared path
        // contains no `..` at all.
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("ext", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "{}".write(to: outside.appendingPathComponent("secret.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("escape", isDirectory: true),
            withDestinationURL: outside
        )

        #expect(throws: ExtensionResourcePathError.self) {
            _ = try ExtensionResourcePath.resolve("./escape/secret.json", inside: directory)
        }
    }
}

/// Where user-installed add-ons are looked for — the pair
/// `AIPluginManager` and the app's extension host now both derive from, having
/// each hand-rolled it before.
///
/// Every case here is about *composition*, not the file system: nothing below
/// creates or reads a directory, because neither does the code under test.
@Suite("InstalledContentLocation")
struct InstalledContentLocationTests {

    @Test("The Application Support path is the app's folder, then the kind of content")
    func applicationSupportComposesBothComponents() throws {
        let url = try #require(InstalledContentLocation.applicationSupport(
            appName: "Coffee Grinder", subdirectory: "Extensions"))

        // The display name goes in with its space intact: that is how macOS
        // names an Application Support subdirectory.
        #expect(url.pathComponents.suffix(3) == ["Application Support", "Coffee Grinder", "Extensions"])
        #expect(url.deletingLastPathComponent().lastPathComponent == "Coffee Grinder")
    }

    @Test("The two hosts' Application Support paths differ only in the kind of content")
    func bothHostsShareTheApplicationSupportShape() throws {
        let plugins = try #require(InstalledContentLocation.applicationSupport(
            appName: "Coffee Grinder", subdirectory: "Plugins"))
        let extensions = try #require(InstalledContentLocation.applicationSupport(
            appName: "Coffee Grinder", subdirectory: "Extensions"))

        #expect(plugins.deletingLastPathComponent() == extensions.deletingLastPathComponent())
    }

    @Test("The dotfolder is hidden by this function, not by the caller's spelling")
    func homeDotDirectoryAddsTheDot() {
        let home = URL(fileURLWithPath: "/var/empty/fixture-home", isDirectory: true)

        #expect(
            InstalledContentLocation.homeDotDirectory(named: "agenticextensions", in: home).path
                == "/var/empty/fixture-home/.agenticextensions")
        #expect(
            InstalledContentLocation.homeDotDirectory(named: "agenticplugins", in: home).path
                == "/var/empty/fixture-home/.agenticplugins")
    }

    @Test("An injected home is used instead of the process's own")
    func theInjectedHomeWins() {
        let home = URL(fileURLWithPath: "/var/empty/fixture-home", isDirectory: true)
        let injected = InstalledContentLocation.homeDotDirectory(named: "agenticextensions", in: home)
        let processHome = InstalledContentLocation.homeDotDirectory(named: "agenticextensions")

        // The default is the process's own home — what a host that has no test
        // override to offer gets — and an injected one must not silently fall
        // back to it, or a test run would read the developer's installed
        // extensions.
        #expect(injected != processHome)
        #expect(processHome.deletingLastPathComponent().path == NSHomeDirectory())
    }
}
