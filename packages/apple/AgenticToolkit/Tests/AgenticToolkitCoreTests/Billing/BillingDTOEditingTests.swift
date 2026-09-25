import XCTest
@testable import AgenticToolkitCore

final class BillingDTOEditingTests: XCTestCase {

    func testReplacingChangesOnlyTheNamedFields() {
        let client = BillingClientDTO(id: "c1", name: "Acme", email: "a@acme.test", currency: "USD")
        let edited = client.replacing(name: "Acme Corp", phone: "555-0100")

        XCTAssertEqual(edited.id, "c1")
        XCTAssertEqual(edited.name, "Acme Corp")
        XCTAssertEqual(edited.phone, "555-0100")
        XCTAssertEqual(edited.email, "a@acme.test", "an unnamed field is carried over")
        XCTAssertEqual(edited.currency, "USD")
    }

    /// A double optional tells "leave it" (`nil`) apart from "clear it"
    /// (`.some(nil)`), which a plain optional parameter cannot.
    func testANullableFieldCanBeClearedOrLeftAlone() {
        let project = BillingProjectDTO(id: "p1", clientId: "c1", name: "Site", defaultRateCents: 12_500)

        XCTAssertEqual(project.replacing(name: "Site 2").clientId, "c1")
        XCTAssertNil(project.replacing(clientId: .some(nil)).clientId)
        XCTAssertNil(project.replacing(defaultRateCents: .some(nil)).defaultRateCents)
        XCTAssertEqual(project.replacing(defaultRateCents: 9_000).defaultRateCents, 9_000)
    }

    func testRepricingRecomputesTheAmount() {
        let entry = BillingEntryDTO(
            id: "e1", projectId: "p1", day: "2026-09-22",
            rawSeconds: 3000, billedSeconds: 3600, rateCents: 10_000, amountCents: 10_000
        )
        let repriced = entry.repriced(billedSeconds: 5400, rateCents: 12_000)

        XCTAssertEqual(repriced.billedSeconds, 5400)
        XCTAssertEqual(repriced.rateCents, 12_000)
        XCTAssertEqual(repriced.amountCents, 18_000)
        XCTAssertEqual(repriced.rawSeconds, 3000, "raw time is what was tracked; editing never rewrites it")
    }

    func testRecordTitleFallsBackForABlankName() {
        XCTAssertEqual(BillingRecordTitle.of("Acme"), "Acme")
        XCTAssertEqual(BillingRecordTitle.of("  "), "Untitled")
    }

    /// A new record never repeats a name, or two rows would read alike.
    func testAUniqueNameSkipsEveryTakenSuffix() {
        XCTAssertEqual(UniqueName.next(base: "New Client", taken: []), "New Client")
        XCTAssertEqual(UniqueName.next(base: "New Client", taken: ["New Client"]), "New Client 2")
        XCTAssertEqual(
            UniqueName.next(base: "misc", taken: ["misc", "misc 2", "misc 3", "other"]), "misc 4")
    }

    /// Two projects that share a name are told apart by client, then by id.
    func testProjectLabelsDistinguishNamesakes() {
        let clients = [BillingClientDTO(id: "c1", name: "Acme"), BillingClientDTO(id: "c2", name: "Beta")]
        let projects = [
            BillingProjectDTO(id: "p1aaaaaa", clientId: "c1", name: "Site"),
            BillingProjectDTO(id: "p2bbbbbb", clientId: "c2", name: "Site"),
            BillingProjectDTO(id: "p3cccccc", clientId: "c2", name: "Site"),
            BillingProjectDTO(id: "p4", name: "Other")
        ]
        let labels = BillingRecordTitle.projectLabels(projects, clients: clients)
        XCTAssertEqual(labels["p1aaaaaa"], "Site — Acme")
        XCTAssertEqual(labels["p2bbbbbb"], "Site — Beta — p2bbbb")
        XCTAssertEqual(labels["p3cccccc"], "Site — Beta — p3cccc")
        XCTAssertEqual(labels["p4"], "Other")
    }
}
