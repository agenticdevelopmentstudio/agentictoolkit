// Tests/AgenticToolkitMacOSTests/Chat/TranscriptDateTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// What a transcript says about *when*.
///
/// Two halves of one question, which is why they are one file: a message says
/// the time of day, and the transcript says the day — once, where it changes.
/// Both are invisible to a build and to every layout test. A 24-hour clock, or
/// a banner that repeats on every row or never appears at all, renders a
/// perfectly correct window that answers the wrong question.
@MainActor
final class TranscriptDateTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    // MARK: - The clock

    /// Thirteen o'clock is one o'clock. The dial is fixed at twelve rather than
    /// taken from the locale's time style, so this holds wherever the test runs.
    func testAnAfternoonTimeReadsOnATwelveHourDial() throws {
        let afternoon = AIChatBubbleView.timeFormatter.string(from: try date(hour: 13, minute: 5))
        XCTAssertTrue(afternoon.hasPrefix("1:05"),
                      "13:05 was written \"\(afternoon)\", not on a twelve-hour dial")
        XCTAssertFalse(afternoon.contains("13"),
                       "\"\(afternoon)\" still has a 24-hour hour in it")
    }

    /// Midnight is the hour a twelve-hour dial gets wrong: `0:05` is nobody's
    /// way of saying it, and `12:05` with the wrong half-of-day is worse.
    func testMidnightReadsAsTwelveAndNotAsZero() throws {
        let midnight = AIChatBubbleView.timeFormatter.string(from: try date(hour: 0, minute: 5))
        XCTAssertTrue(midnight.hasPrefix("12:05"),
                      "00:05 was written \"\(midnight)\", not as twelve")
    }

    /// Halving the dial only works if the halves are told apart, so the
    /// AM/PM word has to be there — on a twelve-hour clock without it, every
    /// reading means two things.
    func testMorningAndAfternoonAreNotTheSameString() throws {
        let morning = AIChatBubbleView.timeFormatter.string(from: try date(hour: 9, minute: 41))
        let evening = AIChatBubbleView.timeFormatter.string(from: try date(hour: 21, minute: 41))
        XCTAssertTrue(morning.hasPrefix("9:41"), "9:41 was written \"\(morning)\"")
        XCTAssertTrue(evening.hasPrefix("9:41"), "21:41 was written \"\(evening)\"")
        XCTAssertNotEqual(morning, evening,
                          "both halves of the day read \"\(morning)\" — the dial says nothing")
    }

    // MARK: - The banner

    /// The banner is the one place a date is written out in full: it is said
    /// once a day rather than once a message, and the reader who scrolled far
    /// enough to need it is asking *which* day.
    func testTheBannerNamesTheWholeDay() throws {
        let calendar = Calendar.current
        let moment = try date(hour: 15, minute: 0)
        let banner = ChatDayBannerView(day: moment, calendar: calendar)

        let parts = calendar.dateComponents([.year, .month, .weekday], from: moment)
        let weekday = calendar.weekdaySymbols[try XCTUnwrap(parts.weekday) - 1]
        let month = calendar.monthSymbols[try XCTUnwrap(parts.month) - 1]

        XCTAssertTrue(banner.title.contains(weekday),
                      "\"\(banner.title)\" does not name the weekday")
        XCTAssertTrue(banner.title.contains(month),
                      "\"\(banner.title)\" does not name the month")
        XCTAssertTrue(banner.title.contains(String(try XCTUnwrap(parts.year))),
                      "\"\(banner.title)\" does not name the year")
    }

    /// Two instants on the same day share a banner however far apart they are,
    /// and the day is the *reader's* — bounded by their own midnight, not by
    /// twenty-four hours from whenever the first message landed.
    func testTwoTimesOnOneDayBelongToOneBanner() throws {
        let morning = ChatDayBannerView(day: try date(hour: 0, minute: 30))
        let night = ChatDayBannerView(day: try date(hour: 23, minute: 30))
        XCTAssertEqual(morning.day, night.day,
                       "half past midnight and half past eleven were put on different days")
        XCTAssertEqual(morning.title, night.title)
    }

    // MARK: - The transcript

    /// Where the banners land: one per day, in front of that day's first
    /// message and nowhere else. Three messages over two days is the smallest
    /// fixture that can tell "once a day" from "once a message" — the middle
    /// message is the one a per-message banner would wrongly head.
    func testATranscriptHeadsEachDayWithOneBannerBeforeItsFirstMessage() async throws {
        let day1 = try date(hour: 9, minute: 15)
        let day2 = try date(hour: 10, minute: 0, addingDays: 1)
        let messages = [
            ChatMessage(role: .user, text: "first thing", timestamp: day1),
            ChatMessage(role: .assistant, text: "later that day", timestamp: day1.addingTimeInterval(3600)),
            ChatMessage(role: .user, text: "next morning", timestamp: day2)
        ]
        let views = try await transcript(of: messages)
        let banners = views.compactMap { $0 as? ChatDayBannerView }

        XCTAssertEqual(banners.count, 2,
                       "three messages over two days produced \(banners.count) banners")
        XCTAssertEqual(banners.map(\.day),
                       [Calendar.current.startOfDay(for: day1),
                        Calendar.current.startOfDay(for: day2)],
                       "the banners are not the two days the messages fall on, in order")

        let positions = views.indices.filter { views[$0] is ChatDayBannerView }
        XCTAssertEqual(positions, [0, 3],
                       "a banner sits somewhere other than in front of its day's first message")
    }

    /// A transcript that never changes day still gets its date said once. The
    /// first message opens a day like any other — there is no "current" day for
    /// it to already belong to.
    func testATranscriptWithinOneDayStillOpensWithItsBanner() async throws {
        let noon = try date(hour: 12, minute: 0)
        let messages = (0..<4).map {
            ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant,
                        text: "message \($0)",
                        timestamp: noon.addingTimeInterval(Double($0) * 60))
        }
        let views = try await transcript(of: messages)

        XCTAssertEqual(views.compactMap { $0 as? ChatDayBannerView }.count, 1,
                       "four messages on one day did not get exactly one banner")
        XCTAssertTrue(views.first is ChatDayBannerView,
                      "the transcript opens on a message with no day named")
    }

    // MARK: - Fixtures

    /// An instant today at the given wall-clock time, in the reader's own time
    /// zone — the one both the formatter and the banner bound their day by.
    private func date(hour: Int, minute: Int, addingDays days: Int = 0) throws -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        let base = try XCTUnwrap(calendar.date(from: components))
        return try XCTUnwrap(calendar.date(byAdding: .day, value: days, to: base))
    }

    /// The transcript's own views, oldest first. The first arranged subview is
    /// the spacer `ChatView` puts above the transcript, which is not one of them.
    private func transcript(of messages: [ChatMessage]) async throws -> [NSView] {
        // An hour's refresh: the first load is the whole of what this test wants.
        let session = FeedChatSession(refreshInterval: .seconds(3600)) { messages }
        let viewModel = AIChatViewModel(session: session)
        let view = ChatView(viewModel: viewModel)
        view.isComposerEnabled = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        self.window = window

        for _ in 0..<100 where viewModel.messages.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(20))
        }
        view.layoutSubtreeIfNeeded()

        let scroll = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try XCTUnwrap(scroll.documentView as? NSStackView)
        return Array(stack.arrangedSubviews.dropFirst())
    }
}
