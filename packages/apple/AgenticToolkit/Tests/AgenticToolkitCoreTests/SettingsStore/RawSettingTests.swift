import XCTest
import OSLog
@testable import AgenticToolkitCore

final class RawSettingTests: XCTestCase {

    func testBoolReadsEverySpellingAndFallsBackOnGarbage() {
        for raw in ["1", "true", " YES ", "on"] {
            XCTAssertTrue(RawSetting.bool(raw, default: false), raw)
        }
        for raw in ["0", "False", "no", "OFF"] {
            XCTAssertFalse(RawSetting.bool(raw, default: true), raw)
        }
        XCTAssertTrue(RawSetting.bool(nil, default: true))
        XCTAssertFalse(RawSetting.bool("maybe", default: false))
    }

    func testIntClampsIntoRangeAndFallsBackWhenAbsent() {
        XCTAssertEqual(RawSetting.int(" 30 ", default: 15, range: 1...240), 30)
        XCTAssertEqual(RawSetting.int("0", default: 15, range: 1...240), 1)
        XCTAssertEqual(RawSetting.int("9999", default: 15, range: 1...240), 240)
        XCTAssertEqual(RawSetting.int("abc", default: 15, range: 1...240), 15)
        XCTAssertEqual(RawSetting.int(nil, default: 15, range: 1...240), 15)
    }

    func testStringTrimsAndFallsBackWhenEmpty() {
        XCTAssertEqual(RawSetting.string(" day ", default: "session"), "day")
        XCTAssertEqual(RawSetting.string("   ", default: "session"), "session")
        XCTAssertEqual(RawSetting.string(nil, default: "session"), "session")
    }
}

@MainActor
final class SettingsSnapshotPushTests: XCTestCase {

    private actor Received {
        var bodies: [Data] = []
        var failuresLeft: Int
        init(failures: Int) { failuresLeft = failures }
        func take(_ body: Data) -> Bool {
            if failuresLeft > 0 {
                failuresLeft -= 1
                return false
            }
            bodies.append(body)
            return true
        }
    }

    private let logger = Logger(subsystem: "AgenticToolkitCoreTests", category: "SettingsSnapshotPush")

    func testPushesOnStartAndOnEveryReconnect() async {
        let received = Received(failures: 0)
        var reconnect: (@Sendable () -> Void)?
        var value = 1
        let push = SettingsSnapshotPush(
            label: "Test", logger: logger, backoffs: [0],
            snapshot: { SettingsSnapshotPush.encodeSorted(["value": value]) },
            send: { await received.take($0) },
            registerReconnect: { reconnect = $0 }
        )

        push.start(makeObservers: { _ in [] })
        await push.awaitPendingPush()
        XCTAssertTrue(push.isObserving)
        var bodies = await received.bodies
        XCTAssertEqual(bodies, [Data(#"{"value":1}"#.utf8)])

        value = 2
        reconnect?()
        let deadline = Date().addingTimeInterval(5)
        while await received.bodies.count < 2, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        bodies = await received.bodies
        XCTAssertEqual(bodies.last, Data(#"{"value":2}"#.utf8))
    }

    func testRetriesABoundedNumberOfTimes() async {
        let received = Received(failures: 2)
        let push = SettingsSnapshotPush(
            label: "Test", logger: logger, backoffs: [0, 1_000_000, 1_000_000],
            snapshot: { Data("{}".utf8) },
            send: { await received.take($0) },
            registerReconnect: { _ in }
        )
        push.push()
        await push.awaitPendingPush()
        let bodies = await received.bodies
        XCTAssertEqual(bodies.count, 1, "the third attempt lands")
    }

    func testAStoppedPushIgnoresReconnects() async throws {
        let received = Received(failures: 0)
        var reconnect: (@Sendable () -> Void)?
        let push = SettingsSnapshotPush(
            label: "Test", logger: logger, backoffs: [0],
            snapshot: { Data("{}".utf8) },
            send: { await received.take($0) },
            registerReconnect: { reconnect = $0 }
        )
        push.start(makeObservers: { _ in [] })
        await push.awaitPendingPush()
        push.stop()
        reconnect?()
        try await Task.sleep(for: .milliseconds(50))
        let bodies = await received.bodies
        XCTAssertEqual(bodies.count, 1)
    }

    func testEncodesWithSortedKeys() {
        let body = SettingsSnapshotPush.encodeSorted(["b": "2", "a": "1"])
        XCTAssertEqual(body, Data(#"{"a":"1","b":"2"}"#.utf8))
    }
}
