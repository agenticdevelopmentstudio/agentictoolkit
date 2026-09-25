import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Clients window against the in-memory daemon: the list follows the
/// model, `+`/`−` create and delete, and every field edit becomes a save.
@MainActor
final class ClientsWindowControllerTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!
    private var confirmAnswer = true
    private var confirmations: [String] = []
    private var failures: [String] = []

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        confirmAnswer = true
        confirmations = []
        failures = []
    }

    private func makeController() -> ClientsWindowController {
        let controller = ClientsWindowController(
            context: .forTests(model: model),
            confirm: { [unowned self] question, _, answer in
                confirmations.append(question)
                answer(confirmAnswer)
            },
            reportFailure: { [unowned self] message in failures.append(message) }
        )
        // Loading the window is what builds the split the panels live in.
        _ = controller.windowController.window
        return controller
    }

    private func titles(_ controller: ClientsWindowController) -> [String] {
        controller.windowController.viewController?.panels.map(\.descriptor.title) ?? []
    }

    private func loadedPanel(_ controller: ClientsWindowController, _ id: String) throws -> ClientDetailPanel {
        let panel = try XCTUnwrap(controller.panel(for: id))
        _ = panel.view
        return panel
    }

    /// What pressing Return in the field does.
    private func type(_ text: String, into field: ComposableSettings.TextEditView) {
        field.textField.stringValue = text
        field.textField.sendAction(field.textField.action, to: field.textField.target)
    }

    // MARK: - The list

    func testClientsAreListedByNameWithArchivedLast() async {
        fake.clients += [
            BillingClientDTO(id: "c2", name: "bolt"),
            BillingClientDTO(id: "c3", name: "Aardvark", archived: true)
        ]
        await model.refresh()

        let controller = makeController()

        XCTAssertEqual(titles(controller), ["Acme", "bolt", "Aardvark"],
                       "case-insensitive by name; an archived client sinks rather than vanishing")
    }

    func testTheListFollowsTheModel() async {
        let controller = makeController()

        fake.clients.append(BillingClientDTO(id: "c2", name: "Bolt"))
        await model.refresh()

        XCTAssertEqual(titles(controller), ["Acme", "Bolt"])
    }

    // MARK: - Add

    func testAddCreatesAndSelectsANewClient() async {
        let controller = makeController()

        controller.windowController.footer.addButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.clients.map(\.name), ["Acme", ClientsWindowController.newClientName])
        XCTAssertEqual(fake.clients.last?.currency, BillingUserSettings.forTests.currency.value,
                       "a new client starts in the currency Settings names")
        XCTAssertEqual(controller.windowController.selectedRecord?.name, ClientsWindowController.newClientName)
    }

    func testASecondNewClientGetsADistinctName() async {
        let controller = makeController()

        await controller.addClient()
        await controller.addClient()

        XCTAssertEqual(fake.clients.map(\.name), ["Acme", "New Client", "New Client 2"])
    }

    func testAFailedAddIsReported() async {
        let controller = makeController()
        fake.reachable = false

        let added = await controller.addClient()

        XCTAssertNil(added)
        XCTAssertEqual(failures.count, 1)
    }

    // MARK: - Remove

    func testRemovingAsksAndCancelKeepsTheClient() async {
        confirmAnswer = false
        let controller = makeController()
        controller.windowController.selectRecord(id: "c1")

        controller.windowController.footer.removeButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertEqual(confirmations, ["Delete “Acme”?"])
        XCTAssertEqual(fake.clients.map(\.id), ["c1"])
    }

    func testRemovingAClientKeepsItsProjects() async {
        let controller = makeController()
        controller.windowController.selectRecord(id: "c1")

        controller.windowController.footer.removeButton.performClick(nil)
        await controller.lastWrite?.value

        XCTAssertTrue(fake.clients.isEmpty)
        XCTAssertNotNil(fake.projects.first { $0.id == "p1" }, "the project survives its client")
        XCTAssertNil(fake.projects.first { $0.id == "p1" }?.clientId, "and becomes your own work")
        XCTAssertEqual(titles(controller), [])
    }

    // MARK: - Editing

    func testEditingTheNameSavesAndRenamesTheRow() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        type("Acme Corp", into: panel.nameField)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.clients.first?.name, "Acme Corp")
        XCTAssertEqual(titles(controller), ["Acme Corp"])
    }

    func testABlankNameIsRefusedAndTheOldNameComesBack() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        type("   ", into: panel.nameField)
        await drainMainQueue()

        XCTAssertNil(controller.lastWrite, "nothing was sent")
        XCTAssertEqual(fake.clients.first?.name, "Acme")
        XCTAssertEqual(panel.nameField.textField.stringValue, "Acme")
    }

    func testContactEditsSave() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        type("billing@acme.test", into: panel.contactFields.emailField)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.clients.first?.email, "billing@acme.test")
    }

    func testCurrencyIsUppercasedAndMustBeThreeLetters() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        type("eur", into: panel.currencyField)
        await controller.lastWrite?.value
        XCTAssertEqual(fake.clients.first?.currency, "EUR")

        type("euro", into: panel.currencyField)
        await controller.lastWrite?.value
        await drainMainQueue()
        XCTAssertEqual(fake.clients.first?.currency, "EUR", "four letters is not a currency code")
        XCTAssertEqual(panel.currencyField.textField.stringValue, "EUR")
    }

    func testArchivingSaves() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        let toggle = panel.archivedToggle.toggle
        toggle.state = .on
        toggle.sendAction(toggle.action, to: toggle.target)
        await controller.lastWrite?.value

        XCTAssertEqual(fake.clients.first?.archived, true)
    }

    func testNotesSaveWhenEditingEnds() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        panel.notesField.textView.string = "Net 30. PO required."
        panel.notesField.commit()
        await controller.lastWrite?.value

        XCTAssertEqual(fake.clients.first?.notes, "Net 30. PO required.")
    }

    func testAFailedSaveIsReportedAndTheStoredValueComesBack() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")
        fake.reachable = false

        type("Acme Corp", into: panel.nameField)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(panel.nameField.textField.stringValue, "Acme",
                       "a field must not keep a value the daemon never stored")
        XCTAssertEqual(titles(controller), ["Acme"])
    }

    func testAFailedSaveRevertsTheFieldBeingEdited() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")
        let field = panel.nameField.textField
        let window = hostWindow(panel.view)
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertNotNil(field.currentEditor(), "the field is being edited")
        fake.reachable = false

        field.stringValue = "Acme Corp"
        field.sendAction(field.action, to: field.target)
        await controller.lastWrite?.value

        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(field.stringValue, "Acme")
        XCTAssertNil(field.currentEditor(), "ending the edit later can't send the refused name again")
    }

    // MARK: - Updates from elsewhere

    func testAChangeFromElsewhereReachesTheOpenPanel() async throws {
        let controller = makeController()
        let panel = try loadedPanel(controller, "c1")

        fake.clients = [fake.clients[0].replacing(email: "new@acme.test")]
        await model.refresh()

        XCTAssertIdentical(controller.panel(for: "c1"), panel, "the pane is updated, not rebuilt")
        XCTAssertEqual(panel.contactFields.emailField.textField.stringValue, "new@acme.test")
    }
}
