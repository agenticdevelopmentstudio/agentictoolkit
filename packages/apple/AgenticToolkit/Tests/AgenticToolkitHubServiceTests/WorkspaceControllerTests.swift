import AgenticToolkitHub
import Foundation
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class WorkspaceControllerTests: XCTestCase {
    private let ada = HubWorkspace(slug: "ada", name: "Ada", type: .individual)
    private let acme = HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization)
    private let core = HubWorkspace(slug: "acme-core", name: "Core", type: .team)

    @MainActor
    private final class FakeWorkspaces: WorkspacesProviding {
        var workspaces: [HubWorkspace] = []
        var preferred: String?
        var listError: (any Error)?
        var prefError: (any Error)?
        var setError: (any Error)?
        var persisted: [String] = []
        var listCalls = 0

        /// Set by `testOverlappingLoadsCoalesceIntoOneInFlightTask` to park the
        /// first `listWorkspaces()` call open (consumed once) so a second,
        /// overlapping `load()` call is guaranteed to start while the first is
        /// still in flight, instead of racing on scheduling order.
        var listGate: (() async -> Void)?

        func listWorkspaces() async throws -> [HubWorkspace] {
            listCalls += 1
            if let gate = listGate {
                listGate = nil
                await gate()
            }
            if let listError { throw listError }
            return workspaces
        }

        func preferredSlug() async throws -> String? {
            if let prefError { throw prefError }
            return preferred
        }

        func setPreferredSlug(_ slug: String) async throws {
            if let setError { throw setError }
            persisted.append(slug)
        }
    }

    private var isolated: IsolatedDefaults!
    private var fake: FakeWorkspaces!
    private var controller: WorkspaceController!

    // The synchronous `XCTestCase.setUp()`/`tearDown()` override points are
    // nonisolated (they come from XCTest's Objective-C `XCTestCase`, not a
    // `@MainActor`-annotated Swift declaration), even though this class is
    // `@MainActor`. The `async throws` override points are `@MainActor`, so
    // using them lets setUp/tearDown touch `isolated` directly with real,
    // checked isolation instead of an unchecked escape hatch.
    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
        fake = FakeWorkspaces()
        fake.workspaces = [ada, acme, core]
        controller = WorkspaceController(provider: fake, defaults: isolated.defaults)
    }

    override func tearDown() async throws {
        isolated.tearDown()
        try await super.tearDown()
    }

    func testLoadResolvesFromTheServerPreferenceAndRecordsARecent() async {
        fake.preferred = "acme"
        var observed: [WorkspaceState] = []
        controller.onChange = { observed.append($0) }
        await controller.load()
        XCTAssertEqual(controller.state, .loaded(acme))
        XCTAssertEqual(controller.current, acme)
        XCTAssertEqual(controller.workspaces, [ada, acme, core])
        XCTAssertEqual(observed, [.loading, .loaded(acme)])
        XCTAssertEqual(controller.recents, ["acme"])
        XCTAssertEqual(isolated.defaults.stringArray(forKey: "hub.recents"), ["acme"])
        XCTAssertEqual(fake.persisted, [])   // implicit resolution never persists
    }

    func testUnknownRequestedSlugIsNotMember() async {
        await controller.load(requestedSlug: "ghost")
        XCTAssertEqual(controller.state, .notMember("ghost"))
        XCTAssertNil(controller.current)
        XCTAssertEqual(controller.workspaces.count, 3)   // the list is kept so the picker still works
    }

    func testSelectPersistsOnlyNonTeamPicks() async {
        await controller.load()
        await controller.select(slug: "acme")
        XCTAssertEqual(controller.state, .loaded(acme))
        XCTAssertEqual(fake.persisted, ["acme"])
        await controller.select(slug: "acme-core")
        XCTAssertEqual(controller.state, .loaded(core))
        XCTAssertEqual(fake.persisted, ["acme"])
        XCTAssertEqual(controller.recents, ["acme-core", "acme", "ada"])
    }

    func testSelectUnknownSlugIsNotMemberAndPersistFailureIsIgnored() async {
        await controller.load()
        await controller.select(slug: "ghost")
        XCTAssertEqual(controller.state, .notMember("ghost"))
        fake.setError = HubError.transport("down")
        await controller.select(slug: "ada")
        XCTAssertEqual(controller.state, .loaded(ada))
    }

    func testListFailureIsFailedAndRetryRecovers() async {
        fake.listError = HubError.transport("HTTP 503")
        await controller.load(requestedSlug: "acme")
        XCTAssertEqual(controller.state, .failed(HubError.transport("HTTP 503").message))
        fake.listError = nil
        await controller.retry()
        XCTAssertEqual(controller.state, .loaded(acme))
        XCTAssertEqual(fake.listCalls, 2)
    }

    func testPreferenceFailureIsIgnoredAndEmptyListFails() async {
        fake.prefError = HubError.transport("down")
        await controller.load()
        XCTAssertEqual(controller.state, .loaded(ada))
        fake.workspaces = []
        fake.prefError = nil
        await controller.load()
        XCTAssertEqual(controller.state, .failed("No workspaces are available for this account."))
    }

    func testRecentsAreCappedAndDeduplicated() async {
        fake.workspaces = (1...7).map { HubWorkspace(slug: "w\($0)", name: "W\($0)", type: .organization) }
        await controller.load()
        for slug in ["w2", "w3", "w4", "w5", "w6", "w2"] {
            await controller.select(slug: slug)
        }
        XCTAssertEqual(controller.recents, ["w2", "w6", "w5", "w4", "w3"])
        controller.reset()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(controller.workspaces, [])
    }

    /// A second `load()` that starts while the first is still awaiting
    /// `listWorkspaces()` must share the in-flight call rather than issuing
    /// its own: without `WorkspaceController`'s in-flight guard this fails,
    /// because the first call's slower resolve would land its (by-then
    /// stale) `requestedSlug` resolution over the second call's, and the
    /// provider would be asked twice instead of once.
    func testOverlappingLoadsCoalesceIntoOneInFlightTask() async {
        fake.workspaces = [ada]
        fake.preferred = "ada"

        var releaseFirstCall: (() -> Void)?
        fake.listGate = {
            await withCheckedContinuation { continuation in
                releaseFirstCall = { continuation.resume() }
            }
        }

        let firstLoad = Task { await self.controller.load(requestedSlug: "ada") }
        while releaseFirstCall == nil {
            await Task.yield()
        }

        // The backing data changes while the first call is still parked.
        fake.workspaces = [acme, core]
        fake.preferred = "acme-core"

        let secondLoad = Task { await self.controller.load(requestedSlug: "acme-core") }
        await Task.yield()

        releaseFirstCall?()
        _ = await (firstLoad.value, secondLoad.value)

        XCTAssertEqual(fake.listCalls, 1)
        if let current = controller.current {
            XCTAssertTrue(controller.workspaces.contains(current))
        }
    }
}
