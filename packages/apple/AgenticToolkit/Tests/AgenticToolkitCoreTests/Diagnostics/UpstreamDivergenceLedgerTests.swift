//
//  UpstreamDivergenceLedgerTests.swift
//  AgenticToolkitCoreTests
//

import Combine
import Foundation
import Testing

@testable import AgenticToolkitCore

/// The ledger that records where this app knowingly does less than VS Code.
///
/// Every test here uses its own instance rather than `.shared`, and that is the
/// point of `shared` being a `let` on a class with a public initialiser: a
/// process-wide default is what lets a call site deep inside a decode loop
/// record without being handed a dependency, and a fresh instance is what keeps
/// one test's hits out of another's.
@Suite("UpstreamDivergenceLedger")
struct UpstreamDivergenceLedgerTests {

    private var overlap: UpstreamDivergence { .semanticTokenOverlapDropped }
    private var unmapped: UpstreamDivergence { .semanticTokenTypeUnmapped }

    @Test("A first record starts a row at the count it was given")
    func firstRecordStartsARow() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "file:///a.swift", count: 3)

        let hits = ledger.hits
        #expect(hits.count == 1)
        #expect(hits[0].divergence == overlap)
        #expect(hits[0].detail == "file:///a.swift")
        #expect(hits[0].count == 3)
    }

    @Test("A second record for the same site and detail adds to the row it already has")
    func secondRecordAccumulates() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "file:///a.swift", count: 2)
        ledger.record(overlap, detail: "file:///a.swift")

        #expect(ledger.hits.count == 1)
        #expect(ledger.hits[0].count == 3)
    }

    /// The detail is part of the identity, not a label on it. "Two documents
    /// each lost tokens once" and "one document lost tokens twice" are
    /// different diagnoses, and a ledger that collapsed them would hide which
    /// server was misbehaving.
    @Test("Two details under one site are two rows")
    func detailsAreSeparateRows() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "file:///a.swift")
        ledger.record(overlap, detail: "file:///b.swift")

        #expect(ledger.hits.count == 2)
        #expect(ledger.hits(for: overlap).count == 2)
        #expect(Set(ledger.hits.map(\.detail)) == ["file:///a.swift", "file:///b.swift"])
    }

    /// `firstSeen` answers "did this start happening at some point", which a
    /// stamp that moved on every hit could never answer. `lastSeen` answers
    /// "is it still happening". Both, because the pair is what makes a row
    /// readable a week later.
    @Test("firstSeen is set once and lastSeen moves")
    func firstSeenIsPinnedAndLastSeenMoves() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "x")
        let first = ledger.hits[0]

        ledger.record(overlap, detail: "x")
        let second = ledger.hits[0]

        #expect(second.firstSeen == first.firstSeen)
        #expect(second.lastSeen >= first.lastSeen)
    }

    @Test("Rows are ordered by site and then detail, not by arrival")
    func rowsAreSortedForReading() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(unmapped, detail: "z")
        ledger.record(overlap, detail: "b")
        ledger.record(overlap, detail: "a")

        let ordered = ledger.hits.map { "\($0.divergence.id)/\($0.detail)" }
        #expect(ordered == ordered.sorted())
    }

    @Test("hits(for:) answers only that site")
    func hitsForOneSite() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "a")
        ledger.record(unmapped, detail: "a")

        #expect(ledger.hits(for: unmapped).map(\.divergence) == [unmapped])
    }

    @Test("A recorded hit is published, and the current value is readable on subscribe")
    func publisherCarriesTheRows() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "a")

        var delivered: [[UpstreamDivergenceHit]] = []
        let cancellable = ledger.hitsPublisher.sink { delivered.append($0) }
        defer { cancellable.cancel() }

        // The subscriber is handed what the ledger already holds — a panel
        // opened after the damage was done must still show it.
        #expect(delivered.count == 1)
        #expect(delivered[0].count == 1)

        ledger.record(unmapped, detail: "b")
        #expect(delivered.count == 2)
        #expect(delivered[1].count == 2)
    }

    @Test("clear() empties the ledger and says so to subscribers")
    func clearEmptiesAndPublishes() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "a")

        var delivered: [[UpstreamDivergenceHit]] = []
        let cancellable = ledger.hitsPublisher.sink { delivered.append($0) }
        defer { cancellable.cancel() }

        ledger.clear()
        #expect(ledger.hits.isEmpty)
        #expect(delivered.last?.isEmpty == true)
    }

    /// A count of zero or less is a caller bug — a loop that recorded its
    /// counter without checking it ran. Recording it would put a row in the
    /// report saying a divergence happened zero times, which is worse than
    /// silence because it reads as a finding.
    @Test("A non-positive count records nothing")
    func nonPositiveCountsAreIgnored() {
        let ledger = UpstreamDivergenceLedger()
        ledger.record(overlap, detail: "a", count: 0)
        ledger.record(overlap, detail: "a", count: -4)

        #expect(ledger.hits.isEmpty)
    }

    @Test("Recording from many threads at once loses nothing")
    func concurrentRecordingIsTotalled() async {
        let ledger = UpstreamDivergenceLedger()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 {
                group.addTask { ledger.record(.semanticTokenOverlapDropped, detail: "shared") }
            }
        }

        #expect(ledger.hits.count == 1)
        #expect(ledger.hits[0].count == 200)
    }
}

/// The catalogue itself, which is documentation the compiler can check.
@Suite("UpstreamDivergence catalogue")
struct UpstreamDivergenceCatalogueTests {

    @Test("Every known divergence has a unique id")
    func idsAreUnique() {
        let ids = UpstreamDivergence.known.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// A row in a report that does not say what VS Code does instead is not
    /// telling anyone anything. Each of these is prose a person reads, so the
    /// only check worth making is that it is there at all.
    @Test("Every known divergence says what upstream does, what we do, and why")
    func everyEntryIsDescribed() {
        for divergence in UpstreamDivergence.known {
            #expect(!divergence.id.isEmpty)
            #expect(!divergence.area.isEmpty)
            #expect(!divergence.upstreamBehaviour.isEmpty)
            #expect(!divergence.ourBehaviour.isEmpty)
            #expect(!divergence.rationale.isEmpty)
        }
    }

    /// The distinction the whole catalogue turns on: a `.counted` entry has a
    /// call site that can fire, so a zero means it did not happen; a
    /// `.declared` entry has none, so a zero means nothing at all. A report
    /// that showed both as "0" without saying which kind it was would invite
    /// exactly the wrong conclusion.
    @Test("At least one entry of each detection kind, and counted ones are the majority")
    func bothDetectionKindsArePresent() {
        let counted = UpstreamDivergence.known.filter { $0.detection == .counted }
        let declared = UpstreamDivergence.known.filter { $0.detection == .declared }

        #expect(!counted.isEmpty)
        #expect(!declared.isEmpty)
        #expect(counted.count >= declared.count)
    }
}
