import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Billables through the Projects window and the in-memory daemon: loading,
/// adding by hand, editing, moving through statuses, and deleting.
@MainActor
final class ProjectBillablesControllerTests: XCTestCase {

    private var fake: FakeBillingClient!
    private var model: BillingModel!
    private var confirmAnswer = true
    private var confirmations: [(String, String)] = []
    private var failures: [String] = []

    override func setUp() async throws {
        fake = FakeBillingClient.seeded()
        fake.clients = [BillingClientDTO(id: "c1", name: "Acme", currency: "EUR")]
        fake.projects = [BillingProjectDTO(id: "p1", clientId: "c1", name: "Website",
                                           defaultRateCents: 12_000, roundingMinutes: 30)]
        fake.entries = [
            BillingEntryDTO(id: "e1", projectId: "p1", clientId: "c1", day: "2026-09-21",
                            rawSeconds: 3500, billedSeconds: 3600, rateCents: 12_000, currency: "EUR",
                            amountCents: 12_000),
            BillingEntryDTO(id: "e2", projectId: "p1", clientId: "c1", day: "2026-09-20",
                            rawSeconds: 1800, billedSeconds: 1800, rateCents: 12_000, currency: "EUR",
                            amountCents: 6_000, status: "billed", locked: true)
        ]
        model = BillingModel(service: fake, refreshInterval: 999)
        await model.refresh()
        confirmAnswer = true
        confirmations = []
        failures = []
    }

    private func makeController() -> ProjectsWindowController {
        let controller = ProjectsWindowController(
            context: .forTests(model: model),
            confirm: { [unowned self] question, detail, answer in
                confirmations.append((question, detail))
                answer(confirmAnswer)
            },
            reportFailure: { [unowned self] message in failures.append(message) },
            chooseFolder: { _, answer in answer(nil) },
            resolveRoot: { _ in .notAGitWorkingTree },
            addClient: { nil }
        )
        _ = controller.windowController.window
        return controller
    }

    private func open(_ controller: ProjectsWindowController) async throws -> ProjectBillablesSection {
        controller.windowController.selectRecord(id: "p1")
        let panel = try XCTUnwrap(controller.panel(for: "p1"))
        _ = panel.view
        await controller.settleDetails()
        return panel.billables
    }

    private func select(_ id: String, in section: ProjectBillablesSection) {
        let row = section.billablesCard.rows.firstIndex { $0.id == id }!
        section.billablesCard.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func settle(_ controller: ProjectsWindowController) async {
        await controller.lastWrite?.value
        await controller.settleDetails()
        await controller.lastAuditLoad?.value
    }

    func testSelectingAProjectLoadsItsBillables() async throws {
        let section = try await open(makeController())
        XCTAssertEqual(section.billablesCard.rows.map(\.id), ["e1", "e2"])
    }

    func testAHandMadeBillableUsesTheProjectsTerms() async throws {
        let controller = makeController()
        let section = try await open(controller)

        let maybeAdded = await controller.addBillable(to: model.project(id: "p1")!)
        let added = try XCTUnwrap(maybeAdded)

        XCTAssertEqual(added.billedSeconds, 1800, "one rounding increment")
        XCTAssertEqual(added.rawSeconds, 0, "nothing was tracked")
        XCTAssertEqual(added.rateCents, 12_000)
        XCTAssertEqual(added.amountCents, 6_000)
        XCTAssertEqual(added.currency, "EUR", "the client's currency")
        XCTAssertEqual(added.clientId, "c1")
        XCTAssertTrue(added.groupKey.hasPrefix("manual-"), "never the derived day's group")
        XCTAssertEqual(added.day, UTCTimestamp.day(of: Date(), in: .current))
        XCTAssertEqual(section.selectedEntry?.id, added.id, "the new row is selected, ready to edit")
    }

    func testTwoHandMadeBillablesOnOneDayDoNotCollide() async throws {
        let controller = makeController()
        _ = try await open(controller)
        let project = model.project(id: "p1")!
        let first = await controller.addBillable(to: project)
        let second = await controller.addBillable(to: project)
        XCTAssertNotEqual(first?.groupKey, second?.groupKey)
    }

    func testAnEditIsSavedThroughTheModel() async throws {
        let controller = makeController()
        let section = try await open(controller)

        let row = section.billablesCard.rows.firstIndex { $0.id == "e1" }!
        section.billablesCard.commitEdit(rowIndex: row, columnID: "hours", newValue: "2")
        await settle(controller)

        XCTAssertEqual(fake.entries.first { $0.id == "e1" }?.billedSeconds, 7200)
        XCTAssertEqual(fake.entries.first { $0.id == "e1" }?.amountCents, 24_000)
    }

    func testMarkingBilledWritesAndShowsTheHistory() async throws {
        let controller = makeController()
        let section = try await open(controller)
        select("e1", in: section)

        section.markBilledButton.performClick(nil)
        await settle(controller)

        XCTAssertEqual(fake.entries.first { $0.id == "e1" }?.status, "billed")
        XCTAssertEqual(section.auditCard.rows.count, 1, "the status change is in the history")
        XCTAssertFalse(section.markBilledButton.isEnabled, "already billed")
    }

    func testRemovingAsksFirst() async throws {
        let controller = makeController()
        let section = try await open(controller)
        select("e1", in: section)

        confirmAnswer = false
        section.billablesCard.removeButton.performClick(nil)
        await settle(controller)
        XCTAssertEqual(confirmations.first?.0, "Delete the billable for 2026-09-21?")
        XCTAssertTrue(confirmations.first?.1.contains("billed again") ?? false, "tracked time comes back")
        XCTAssertNotNil(fake.entries.first { $0.id == "e1" })

        confirmAnswer = true
        section.billablesCard.removeButton.performClick(nil)
        await settle(controller)
        XCTAssertNil(fake.entries.first { $0.id == "e1" })
    }

    func testAFailedWriteIsReported() async throws {
        let controller = makeController()
        let section = try await open(controller)
        fake.reachable = false

        let row = section.billablesCard.rows.firstIndex { $0.id == "e1" }!
        section.billablesCard.commitEdit(rowIndex: row, columnID: "description", newValue: "Launch")
        await settle(controller)

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].hasPrefix("The billable couldn't be saved."), failures[0])
    }

    /// Today's auto billable grows every pass. A description typed into a
    /// window showing a minute-old copy must send the words alone — sending
    /// the row would write the stale figures back and freeze them.
    func testADescriptionEditSendsOnlyTheWords() async throws {
        let controller = makeController()
        let section = try await open(controller)
        let before = fake.entries.count
        // The daemon's entry has grown since the window loaded it.
        let grown = BillingEntryDTO(id: "e1", projectId: "p1", clientId: "c1", day: "2026-09-21",
                                    rawSeconds: 5400, billedSeconds: 5400, rateCents: 12_000,
                                    currency: "EUR", amountCents: 18_000)
        fake.entries[fake.entries.firstIndex { $0.id == "e1" }!] = grown

        let row = section.billablesCard.rows.firstIndex { $0.id == "e1" }!
        section.billablesCard.commitEdit(rowIndex: row, columnID: "description", newValue: " Launch ")
        await settle(controller)

        XCTAssertEqual(fake.descriptionSaves.map(\.id), ["e1"])
        XCTAssertEqual(fake.descriptionSaves.map(\.description), ["Launch"])
        let stored = try XCTUnwrap(fake.entries.first { $0.id == "e1" })
        XCTAssertEqual(stored.billedSeconds, 5400, "the grown figures are not overwritten")
        XCTAssertEqual(stored.description, "Launch")
        XCTAssertEqual(fake.entries.count, before)
        XCTAssertTrue(failures.isEmpty)
    }
}
