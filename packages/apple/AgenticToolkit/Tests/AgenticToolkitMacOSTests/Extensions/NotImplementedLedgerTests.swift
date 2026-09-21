import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// The record of what extensions asked this host for and did not get.
///
/// Everything here is a rule about *collapsing*: thousands of reaches become
/// one row, two kinds of reach share that row while staying separately
/// countable, and the row's timestamp is the first reach rather than the last.
/// None of it was tested, and all of it is what the report a user reads is
/// made of — a ledger that silently kept the last stamp instead of the first
/// would still render, and would answer the one question the report exists to
/// answer ("did this break during activation?") backwards.
@MainActor
struct NotImplementedLedgerTests {

    /// A clock that only moves when a test moves it. The stamp rule is about
    /// two readings being *different*, which the real clock cannot be relied
    /// on to make them.
    private final class StoppedClock {
        var now: Date
        init(_ start: Date) { self.now = start }
    }

    private func makeLedger(
        startingAt start: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> (NotImplementedLedger, StoppedClock) {
        let clock = StoppedClock(start)
        return (NotImplementedLedger(now: { clock.now }), clock)
    }

    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - The stamp

    /// First, not last. An extension that trips on a missing member during
    /// activation and an extension that trips on it an hour later are two
    /// different reports, and only the first stamp distinguishes them.
    @Test("the first reach sets the stamp and no later reach moves it")
    func theFirstStampIsKept() throws {
        let (ledger, clock) = makeLedger()

        ledger.record(memberPath: "vscode.tasks.executeTask", extensionIdentifier: "acme.widget")
        clock.now = start.addingTimeInterval(3600)
        ledger.record(memberPath: "vscode.tasks.executeTask", extensionIdentifier: "acme.widget")

        let row = try #require(ledger.accesses.first)
        #expect(row.firstAccess == start)
        #expect(row.count == 2)
    }

    /// A probe is a reach too, so it must not move the stamp either — and a
    /// probe arriving *first* is what sets it.
    @Test("a probe sets the stamp if it is first, and never moves it after")
    func aProbeObeysTheSameStampRule() throws {
        let (ledger, clock) = makeLedger()

        ledger.recordProbe(memberPath: "fetch", extensionIdentifier: "acme.widget")
        clock.now = start.addingTimeInterval(60)
        ledger.record(memberPath: "fetch", extensionIdentifier: "acme.widget")

        let row = try #require(ledger.accesses.first)
        #expect(row.firstAccess == start)
    }

    /// Two different members are two rows, so each keeps its own stamp — the
    /// rule is per row and not a single "when did this extension first
    /// stumble".
    @Test("each member keeps the stamp of its own first reach")
    func eachRowKeepsItsOwnStamp() {
        let (ledger, clock) = makeLedger()

        ledger.record(memberPath: "a", extensionIdentifier: "acme.widget")
        clock.now = start.addingTimeInterval(120)
        ledger.record(memberPath: "b", extensionIdentifier: "acme.widget")

        #expect(ledger.accesses.map(\.firstAccess)
            == [start, start.addingTimeInterval(120)])
    }

    // MARK: - Uses and probes

    /// The two counters answer different questions, so a use must not show up
    /// as a probe and a probe must not show up as a use. A ledger that merged
    /// them would report an extension that quietly took its fallback path as
    /// one that broke.
    @Test("a refused use and a negative probe share one row and two counters")
    func usesAndProbesShareARowAndNotACounter() throws {
        let (ledger, _) = makeLedger()

        ledger.recordProbe(memberPath: "vscode.notebooks", extensionIdentifier: "acme.widget")
        ledger.record(memberPath: "vscode.notebooks", extensionIdentifier: "acme.widget")
        ledger.record(memberPath: "vscode.notebooks", extensionIdentifier: "acme.widget")

        #expect(ledger.accesses.count == 1)
        let row = try #require(ledger.accesses.first)
        #expect(row.count == 2)
        #expect(row.probeCount == 1)
    }

    /// The row the report most wants and the system would otherwise never
    /// notice: an extension that feature-detected, found nothing, and never
    /// called. Its use count is zero and the row exists anyway.
    @Test("a member only ever probed is a row with no uses at all")
    func aProbeOnlyRowHasNoUses() throws {
        let (ledger, _) = makeLedger()

        ledger.recordProbe(memberPath: "vscode.lm", extensionIdentifier: "acme.widget")
        ledger.recordProbe(memberPath: "vscode.lm", extensionIdentifier: "acme.widget")

        let row = try #require(ledger.accesses.first)
        #expect(row.count == 0)
        #expect(row.probeCount == 2)
    }

    /// The value handed back is the value stored, which is what lets a caller
    /// log the row it just recorded without reading the ledger again.
    @Test("the row returned is the row that was kept")
    func theReturnedRowIsTheStoredOne() {
        let (ledger, _) = makeLedger()

        ledger.record(memberPath: "vscode.lm", extensionIdentifier: "acme.widget")
        let second = ledger.record(memberPath: "vscode.lm", extensionIdentifier: "acme.widget")

        #expect(ledger.accesses == [second])
    }

    // MARK: - Whose row it is

    /// The key is the pair, not the member. Two extensions reaching for the
    /// same missing member is the commonest shape there is — a shared library
    /// vendored into both — and collapsing them would attribute one
    /// extension's breakage to another.
    @Test("two extensions reaching for the same member keep separate rows")
    func theKeyIsTheExtensionAndTheMember() {
        let (ledger, _) = makeLedger()

        ledger.record(memberPath: "fetch", extensionIdentifier: "acme.widget")
        ledger.record(memberPath: "fetch", extensionIdentifier: "other.thing")

        #expect(ledger.accesses.count == 2)
        #expect(ledger.accesses.allSatisfy { $0.count == 1 })
    }

    @Test("asking for one extension's rows leaves every other extension out")
    func rowsCanBeReadPerExtension() {
        let (ledger, _) = makeLedger()

        ledger.record(memberPath: "fetch", extensionIdentifier: "acme.widget")
        ledger.record(memberPath: "vscode.lm", extensionIdentifier: "acme.widget")
        ledger.record(memberPath: "fetch", extensionIdentifier: "other.thing")

        #expect(ledger.accesses(for: "acme.widget").map(\.memberPath) == ["fetch", "vscode.lm"])
        #expect(ledger.accesses(for: "other.thing").map(\.memberPath) == ["fetch"])
        #expect(ledger.accesses(for: "nobody.here").isEmpty)
    }

    /// Sorted rather than first-seen, so two runs of the same extension
    /// produce the same report and the difference between them is a real
    /// difference.
    @Test("the list is ordered by extension and then by member, not by arrival")
    func theListIsSortedRatherThanChronological() {
        let (ledger, _) = makeLedger()

        ledger.record(memberPath: "zeta", extensionIdentifier: "zz.last")
        ledger.record(memberPath: "beta", extensionIdentifier: "aa.first")
        ledger.record(memberPath: "alpha", extensionIdentifier: "zz.last")
        ledger.record(memberPath: "alpha", extensionIdentifier: "aa.first")

        #expect(ledger.accesses.map { "\($0.extensionIdentifier)/\($0.memberPath)" }
            == ["aa.first/alpha", "aa.first/beta", "zz.last/alpha", "zz.last/zeta"])
    }

    @Test("a ledger nothing has been recorded in is empty")
    func aFreshLedgerIsEmpty() {
        let (ledger, _) = makeLedger()

        #expect(ledger.accesses.isEmpty)
    }

    /// The default is the real clock, and a seam that only worked when a test
    /// passed one would be a seam production never crossed.
    @Test("a ledger built without a clock stamps from the real one")
    func theDefaultClockIsTheRealOne() throws {
        let before = Date()

        let ledger = NotImplementedLedger()
        ledger.record(memberPath: "fetch", extensionIdentifier: "acme.widget")

        let row = try #require(ledger.accesses.first)
        #expect(row.firstAccess >= before)
        #expect(row.firstAccess <= Date())
    }
}
