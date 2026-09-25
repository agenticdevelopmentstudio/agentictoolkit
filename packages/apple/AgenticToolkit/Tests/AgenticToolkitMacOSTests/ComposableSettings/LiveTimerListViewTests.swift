import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// A list of running timers: rows kept across reloads, a stop button only
/// where the timer is manual, and clocks that move only while it can be seen.
@Suite(.serialized)
@MainActor
struct LiveTimerListViewTests {

    private typealias Model = ComposableSettings.LiveTimerRowView.Model
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func timer(_ id: String, manual: Bool, subtitle: String? = nil) -> Model {
        Model(id: id, title: id, subtitle: subtitle, startedAt: start, isManual: manual)
    }

    @Test func showsTheEmptyMessageUntilSomethingRuns() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "Nothing running.")
        #expect(list.emptyLabel.stringValue == "Nothing running.")
        #expect(list.emptyLabel.isHidden == false)

        list.setTimers([timer("a", manual: true)])
        #expect(list.emptyLabel.isHidden)

        list.setTimers([])
        #expect(list.rows.isEmpty)
        #expect(list.emptyLabel.isHidden == false)
    }

    @Test func onlyAManualTimerCanBeStopped() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "")
        list.setTimers([timer("manual", manual: true), timer("auto", manual: false)])
        #expect(list.rows.map(\.stopButton.isHidden) == [false, true])
    }

    @Test func aRowIsKeptWhileItsTimerRuns() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "")
        list.setTimers([timer("a", manual: true), timer("b", manual: false)])
        let kept = list.rows[1]

        list.setTimers([timer("b", manual: false, subtitle: "renamed")])

        #expect(list.rows.count == 1)
        #expect(list.rows[0] === kept, "a reload updates the row, it does not rebuild it")
        #expect(kept.model.subtitle == "renamed")
    }

    @Test func stopReportsTheTimersID() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "")
        var stopped: [String] = []
        list.onStop = { stopped.append($0) }
        list.setTimers([timer("a", manual: true)])

        list.rows[0].stopButton.performClick(nil)

        #expect(stopped == ["a"])
    }

    @Test func theClocksMoveOnlyWhileTheListCanBeSeen() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "")
        var visible = false
        list.windowIsVisible = { visible }
        var ticks = 0
        list.onTick = { ticks += 1 }

        list.setTimers([timer("a", manual: true)])
        list.ticker.fireForTests()
        #expect(ticks == 0, "not seen: not started")

        visible = true
        list.visibilityChanged()
        #expect(ticks == 1, "catches up the moment it shows")
        list.ticker.fireForTests()
        #expect(ticks == 2)

        list.setTimers([])
        list.ticker.fireForTests()
        #expect(ticks == 2, "nothing running: stopped")
    }

    @Test func withNoWindowItIsNotSeen() {
        let list = ComposableSettings.LiveTimerListView(emptyMessage: "")
        #expect(list.windowIsVisible() == false)
    }
}
