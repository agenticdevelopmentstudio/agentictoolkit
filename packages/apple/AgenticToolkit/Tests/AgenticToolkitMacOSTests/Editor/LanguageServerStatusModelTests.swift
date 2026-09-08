//
//  LanguageServerStatusModelTests.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AppKit
import Combine
import Foundation
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// What the language servers settings panel can say about a running server.
///
/// The model is driven from a `CurrentValueSubject` of projects rather than
/// from `ProjectWindowManager`, which is the whole reason it takes a publisher:
/// none of this needs a window to be open, or a singleton to exist.
@Suite("Language server status model")
@MainActor
struct LanguageServerStatusModelTests {

    /// One project: its identity for the model, and the registry and fake
    /// session behind it.
    private struct ProjectFixture {
        let project: LanguageServerStatusModel.Project
        let editor: LSPEditorFixture

        var registry: LanguageServerRegistry { editor.registry }
        var configuration: LanguageServerConfiguration { editor.configuration }
    }

    /// A project whose registry holds exactly one session, parked at `.idle`.
    ///
    /// `holdsStart` throughout this suite. The registry starts a session it has
    /// just created in a `Task` of its own, so without the gate every session
    /// races to `.running` and a test about `.idle` or `.failed` would be
    /// asserting against whichever side of that race it lost. Held, the session
    /// sits still and the test drives every transition it wants to see.
    private func makeProject(named name: String, configurationID: UUID = UUID()) -> ProjectFixture {
        let editor = LSPEditorFixture(
            behavior: FakeEditorSessionBehavior(holdsStart: true),
            configurationID: configurationID
        )
        return ProjectFixture(
            project: LanguageServerStatusModel.Project(id: UUID(), name: name, registry: editor.registry),
            editor: editor
        )
    }

    /// The model's two inputs driven from one subject, for the tests that do
    /// not care about the difference between "projects with language services"
    /// and "open project windows". Every project in this suite has services, so
    /// the two counts agree; the test that separates them passes its own
    /// subject for the count.
    private func makeModel(
        _ projects: CurrentValueSubject<[LanguageServerStatusModel.Project], Never>
    ) -> LanguageServerStatusModel {
        LanguageServerStatusModel(projects: projects, openProjectCount: projects.map(\.count))
    }

    private func session(of fixture: ProjectFixture) throws -> FakeEditorLanguageServerSession {
        try #require(fixture.registry.session(forLanguageId: "swift") as? FakeEditorLanguageServerSession)
    }

    /// A transition reaches `rows` through the registry's per-session reader
    /// task and then a Combine sink, neither of which a test can await.
    private func poll(
        seconds: TimeInterval = 3,
        until condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - 1. The rows

    /// A language server is per project, so the unit the panel shows is not the
    /// configuration — it is the configuration *in* a project, and two open
    /// windows running the same server are two lines.
    @Test("the status rows are one per project per server the registry has a session for")
    func statusRowsListOneRowPerProjectPerRunningServer() async throws {
        let alpha = makeProject(named: "Alpha")
        let beta = makeProject(named: "Beta")
        try await session(of: alpha).transition(to: .running)
        try await session(of: beta).transition(to: .running)

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>(
            [alpha.project, beta.project])
        let model = makeModel(projects)

        #expect(await poll { model.rows.map(\.kind) == [.running, .running] })
        // Sorted by project name, which is what keeps the list still while a
        // handshake ticks underneath it.
        #expect(model.rows.map(\.projectName) == ["Alpha", "Beta"])
        #expect(model.rows.map(\.configurationName) == ["Fake", "Fake"])
        #expect(model.rows.map(\.configurationID) == [alpha.configuration.id, beta.configuration.id])
        #expect(model.hasOpenProject)
    }

    /// The reason the state carries a failure at all. "Failed" on its own sends
    /// the user to Console; the server's own stderr is normally where a wrong
    /// command path or a missing dependency says so in as many words.
    @Test("a failed row carries the reason and what the server wrote on its error output")
    func aFailedRowCarriesTheReasonAndTheServersStandardError() async throws {
        let alpha = makeProject(named: "Alpha")
        let failure = LanguageServerFailure(
            error: LanguageServerSessionError.serverExited(status: 127),
            // Deliberately padded: a row renders this directly, and a server's
            // last line of stderr almost always ends in a newline.
            standardErrorText: "  env: sourcekit-lsp: No such file or directory\n"
        )
        try await session(of: alpha).transition(to: .failed(failure))

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([alpha.project])
        let model = makeModel(projects)

        #expect(await poll { model.rows.first?.kind == .failed })
        let row = try #require(model.rows.first)
        #expect(row.failureReason == failure.error.localizedDescription)
        #expect(row.standardErrorText == "env: sourcekit-lsp: No such file or directory")
    }

    /// A configuration the registry has no session for contributes no row —
    /// and the model does not invent one, because inventing a row would mean
    /// inventing a state. The panel is what turns that absence into
    /// "Not running", so this asserts both halves: no row here, and a list view
    /// model that still lists the configuration with nothing under it.
    @Test("a configuration with no session has no row, and the list has no status to show for it")
    func aConfigurationWithNoSessionHasNoRowAndTheListSaysNotRunning() async throws {
        let alpha = makeProject(named: "Alpha")
        try await session(of: alpha).transition(to: .running)

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([alpha.project])
        let model = makeModel(projects)
        let list = LanguageServersListViewModel(store: alpha.editor.settings, statusModel: model)

        #expect(await poll { list.statusesByConfiguration[alpha.configuration.id]?.count == 1 })

        var disabled = alpha.configuration
        disabled.isEnabled = false
        alpha.editor.settings.set([disabled], for: UserSettings.languageServerConfigurations)

        #expect(await poll { model.rows.isEmpty })
        // Still listed — switched off is not removed — and now with no status
        // line of its own.
        #expect(list.configurations.map(\.id) == [alpha.configuration.id])
        #expect(list.statusesByConfiguration[alpha.configuration.id] == nil)
        // Not "no project open": a window is open, this server just is not
        // running in it. The two read differently in the panel.
        #expect(list.hasOpenProject)
    }

    // MARK: - 2. Projects opening and closing

    @Test("opening a project adds its rows")
    func openingAProjectAddsItsRows() async throws {
        let alpha = makeProject(named: "Alpha")
        let beta = makeProject(named: "Beta")
        try await session(of: alpha).transition(to: .running)
        try await session(of: beta).transition(to: .running)

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([])
        let model = makeModel(projects)

        #expect(model.rows.isEmpty)
        #expect(!model.hasOpenProject)

        projects.send([alpha.project])
        #expect(await poll { model.rows.map(\.projectName) == ["Alpha"] })
        #expect(model.hasOpenProject)

        projects.send([alpha.project, beta.project])
        #expect(await poll { model.rows.map(\.projectName) == ["Alpha", "Beta"] })
    }

    /// The rows are the visible half; the release is the half that is not.
    ///
    /// A settings window outlives every project window, so a model that kept
    /// what it was handed would keep every registry the user ever opened — and
    /// a registry owns language server processes. The weak reference is driven
    /// from a nested function so the fixture's own strong references are gone
    /// by the time the assertion runs, leaving the subject's current value and
    /// the model as the only candidates to be holding it.
    @Test("closing a project removes its rows and releases its registry")
    func closingAProjectRemovesItsRowsAndReleasesItsRegistry() async throws {
        let alpha = makeProject(named: "Alpha")
        try await session(of: alpha).transition(to: .running)

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([alpha.project])
        let model = makeModel(projects)
        #expect(await poll { model.rows.map(\.projectName) == ["Alpha"] })

        weak var closedRegistry: LanguageServerRegistry?

        func openBeta() async throws {
            let beta = makeProject(named: "Beta")
            try await session(of: beta).transition(to: .running)
            closedRegistry = beta.registry
            projects.send([alpha.project, beta.project])
            #expect(await poll { model.rows.map(\.projectName) == ["Alpha", "Beta"] })
        }
        try await openBeta()

        projects.send([alpha.project])

        #expect(await poll { model.rows.map(\.projectName) == ["Alpha"] })
        #expect(await poll { closedRegistry == nil })
    }

    // MARK: - 3. Ordering

    /// ★ N2, stated as a test.
    ///
    /// Two windows on `~/work/api` and `~/archive/api` share a project name,
    /// and one configuration open in both ties the configuration name and the
    /// configuration id as well. With every earlier key equal the comparator
    /// has nothing left to decide on, `sort` is not stable, and the rows are
    /// built by walking the projects in the order they were delivered — which
    /// in the host is a dictionary's order, not a list's. So the two rows swap
    /// on a recompute and the list reorders under the reader's cursor. The
    /// project id is unique by construction and makes the order total.
    ///
    /// Driven by re-delivering the same two projects in the opposite order,
    /// because that is the only thing about them a test can vary: everything
    /// the comparator looked at before this fix is identical between them.
    @Test("two projects with the same name running the same server hold a stable order")
    func rowsForTwoProjectsSharingANameAndAServerHoldTheirOrder() async throws {
        let shared = UUID()
        let first = makeProject(named: "api", configurationID: shared)
        let second = makeProject(named: "api", configurationID: shared)
        try await session(of: first).transition(to: .running)
        try await session(of: second).transition(to: .running)

        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>(
            [first.project, second.project])
        let model = makeModel(projects)

        #expect(await poll { model.rows.count == 2 })
        let expected = [first.project.id, second.project.id].sorted { $0.uuidString < $1.uuidString }
        #expect(model.rows.map(\.projectID) == expected)
        #expect(model.rows.map(\.configurationID) == [shared, shared])

        // Re-subscribes and recomputes synchronously: `@Published` hands a new
        // subscriber the current value, and `observe` recomputes unconditionally
        // afterwards. So there is nothing to wait for here — only an order to
        // check, against the same rows arriving the other way round.
        projects.send([second.project, first.project])
        #expect(model.rows.map(\.projectID) == expected)

        projects.send([first.project, second.project])
        #expect(model.rows.map(\.projectID) == expected)
    }

    /// ★ N3, stated as a test.
    ///
    /// "No project open" is a claim about project windows, and `projects`
    /// carries only the ones that have language services. A window whose
    /// services could not be built contributes nothing to that list, and the
    /// panel would have said there was no project open with the window on
    /// screen. The count is the input that cannot say that.
    @Test("an open project with no language services is still an open project")
    func anOpenProjectWithNoLanguageServicesStillCountsAsOpen() {
        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([])
        let openProjectCount = CurrentValueSubject<Int, Never>(0)
        let model = LanguageServerStatusModel(projects: projects, openProjectCount: openProjectCount)

        #expect(!model.hasOpenProject)

        openProjectCount.send(1)

        #expect(model.hasOpenProject)
        // Nothing to report about it — which is what "Not running" is for.
        #expect(model.rows.isEmpty)
    }

    // MARK: - 4. The panel

    @Test("the panel adds its sub-panel and carries the help topics that describe it")
    func thePanelAddsItsSubPanelAndItsHelpTopics() async throws {
        let alpha = makeProject(named: "Alpha")
        let projects = CurrentValueSubject<[LanguageServerStatusModel.Project], Never>([alpha.project])
        let panel = LanguageServersPanelViewController(
            store: alpha.editor.settings,
            projects: projects,
            openProjectCount: projects.map(\.count)
        )

        panel.loadViewIfNeeded()

        #expect(panel.panels.count == 1)
        #expect(panel.panels.first?.descriptor.title == "Servers")

        let help = try #require(panel.helpContent)
        #expect(help.topics.map(\.title) == [
            "Language Servers", "Command and Environment", "Root Markers", "Status"
        ])
        // The topic this task adds, and the one the panel would be lying
        // without: it is the only place the five states are named.
        let status = try #require(help.topics.first { $0.title == "Status" })
        for state in ["idle", "starting", "running", "stopped", "failed"] {
            #expect(status.body.contains(state))
        }
    }
}
