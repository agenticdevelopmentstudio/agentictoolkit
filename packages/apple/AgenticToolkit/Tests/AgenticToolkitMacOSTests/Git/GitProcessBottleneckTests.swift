import XCTest

/// Every git process the toolkit spawns must come out of `GitClient`, so that
/// git usage — by the app and by agents driving it — is countable in one place.
/// This test is the guard: it walks all twelve framework tiers and fails on any
/// file outside the abstraction that spells a git command line.
///
/// **What it does and does not promise.** It catches an honest regression — a
/// new feature that reaches for `Process()` and `/usr/bin/git` because that is
/// the shortest path — which is the only failure mode a bottleneck like this
/// actually suffers. It does not defeat deliberate evasion: a file that builds
/// its executable path from concatenated fragments, or hides the verb inside a
/// string interpolation, walks straight through, and no textual scan of source
/// can change that. Read a pass as "nobody did this by accident", never as
/// "nobody can".
///
/// `App/`'s half of the same guard lives in the consuming project's own test
/// bundle (`App/Tests/Git/AppGitProcessBottleneckTests.swift`); a test in this
/// repository cannot reach up into a repository that consumes it. The two
/// signal lists are deliberately identical — change one and change the other.
final class GitProcessBottleneckTests: XCTestCase {
    /// Every source directory that ships in a framework. Listed rather than
    /// discovered so that adding a tier without adding it here is a decision
    /// somebody makes, not an omission the scan absorbs silently.
    static let tiers = [
        "AIPluginKit", "Core", "CoreMacOS", "CoreUI", "Database", "Language",
        "macOS", "Markdown", "Permissions", "PermissionsUI", "Sync", "SyncGRDB"
    ]

    /// Which file may contain which spelling.
    ///
    /// The allowance is per spelling, not per file, and that distinction is the
    /// whole guard. Everything in `Core/Git/` is the door or a parser of what
    /// came through it, so the git vocabulary belongs there wholesale, and
    /// `UserSettings+Git.swift` holds the default executable path the user may
    /// override. The settings panel is the third case and a narrower one: its
    /// entire job is letting the user edit `gitExecutablePath`, so it cannot
    /// avoid naming that setting — but it has no business naming an executable
    /// or a git verb, and a file-level allowlist entry would have let it spawn
    /// git undetected. It gets the one spelling it needs and nothing else.
    static func isAllowed(_ relativePath: String, _ spelling: String) -> Bool {
        if relativePath.hasPrefix("Core/Git/") { return true }
        if relativePath == "Core/SettingStorage/UserSettings+Git.swift" { return true }
        if relativePath == "macOS/Features/Git/Settings/GitSettingsPanelViewController.swift" {
            return spelling == "gitExecutablePath"
        }
        return false
    }

    /// Spellings that mean a file is composing a git command line for itself.
    ///
    /// Three kinds, and each earns its place by catching something the others
    /// miss. The executable spellings (`/usr/bin/git`, a bare `"git"` literal,
    /// and `/usr/bin/env`, which launches by name off `PATH`) catch a spawn
    /// that names git directly. `gitExecutablePath` catches a spawn that reads
    /// the user's configured path instead, which names git without the string.
    /// And git's own argument vocabulary catches a spawn routed through a
    /// shell — `/bin/sh -c "git rev-parse …"` names neither an executable this
    /// list knows nor the setting, but it cannot avoid naming the verb.
    static let forbiddenSpellings = [
        "/usr/bin/git",
        "/usr/bin/env",
        "\"git\"",
        "gitExecutablePath",
        "rev-parse",
        "for-each-ref",
        "--abbrev-ref",
        "--porcelain",
        "--git-dir",
        "--no-pager"
    ]

    private var packageRoot: URL {
        // <root>/Tests/AgenticToolkitMacOSTests/Git/GitProcessBottleneckTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Git
            .deletingLastPathComponent()  // AgenticToolkitMacOSTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    /// Reports every `(relative path, spelling)` pair found under `root`, given
    /// a predicate naming the files allowed to contain them.
    ///
    /// Shared by the real scan and by `testTheScanCatchesEachForbiddenSpelling`,
    /// so the thing under test and the thing doing the work are the same code.
    static func offenders(
        under root: URL,
        relativeTo base: URL,
        isAllowed: (String, String) -> Bool
    ) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        // Both sides resolved before they are compared. `/var` is a symlink to
        // `/private/var` on macOS, so a temporary directory and the files the
        // enumerator finds inside it can disagree by that prefix — and a
        // prefix-length subtraction that guesses wrong yields a garbage
        // relative path, which silently makes every allowlist check and every
        // assertion about a file name miss.
        let basePath = base.resolvingSymlinksInPath().path
        var offenders: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let path = file.resolvingSymlinksInPath().path
            let relative = path.hasPrefix(basePath + "/") ? String(path.dropFirst(basePath.count + 1)) : path
            let source = try String(contentsOf: file, encoding: .utf8)
            for spelling in forbiddenSpellings
            where source.contains(spelling) && !isAllowed(relative, spelling) {
                offenders.append("\(relative) contains \(spelling)")
            }
        }
        return offenders.sorted()
    }

    func testEveryTierDirectoryExists() {
        for tier in Self.tiers {
            let url = packageRoot.appendingPathComponent(tier)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "Tier '\(tier)' is listed but not on disk — a rename would silently shrink the scan"
            )
        }
    }

    func testOnlyGitClientNamesTheGitExecutable() throws {
        var offenders: [String] = []
        for tier in Self.tiers {
            offenders += try Self.offenders(
                under: packageRoot.appendingPathComponent(tier),
                relativeTo: packageRoot,
                isAllowed: Self.isAllowed
            )
        }
        XCTAssertEqual(offenders, [], "Route these through GitClient:\n" + offenders.joined(separator: "\n"))
    }

    /// The scan is only worth its name if it actually fires. Each spelling gets
    /// a synthetic source file in a throwaway directory, and each must be
    /// reported — otherwise a typo in the list above turns the guard above into
    /// a test that passes because it looks at nothing.
    func testTheScanCatchesEachForbiddenSpelling() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-bottleneck-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for (index, spelling) in Self.forbiddenSpellings.enumerated() {
            let file = root.appendingPathComponent("Probe\(index).swift")
            try "let probe = \"\(spelling)\"\n".write(to: file, atomically: true, encoding: .utf8)
        }
        // A file with none of the spellings, to prove the scan is not simply
        // reporting everything it reads.
        try "let innocent = \"hello\"\n"
            .write(to: root.appendingPathComponent("Innocent.swift"), atomically: true, encoding: .utf8)

        let offenders = try Self.offenders(under: root, relativeTo: root, isAllowed: { _, _ in false })
        for (index, spelling) in Self.forbiddenSpellings.enumerated() {
            XCTAssertTrue(
                offenders.contains("Probe\(index).swift contains \(spelling)"),
                "The scan missed \(spelling)"
            )
        }
        XCTAssertFalse(
            offenders.contains { $0.hasPrefix("Innocent.swift") },
            "The scan reported a file containing none of the spellings"
        )
    }

    /// The four bypasses a reviewer actually planted against the first version
    /// of this test, which caught none of them.
    ///
    /// Three are now caught, each by a different signal, which is why the list
    /// has three kinds in it rather than one. The fourth — an executable path
    /// assembled from fragments — is still not caught, and is asserted here as
    /// *not* caught on purpose: it is the honest boundary of a textual scan,
    /// and a test that quietly hoped otherwise is how the first version came to
    /// look like a guarantee.
    func testTheScanCatchesTheBypassesThatDefeatedTheFirstVersion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-bypass-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bypasses = [
            "ShellRouted.swift": #"let argv = ["/bin/sh", "-c", "git rev-parse --abbrev-ref HEAD"]"#,
            "SettingsRouted.swift": "let path = UserSettings.gitExecutablePath.value",
            "EnvLauncher.swift": #"let argv = ["/usr/bin/env", "gi" + "t", "status"]"#
        ]
        for (name, source) in bypasses {
            try (source + "\n").write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let concatenated = "Concatenated.swift"
        try (#"let path = "/usr/bin/gi" + "t""# + "\n")
            .write(to: root.appendingPathComponent(concatenated), atomically: true, encoding: .utf8)

        let offenders = try Self.offenders(under: root, relativeTo: root, isAllowed: { _, _ in false })
        for name in bypasses.keys {
            XCTAssertTrue(
                offenders.contains { $0.hasPrefix(name) },
                "\(name) is a bypass this scan is supposed to catch"
            )
        }
        XCTAssertFalse(
            offenders.contains { $0.hasPrefix(concatenated) },
            """
            A fragmented executable path is still invisible to a textual scan. \
            If this now fails, the scan grew a real ability and the class doc's \
            promise should be widened to match.
            """
        )
    }

    /// The allowlist has to be narrow enough to still catch a bypass planted in
    /// an allowed tier but an unrelated directory.
    func testTheAllowlistCoversTheAbstractionAndNothingElse() {
        XCTAssertTrue(Self.isAllowed("Core/Git/GitClient.swift", "/usr/bin/git"))
        XCTAssertTrue(Self.isAllowed("Core/SettingStorage/UserSettings+Git.swift", "/usr/bin/git"))
        XCTAssertFalse(Self.isAllowed("Core/SettingStorage/UserSettings.swift", "/usr/bin/git"))
        XCTAssertFalse(Self.isAllowed("macOS/Features/TerminalSession/TerminalSession.swift", "/usr/bin/git"))
        XCTAssertFalse(Self.isAllowed("CoreMacOS/Git/SomethingNew.swift", "/usr/bin/git"))
    }

    /// The settings panel's allowance is one spelling wide, and the half that
    /// matters is what it still refuses. A panel that edits the executable path
    /// must name the setting; a panel that *spawns* the executable is the exact
    /// bypass this whole test exists to catch, and moving the allowance from
    /// per-file to per-spelling is what keeps the second from riding in on the
    /// first.
    func testTheSettingsPanelMayNameTheSettingButNotSpawnGit() {
        let panel = "macOS/Features/Git/Settings/GitSettingsPanelViewController.swift"
        XCTAssertTrue(Self.isAllowed(panel, "gitExecutablePath"))
        for spelling in Self.forbiddenSpellings where spelling != "gitExecutablePath" {
            XCTAssertFalse(
                Self.isAllowed(panel, spelling),
                "The settings panel must not be allowed to name \(spelling)"
            )
        }
    }
}
