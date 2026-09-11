//
//  ContributionRegistrationsTests.swift
//  AgenticToolkit
//

import Testing
@testable import AgenticToolkitCore

/// The bookkeeping `ViewsContributionPoint` and `ConfigurationContributionPoint`
/// used to keep a copy of each: one payload per applied extension in
/// application order, notes alongside it, and a withdrawal that takes both.
///
/// Pinned here, in `apple-core`, because that is where the one implementation
/// now lives — and because every rule below is one a point was previously
/// free to get right in one file and wrong in the next.
///
/// `ContributedViewNote` is the note type rather than a stand-in written for
/// the test: it is a real conformer, so this suite pins the conformance too.
@Suite("ContributionRegistrations")
struct ContributionRegistrationsTests {

    private func note(_ identifier: String, _ viewID: String) -> ContributedViewNote {
        ContributedViewNote(
            extensionIdentifier: identifier,
            viewID: viewID,
            kind: .whenNotEvaluated,
            detail: "recorded by a test")
    }

    @Test("Payloads and notes come back in the order they were applied")
    func applicationOrderIsReported() {
        var registrations = ContributionRegistrations<Int, ContributedViewNote>()
        registrations.record(1, notes: [note("a", "a.one")], for: "a")
        registrations.record(2, notes: [note("b", "b.one")], for: "b")
        registrations.record(3, notes: [], for: "c")

        #expect(registrations.identifiers == ["a", "b", "c"])
        #expect(registrations.payload(for: "b") == 2)
        #expect(registrations.notes.map(\.viewID) == ["a.one", "b.one"])
    }

    @Test("An unrecorded identifier has no payload, and removing it changes nothing")
    func anUnknownIdentifierIsInert() {
        var registrations = ContributionRegistrations<Int, ContributedViewNote>()
        registrations.record(1, notes: [note("a", "a.one")], for: "a")

        #expect(registrations.payload(for: "absent") == nil)
        registrations.remove("absent")
        #expect(registrations.identifiers == ["a"])
        #expect(registrations.notes.count == 1)
    }

    @Test("Recording the same extension twice leaves one payload and one set of notes")
    func recordingTwiceReplaces() {
        var registrations = ContributionRegistrations<Int, ContributedViewNote>()
        registrations.record(1, notes: [note("a", "a.one")], for: "a")
        registrations.record(2, notes: [note("b", "b.one")], for: "b")
        registrations.record(10, notes: [note("a", "a.two")], for: "a")

        // One entry, the newest payload, and the newest notes — not two of
        // either. A reload and a disable/enable both come through here.
        #expect(registrations.identifiers == ["b", "a"])
        #expect(registrations.payload(for: "a") == 10)
        #expect(registrations.notes.map(\.viewID) == ["b.one", "a.two"])
    }

    @Test("Removing one extension leaves the others and their notes alone")
    func removalIsPerExtension() {
        var registrations = ContributionRegistrations<Int, ContributedViewNote>()
        registrations.record(1, notes: [note("a", "a.one"), note("a", "a.two")], for: "a")
        registrations.record(2, notes: [note("b", "b.one")], for: "b")

        registrations.remove("a")

        #expect(registrations.identifiers == ["b"])
        #expect(registrations.payload(for: "a") == nil)
        #expect(registrations.notes.map(\.viewID) == ["b.one"])
    }

    @Test("The filtered identifiers keep application order")
    func filteringKeepsOrder() {
        var registrations = ContributionRegistrations<Int, ContributedViewNote>()
        for (index, identifier) in ["a", "b", "c", "d"].enumerated() {
            registrations.record(index, notes: [], for: identifier)
        }

        #expect(registrations.identifiers(where: { $0.isMultiple(of: 2) }) == ["a", "c"])
    }
}
