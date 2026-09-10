import XCTest

/// Every git process in the toolkit must be spawned by `GitClient`. This test
/// scans the four framework source trees for the executable path and the
/// argument spellings that would mean someone bypassed it.
final class GitProcessBottleneckTests: XCTestCase {
    private static let allowedFiles: Set<String> = [
        "Core/Git/GitClient.swift",
        "Core/Git/GitClientConfiguration.swift",
        "Core/SettingStorage/UserSettings+Git.swift"
    ]

    private static let forbiddenSpellings = ["/usr/bin/git", "\"git\""]

    private var packageRoot: URL {
        // <root>/Tests/AgenticToolkitMacOSTests/Git/GitProcessBottleneckTests.swift
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Git
            .deletingLastPathComponent()  // AgenticToolkitMacOSTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    func testOnlyGitClientNamesTheGitExecutable() throws {
        var offenders: [String] = []
        for tier in ["Core", "CoreUI", "CoreMacOS", "macOS"] {
            let tierURL = packageRoot.appendingPathComponent(tier)
            guard let enumerator = FileManager.default.enumerator(
                at: tierURL,
                includingPropertiesForKeys: nil
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                let relative = String(file.path.dropFirst(packageRoot.path.count + 1))
                if Self.allowedFiles.contains(relative) { continue }
                let source = try String(contentsOf: file, encoding: .utf8)
                for spelling in Self.forbiddenSpellings where source.contains(spelling) {
                    offenders.append("\(relative) contains \(spelling)")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Route these through GitClient:\n" + offenders.joined(separator: "\n"))
    }
}
