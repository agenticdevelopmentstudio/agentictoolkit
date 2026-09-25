import AppKit
import Testing
@testable import AgenticToolkitMacOS

@Suite(.serialized)
@MainActor
struct LiveTimerRowViewTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRow() -> ComposableSettings.LiveTimerRowView {
        ComposableSettings.LiveTimerRowView(
            model: .init(id: "run-1", title: "Acme — stenographer",
                         subtitle: "main · $150/hr", startedAt: start, isManual: true))
    }

    @Test func rendersTitleAndSubtitle() {
        let row = makeRow()
        #expect(row.titleLabel.stringValue == "Acme — stenographer")
        #expect(row.subtitleLabel.stringValue == "main · $150/hr")
        #expect(row.subtitleLabel.isHidden == false)
    }

    @Test func hidesAnAbsentSubtitle() {
        let row = ComposableSettings.LiveTimerRowView(
            model: .init(id: "run-2", title: "Unassigned", subtitle: nil,
                         startedAt: start, isManual: false))
        #expect(row.subtitleLabel.isHidden)
    }

    @Test func showsElapsedAsAClock() {
        let row = makeRow()
        row.now = { self.start.addingTimeInterval(3_903) }   // 1h 5m 3s
        row.refreshElapsed()
        #expect(row.elapsedText == "1:05:03")
    }

    @Test func elapsedStartsAtZero() {
        let row = makeRow()
        row.now = { self.start }
        row.refreshElapsed()
        #expect(row.elapsedText == "0:00:00")
    }

    @Test func aClockSkewBackwardsNeverShowsNegativeTime() {
        let row = makeRow()
        row.now = { self.start.addingTimeInterval(-60) }
        row.refreshElapsed()
        #expect(row.elapsedText == "0:00:00")
    }

    @Test func updateSwapsTheModelAndTheElapsedBase() {
        let row = makeRow()
        row.update(.init(id: "run-9", title: "Other", subtitle: nil,
                         startedAt: start.addingTimeInterval(600), isManual: false))
        row.now = { self.start.addingTimeInterval(900) }
        row.refreshElapsed()
        #expect(row.titleLabel.stringValue == "Other")
        #expect(row.elapsedText == "0:05:00")
        #expect(row.model.id == "run-9")
    }

    @Test func stopReportsTheRunID() {
        let row = makeRow()
        var stopped: [String] = []
        row.onStop = { stopped.append($0) }
        row.stopButton.performClick(nil)
        #expect(stopped == ["run-1"])
    }

    @Test func theRowCarriesAccessibilityIdentifiers() {
        let row = makeRow()
        #expect(row.stopButton.accessibilityIdentifier() == "timer.run-1.stop")
        #expect(row.elapsedLabel.accessibilityIdentifier() == "timer.run-1.elapsed")
    }

    @Test func tickerDeliversTicksUntilStopped() {
        let ticker = ComposableSettings.LiveTimerTicker(interval: 1)
        var ticks = 0
        ticker.onTick = { ticks += 1 }
        ticker.start()
        ticker.fireForTests()
        ticker.fireForTests()
        #expect(ticks == 2)

        ticker.stop()
        ticker.fireForTests()
        #expect(ticks == 2)
    }

    @Test func startingATickerTwiceDoesNotDoubleIt() {
        let ticker = ComposableSettings.LiveTimerTicker(interval: 1)
        var ticks = 0
        ticker.onTick = { ticks += 1 }
        ticker.start()
        ticker.start()
        ticker.fireForTests()
        #expect(ticks == 1)
    }

    /// Review V19-d: the origin tooltip is the host's wording, not the toolkit's.
    @Test func originTooltipsAreTheHostsToSet() {
        let row = makeRow()
        #expect(row.originLabel.toolTip == "Started by hand")
        row.manualOriginTooltip = "Started from the menu"
        #expect(row.originLabel.toolTip == "Started from the menu")

        row.automaticOriginTooltip = "Started from session activity"
        row.update(.init(id: "run-1", title: "Acme", startedAt: start, isManual: false))
        #expect(row.originLabel.toolTip == "Started from session activity")
    }
}
