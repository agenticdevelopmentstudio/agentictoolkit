import XCTest
@testable import AgenticToolkitMacOS

/// Builds a `ProjectsCoordinator` the way `ProjectWindowManagerControllerTests`
/// does: a throwaway `ProjectDatabase` on disk (there is no in-memory mode)
/// and a fresh `CommandRegistry`, since these tests only need the menu the
/// coordinator's `init` builds, never a project actually open.
@MainActor
private func makeProjectsCoordinator() throws -> ProjectsCoordinator {
    let databasePath = FileManager.default.temporaryDirectory
        .appendingPathComponent("projects-menu-test-\(UUID().uuidString).db")
        .path
    let database = try ProjectDatabase(path: databasePath)
    return try ProjectsCoordinator(database: database, scanner: nil, commandRegistry: CommandRegistry())
}

@MainActor
final class ProjectsMenuTests: XCTestCase {

    func testOpenProjectUsesOptionCommandP() throws {
        let coordinator = try makeProjectsCoordinator()
        let contribution = try XCTUnwrap(
            coordinator.menuContributions.first { $0.title == "Open Project…" })

        XCTAssertEqual(contribution.key, "p")
        XCTAssertEqual(contribution.modifiers, [.command, .option])
    }

    func testItDoesNotCollideWithTheCommandPalette() throws {
        let coordinator = try makeProjectsCoordinator()
        let contribution = try XCTUnwrap(
            coordinator.menuContributions.first { $0.title == "Open Project…" })

        XCTAssertNotEqual(contribution.modifiers, [.command, .shift],
                          "shift-command-P is the command palette")
    }
}
