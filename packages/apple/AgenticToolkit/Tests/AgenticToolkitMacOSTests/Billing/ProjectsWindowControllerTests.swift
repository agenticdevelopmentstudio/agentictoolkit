import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Projects window against the in-memory daemon: the project card saves
/// every edit, the client popup follows the client list, and repositories are
/// recorded as the root the daemon groups sessions under.
@MainActor
final class ProjectsWindowControllerTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!
    private var confirmAnswer = true
    private var confirmations: [String] = []
    private var failures: [String] = []
    private var chosenFolder: URL?

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        confirmAnswer = true
        confirmations = []
        failures = []
        chosenFolder = nil
    }

    private func makeController(
        addClient: (@MainActor () async -> BillingClientDTO?)? = nil
    ) -> ProjectsWindowController {
        let model = self.model!
        let controller = ProjectsWindowController(
            context: .forTests(model: model),
            confirm: { [unowned self] question, _, answer in
                confirmations.append(question)
                answer(confirmAnswer)
            },
            reportFailure: { [unowned self] message in failures.append(message) },
            chooseFolder: { [unowned self] _, answer in answer(chosenFolder) },
            // Anything under /src/site is that repository; /tmp is not a repository.
            resolveRoot: { path in
                path.hasPrefix("/src/site") ? .resolved("/src/site") : .notAGitWorkingTree
            },
            addClient: addClient ?? { await model.saveClient(BillingClientDTO(id: "", name: "Fresh Co")) }
        )
        _ = controller.windowController.window
        return controller
    }

    private func titles(_ controller: ProjectsWindowController) -> [String] {
        controller.windowController.viewController?.panels.map(\.descriptor.title) ?? []
    }

    /// Selects the project, loads its pane and waits for its repositories.
    private func open(_ controller: ProjectsWindowController, _ id: String) async throws -> ProjectDetailPanel {
        controller.windowController.selectRecord(id: id)
        let panel = try XCTUnwrap(controller.panel(for: id))
        _ = panel.view
        await controller.settleDetails()
        return panel
    }

    private func type(_ text: String, into field: ComposableSettings.MoneyFieldView) {
        field.textField.stringValue = text
        field.textField.sendAction(field.textField.action, to: field.textField.target)
    }

    private func type(_ text: String, into field: ComposableSettings.TextEditView) {
        field.textField.stringValue = text
        field.textField.sendAction(field.textField.action, to: field.textField.target)
    }

    private func choose(_ title: String, in popup: ComposableSettings.PopupMenuChoiceView<String>) {
        popup.popUpButton.selectItem(withTitle: title)
        popup.popUpButton.sendAction(popup.popUpButton.action, to: popup.popUpButton.target)
    }

    /// `EditableTableCellValue` is not `Equatable`, and a test only cares what it reads as.
    private func show(_ value: ComposableSettings.EditableTableCellValue?) -> String {
        return shownCell(value)
    }

    // MARK: - The list

    func testProjectsAreListedByNameWithArchivedLast() async {
        fake.projects.append(BillingProjectDTO(id: "p3", name: "api"))
        await model.refresh()

        let controller = makeController()

        XCTAssertEqual(titles(controller), ["api", "Website", "Old thing", "Unassigned"])
    }

    func testAddCreatesAProjectWithTheSettingsRounding() async {
        let controller = makeController()

        controller.windowController.footer.addButton.performClick(nil)
        await controller.lastWrite?.value

        let added = fake.projects.last
        XCTAssertEqual(added?.name, ProjectsWindowController.newProjectName)
        XCTAssertNil(added?.clientId, "a new project is your own work until a client is chosen")
        XCTAssertEqual(added?.roundingMinutes, BillingUserSettings.forTests.roundingMinutes.value)
        XCTAssertEqual(added?.roundingMode, BillingUserSettings.forTests.roundingMode.value)
        XCTAssertEqual(controller.windowController.selectedRecord?.id, added?.id)
    }

    // MARK: - Remove

    func testRemovingAProjectWithNoBillablesAsksThenDeletes() async {
        let controller = makeController()
        controller.windowController.selectRecord(id: "p1")

        controller.windowController.footer.removeButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(confirmations, ["Delete “Website”?"])
        XCTAssertNil(fake.projects.first { $0.id == "p1" })
        XCTAssertNil(fake.segments.first { $0.id == "s-running" }?.projectId,
                     "its tracked time falls back to Unassigned rather than vanishing")
    }

    func testAProjectWithBillablesIsNotDeleted() async {
        fake.entries = [BillingEntryDTO(id: "e1", projectId: "p1", day: "2026-09-21", rawSeconds: 3600,
                                        billedSeconds: 3600, rateCents: 10_000, amountCents: 10_000,
                                        status: "billed", locked: true)]
        let controller = makeController()
        controller.windowController.selectRecord(id: "p1")

        controller.windowController.footer.removeButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertTrue(confirmations.isEmpty, "nothing to confirm: the answer is no")
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("Archive"), failures[0])
        XCTAssertNotNil(fake.projects.first { $0.id == "p1" })
    }

    // MARK: - The project card

    func testEditingTheNameSaves() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        type("Website Redesign", into: panel.nameField)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.projects.first { $0.id == "p1" }?.name, "Website Redesign")
        XCTAssertEqual(titles(controller), ["Website Redesign", "Old thing", "Unassigned"])
    }

    func testTheClientPopupOffersNoneTheActiveClientsAndAdd() async throws {
        fake.clients += [BillingClientDTO(id: "c2", name: "Bolt"),
                         BillingClientDTO(id: "c3", name: "Gone", archived: true)]
        await model.refresh()
        let controller = makeController()
        let panel = try await open(controller, "p1")

        XCTAssertEqual(panel.clientPopup.popUpButton.itemTitles,
                       ["None", "Acme", "Bolt", "", ProjectDetailPanel.addClientTitle],
                       "the command sits below a separator")
        XCTAssertEqual(panel.clientPopup.popUpButton.titleOfSelectedItem, "Acme")
    }

    func testChoosingAClientAndNoneSaves() async throws {
        fake.clients.append(BillingClientDTO(id: "c2", name: "Bolt"))
        await model.refresh()
        let controller = makeController()
        let panel = try await open(controller, "p1")

        choose("Bolt", in: panel.clientPopup)
        await controller.lastWrite?.value
        XCTAssertEqual(fake.projects.first { $0.id == "p1" }?.clientId, "c2")

        choose("None", in: panel.clientPopup)
        await controller.lastWrite?.value
        XCTAssertNil(fake.projects.first { $0.id == "p1" }?.clientId)
    }

    func testAddClientCreatesItAndAssignsIt() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        choose(ProjectDetailPanel.addClientTitle, in: panel.clientPopup)
        await controller.lastWrite?.value

        let fresh = try XCTUnwrap(fake.clients.first { $0.name == "Fresh Co" })
        XCTAssertEqual(fake.projects.first { $0.id == "p1" }?.clientId, fresh.id)
        XCTAssertEqual(panel.clientPopup.popUpButton.titleOfSelectedItem, "Fresh Co")
    }

    /// "Add Client…" waits on the Clients window. A change saved to the
    /// project meanwhile must survive the save that assigns the new client.
    func testAddClientKeepsAnEditSavedWhileItWaited() async throws {
        let model = self.model!
        let controller = makeController(addClient: {
            let project = try? XCTUnwrap(model.project(id: "p1"))
            if let project { _ = await model.saveProject(project.replacing(archived: true)) }
            return await model.saveClient(BillingClientDTO(id: "", name: "Fresh Co"))
        })
        let panel = try await open(controller, "p1")

        choose(ProjectDetailPanel.addClientTitle, in: panel.clientPopup)
        await controller.lastWrite?.value

        let stored = try XCTUnwrap(fake.projects.first { $0.id == "p1" })
        XCTAssertTrue(stored.archived, "the archive saved while Add Client waited was kept")
        XCTAssertEqual(stored.clientId, fake.clients.first { $0.name == "Fresh Co" }?.id)
    }

    /// A reload while a detail load is still in flight replaces it: the
    /// pane ends on what the newest load read.
    func testASecondDetailLoadReplacesTheFirst() async throws {
        let controller = makeController()
        controller.windowController.selectRecord(id: "p1")
        let panel = try XCTUnwrap(controller.panel(for: "p1"))
        _ = panel.view
        fake.entries.append(BillingEntryDTO(
            id: "e-late", projectId: "p1", day: "2026-09-23",
            rawSeconds: 3600, billedSeconds: 3600, rateCents: 10_000, amountCents: 10_000))

        await model.refresh()
        await controller.settleDetails()

        XCTAssertTrue(panel.billables.entries.contains { $0.id == "e-late" })
    }

    func testAnArchivedCurrentClientStaysVisible() async throws {
        fake.clients = [fake.clients[0].replacing(archived: true)]
        await model.refresh()
        let controller = makeController()
        let panel = try await open(controller, "p1")

        XCTAssertEqual(panel.clientPopup.popUpButton.titleOfSelectedItem, "Acme (Archived)",
                       "archiving a client must not make its projects look client-less")
    }

    func testTheDefaultRateParsesAndBlankFallsBackToSettings() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        type("$150.50", into: panel.rateField)
        await controller.lastWrite?.value
        XCTAssertEqual(fake.projects.first { $0.id == "p1" }?.defaultRateCents, 15_050)

        type("", into: panel.rateField)
        await controller.lastWrite?.value
        XCTAssertNil(fake.projects.first { $0.id == "p1" }?.defaultRateCents)
    }

    func testAnUnreadableRateIsRefused() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        type("lots", into: panel.rateField)
        await drainMainQueue()

        XCTAssertNil(controller.lastWrite, "nothing was sent")
        XCTAssertEqual(panel.rateField.textField.stringValue, "")
    }

    func testARateTheDaemonWouldRefuseIsNotSent() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        type("150000", into: panel.rateField)
        type("-5", into: panel.rateField)

        XCTAssertNil(controller.lastWrite, "nothing was sent")
    }

    /// What a blank rate bills at is the Settings default; changing it while
    /// the pane is open changes the hint too.
    func testTheBlankRateHintFollowsSettings() async throws {
        let saved = BillingUserSettings.forTests.defaultRateCents.value
        defer { BillingUserSettings.forTests.defaultRateCents.value = saved }
        BillingUserSettings.forTests.defaultRateCents.value = 15_000
        let controller = makeController()
        let panel = try await open(controller, "p1")
        let hint = { panel.rateField.textField.placeholderString ?? "" }
        XCTAssertTrue(hint().contains("150"), hint())

        BillingUserSettings.forTests.defaultRateCents.value = 17_500
        await drainMainQueue()

        XCTAssertTrue(hint().contains("175"), hint())
    }

    func testRoundingSaves() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        panel.roundingField.textField.stringValue = "6"
        panel.roundingField.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: panel.roundingField.textField))
        await controller.lastWrite?.value
        choose("Round to Nearest", in: panel.roundingModePopup)
        await controller.lastWrite?.value

        let saved = fake.projects.first { $0.id == "p1" }
        XCTAssertEqual(saved?.roundingMinutes, 6)
        XCTAssertEqual(saved?.roundingMode, "nearest")
    }

    func testBillingAndArchivedTogglesSave() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")

        for toggle in [panel.billingToggle.toggle, panel.archivedToggle.toggle] {
            toggle.state = toggle.state == .on ? .off : .on
            toggle.sendAction(toggle.action, to: toggle.target)
            await controller.lastWrite?.value
        }

        let saved = fake.projects.first { $0.id == "p1" }
        XCTAssertEqual(saved?.billingEnabled, false)
        XCTAssertEqual(saved?.archived, true)
    }

    // MARK: - Repositories

    func testTheSelectedProjectsRepositoriesAreListed() async throws {
        fake.repos = [
            BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site", branch: "main", rateCents: 20_000),
            BillingRepoDTO(id: "r2", projectId: "p1", projectRoot: "/src/site", billingEnabled: false),
            BillingRepoDTO(id: "r3", projectId: "p2", projectRoot: "/src/other")
        ]
        let controller = makeController()
        let panel = try await open(controller, "p1")

        let rows = panel.reposCard.rows
        XCTAssertEqual(rows.map(\.id), ["r2", "r1"], "by path, then any-branch before a named one")
        XCTAssertEqual(rows.map { show($0.cells["branch"]) }, ["(Any branch)", "main"])
        XCTAssertEqual(rows.map { show($0.cells["rate"]) }, ["(Project rate)", "200.00"])
        XCTAssertEqual(rows.map { show($0.cells["enabled"]) }, ["off", "on"])
    }

    func testAddingAFolderRecordsItsRepositoryRoot() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")
        chosenFolder = URL(fileURLWithPath: "/src/site/Sources/App")

        panel.reposCard.addButton.performClick(nil)
        await controller.lastWrite?.value
        await controller.settleDetails()

        XCTAssertEqual(fake.repos.map(\.projectRoot), ["/src/site"],
                       "the root sessions report, not the folder that was clicked")
        XCTAssertEqual(panel.reposCard.rows.count, 1)
    }

    func testAFolderOutsideARepositoryIsRefused() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")
        chosenFolder = URL(fileURLWithPath: "/tmp/notes")

        panel.reposCard.addButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertTrue(fake.repos.isEmpty)
        XCTAssertEqual(failures.count, 1)
    }

    func testEditingBranchRateAndSwitchSaves() async throws {
        fake.repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site")]
        let controller = makeController()
        let panel = try await open(controller, "p1")
        let card = panel.reposCard!

        card.commitEdit(rowIndex: 0, columnID: "branch", newValue: " feature/x ")
        await controller.lastWrite?.value
        card.commitEdit(rowIndex: 0, columnID: "rate", newValue: "175")
        await controller.lastWrite?.value
        card.onToggle?("r1", "enabled", false)
        await controller.lastWrite?.value

        let saved = fake.repos.first
        XCTAssertEqual(saved?.branch, "feature/x")
        XCTAssertEqual(saved?.rateCents, 17_500)
        XCTAssertEqual(saved?.billingEnabled, false)
    }

    func testAnUnreadableRepoRateIsPutBack() async throws {
        fake.repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site", rateCents: 9_000)]
        let controller = makeController()
        let panel = try await open(controller, "p1")

        panel.reposCard.commitEdit(rowIndex: 0, columnID: "rate", newValue: "abc")

        XCTAssertNil(controller.lastWrite)
        XCTAssertEqual(show(panel.reposCard.rows.first?.cells["rate"]), "90.00")
    }

    func testRemovingARepositoryDeletesItWithoutAsking() async throws {
        fake.repos = [BillingRepoDTO(id: "r1", projectId: "p1", projectRoot: "/src/site")]
        let controller = makeController()
        let panel = try await open(controller, "p1")

        panel.reposCard.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        panel.reposCard.removeButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertTrue(fake.repos.isEmpty)
        XCTAssertTrue(confirmations.isEmpty)
    }

    // MARK: - Failure

    func testAFailedSaveIsReportedAndTheStoredValueComesBack() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")
        fake.reachable = false

        type("Renamed", into: panel.nameField)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(panel.nameField.textField.stringValue, "Website")
    }

    /// The refused text is in the field being edited, which a refresh leaves
    /// alone; the failure path has to put the stored value back itself.
    func testAFailedSaveRevertsTheFieldBeingEdited() async throws {
        let controller = makeController()
        let panel = try await open(controller, "p1")
        let field = panel.nameField.textField
        let window = hostWindow(panel.view)
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertNotNil(field.currentEditor(), "the field is being edited")
        fake.reachable = false

        field.stringValue = "Renamed"
        field.sendAction(field.action, to: field.target)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(field.stringValue, "Website")
        XCTAssertNil(field.currentEditor(), "ending the edit later can't send the refused name again")
    }
}

/// Runs everything already queued on the main queue: a settings row
/// re-reads its value there after a set, and a closed window lets go there.
@MainActor
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// A window for a pane's view, so a field in it can hold a field editor.
@MainActor
func hostWindow(_ view: NSView) -> NSWindow {
    if let window = view.window { return window }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    return window
}
