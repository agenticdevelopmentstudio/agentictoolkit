import Testing
import Foundation
@testable import AgenticToolkitCore

@Suite
struct ActivationEventMatcherTests {

    private static func manifest(
        engines: String = "^1.74.0",
        activationEvents: [String] = [],
        commands: [String] = []
    ) throws -> ExtensionManifest {
        let commandsJSON = commands
            .map { "{ \"command\": \"\($0)\", \"title\": \"\($0)\" }" }
            .joined(separator: ", ")
        let eventsJSON = activationEvents
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ", ")
        let json = """
        {
            "name": "fixture",
            "version": "1.0.0",
            "engines": { "vscode": "\(engines)" },
            "activationEvents": [\(eventsJSON)],
            "contributes": { "commands": [\(commandsJSON)] }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    // MARK: - Parsing

    @Test("each recognised shape parses to the right Kind and keeps rawValue verbatim")
    func parsesEachRecognisedShape() {
        let any = ActivationEvent(rawValue: "*")
        #expect(any?.kind == .any)
        #expect(any?.rawValue == "*")

        let startup = ActivationEvent(rawValue: "onStartupFinished")
        #expect(startup?.kind == .startupFinished)
        #expect(startup?.rawValue == "onStartupFinished")

        let language = ActivationEvent(rawValue: "onLanguage:swift")
        #expect(language?.kind == .language("swift"))
        #expect(language?.rawValue == "onLanguage:swift")

        let command = ActivationEvent(rawValue: "onCommand:foo.bar")
        #expect(command?.kind == .command("foo.bar"))
        #expect(command?.rawValue == "onCommand:foo.bar")

        let workspace = ActivationEvent(rawValue: "workspaceContains:**/*.csproj")
        #expect(workspace?.kind == .workspaceContains("**/*.csproj"))
        #expect(workspace?.rawValue == "workspaceContains:**/*.csproj")
    }

    @Test(
        "empty payloads, blank entries and gibberish are unrecognized",
        arguments: [
            "onLanguage:", "onCommand:", "workspaceContains:",
            "", "   ", "onDebug", "onView:explorer"
        ]
    )
    func unrecognizedEntries(_ raw: String) {
        #expect(ActivationEvent(rawValue: raw) == nil)
    }

    @Test("whitespace around an otherwise valid entry is trimmed before parsing")
    func trimsWhitespace() {
        let event = ActivationEvent(rawValue: "  onStartupFinished  ")
        #expect(event?.kind == .startupFinished)
    }

    @Test("a manifest mixing valid and invalid entries keeps both lists, in order")
    func mixedManifestKeepsBothLists() throws {
        let manifest = try Self.manifest(activationEvents: [
            "onStartupFinished", "onDebug", "onLanguage:swift", "onView:explorer", "onCommand:x.y"
        ])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.events.map(\.rawValue) == ["onStartupFinished", "onLanguage:swift", "onCommand:x.y"])
        #expect(matcher.unrecognizedEvents == ["onDebug", "onView:explorer"])
    }

    // MARK: - Matching

    @Test("\"*\" matches every trigger case and activatesEagerly is true")
    func eagerActivationMatchesEverything() throws {
        let manifest = try Self.manifest(activationEvents: ["*"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.activatesEagerly)
        #expect(matcher.matches(.startupFinished))
        #expect(matcher.matches(.documentOpened(languageID: "swift")))
        #expect(matcher.matches(.commandInvoked("anything")))
        #expect(matcher.matches(.workspaceScanned(relativePaths: [])))
    }

    @Test("onStartupFinished matches .startupFinished and nothing else")
    func startupFinishedMatchesOnlyItself() throws {
        let manifest = try Self.manifest(activationEvents: ["onStartupFinished"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.startupFinished))
        #expect(!matcher.matches(.documentOpened(languageID: "swift")))
        #expect(!matcher.matches(.commandInvoked("x")))
        #expect(!matcher.matches(.workspaceScanned(relativePaths: ["a"])))
    }

    @Test("onLanguage:swift matches only an exact, case-sensitive languageID")
    func languageMatchIsExactAndCaseSensitive() throws {
        let manifest = try Self.manifest(activationEvents: ["onLanguage:swift"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.documentOpened(languageID: "swift")))
        #expect(!matcher.matches(.documentOpened(languageID: "Swift")))
        #expect(!matcher.matches(.documentOpened(languageID: "swiftui")))
    }

    @Test("onCommand:a.b matches only the exact command id")
    func commandMatchIsExact() throws {
        let manifest = try Self.manifest(activationEvents: ["onCommand:a.b"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.commandInvoked("a.b")))
        #expect(!matcher.matches(.commandInvoked("a")))
        #expect(!matcher.matches(.commandInvoked("a.b.c")))
    }

    @Test("an empty manifest matches nothing and does not activate eagerly")
    func emptyManifestMatchesNothing() throws {
        let manifest = try Self.manifest(engines: "^1.74.0", activationEvents: [], commands: [])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(!matcher.activatesEagerly)
        #expect(!matcher.matches(.startupFinished))
        #expect(!matcher.matches(.documentOpened(languageID: "swift")))
        #expect(!matcher.matches(.commandInvoked("x")))
        #expect(!matcher.matches(.workspaceScanned(relativePaths: ["a"])))
    }

    // MARK: - Implicit activation

    @Test("engine ^1.74.0 with a declared command and no onCommand: entry still activates")
    func implicitActivationAtTheFloor() throws {
        let manifest = try Self.manifest(engines: "^1.74.0", activationEvents: [], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.implicitlyActivatingCommands == ["x.run"])
        #expect(matcher.matches(.commandInvoked("x.run")))
    }

    @Test("engine ^1.73.0 with the same command does not implicitly activate")
    func noImplicitActivationBelowTheFloor() throws {
        let manifest = try Self.manifest(engines: "^1.73.0", activationEvents: [], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.implicitlyActivatingCommands.isEmpty)
        #expect(!matcher.matches(.commandInvoked("x.run")))
    }

    @Test("engine >=1.80.0 implicitly activates its declared commands")
    func implicitActivationAboveTheFloorWithAtLeast() throws {
        let manifest = try Self.manifest(engines: ">=1.80.0", activationEvents: [], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.commandInvoked("x.run")))
    }

    @Test("engine 1.74.0 (exact) implicitly activates its declared commands")
    func implicitActivationWithExactEngine() throws {
        let manifest = try Self.manifest(engines: "1.74.0", activationEvents: [], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.commandInvoked("x.run")))
    }

    @Test("an unparseable engine string gets no implicit activation")
    func unparseableEngineGetsNoImplicitActivation() throws {
        let manifest = try Self.manifest(engines: "~1.74.0", activationEvents: [], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.implicitlyActivatingCommands.isEmpty)
        #expect(!matcher.matches(.commandInvoked("x.run")))
    }

    @Test("an explicit onCommand: entry still matches regardless of engine version")
    func explicitOnCommandIgnoresEngineVersion() throws {
        let manifest = try Self.manifest(
            engines: "^1.60.0", activationEvents: ["onCommand:x.run"], commands: ["x.run"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.implicitlyActivatingCommands.isEmpty)
        #expect(matcher.matches(.commandInvoked("x.run")))
    }

    // MARK: - Globs

    @Test(
        "glob matching, table-driven",
        arguments: [
            ("package.json", "package.json", true),
            ("package.json", "src/package.json", false),
            ("**/package.json", "package.json", true),
            ("**/package.json", "a/b/package.json", true),
            ("*.csproj", "a.csproj", true),
            ("*.csproj", "src/a.csproj", false),
            ("**/*.csproj", "a.csproj", true),
            ("**/*.csproj", "src/deep/a.csproj", true),
            (".vscode/tasks.json", ".vscode/tasks.json", true),
            (".vscode/tasks.json", "other/.vscode/tasks.json", false),
            ("src/*/index.ts", "src/a/index.ts", true),
            ("src/*/index.ts", "src/a/b/index.ts", false),
            ("?.txt", "a.txt", true),
            ("?.txt", "ab.txt", false),
            ("**/{package.json,bower.json}", "package.json", true),
            ("**/{package.json,bower.json}", "bower.json", true),
            ("**/{package.json,bower.json}", "other.json", false),
            ("a.txt", "axtxt", false)
        ] as [(String, String, Bool)]
    )
    func globMatching(pattern: String, path: String, expected: Bool) throws {
        let manifest = try Self.manifest(activationEvents: ["workspaceContains:\(pattern)"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.matches(.workspaceScanned(relativePaths: [path])) == expected)
    }

    @Test(
        "unsupported glob syntax lands in unsupportedPatterns and never matches",
        arguments: ["[abc].txt", "!foo"]
    )
    func unsupportedGlobSyntax(_ pattern: String) throws {
        let manifest = try Self.manifest(activationEvents: ["workspaceContains:\(pattern)"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(matcher.unsupportedPatterns == [pattern])
        #expect(!matcher.matches(.workspaceScanned(relativePaths: [pattern])))
    }

    @Test("workspaceContains: against an empty relativePaths matches nothing")
    func emptyWorkspaceScanMatchesNothing() throws {
        let manifest = try Self.manifest(activationEvents: ["workspaceContains:**/*.csproj"])
        let matcher = ActivationEventMatcher(manifest: manifest)

        #expect(!matcher.matches(.workspaceScanned(relativePaths: [])))
    }
}
