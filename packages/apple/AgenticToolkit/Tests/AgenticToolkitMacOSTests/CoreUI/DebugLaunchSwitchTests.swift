import Foundation
import XCTest
@testable import AgenticToolkitMacOS

final class DebugLaunchSwitchTests: XCTestCase {

    private func scratchDefaults(
        _ contents: [String: Any] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UserDefaults {
        let suite = "DebugLaunchSwitchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite), file: file, line: line)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for (key, value) in contents { defaults.set(value, forKey: key) }
        return defaults
    }

    func testASwitchIsOffUntilItsLaunchArgumentSaysOtherwise() throws {
        let never = DebugLaunchSwitch("NeverPassed")

        XCTAssertFalse(never.isOn(defaults: try scratchDefaults()))
    }

    func testTheLaunchArgumentTurnsItOnInADebugBuild() throws {
        let flag = DebugLaunchSwitch("SomeDebugBehavior")
        let defaults = try scratchDefaults([flag.key: true])

        // This suite only ever builds Debug, so the `#if` below is not a
        // tautology-free assertion — it is the Debug branch, and the Release
        // branch is asserted by the compiler refusing to read `defaults` there.
        #if DEBUG
        XCTAssertTrue(flag.isOn(defaults: defaults))
        #else
        XCTAssertFalse(flag.isOn(defaults: defaults),
            "a shipping build must ignore the argument entirely")
        #endif
    }

    // `QuietWindowPresentation` is `@MainActor` (it reads `NSWindow` state), so
    // reading its two statics has to be too.
    @MainActor
    func testTheKeyIsTheArgumentName() {
        // `open --args -QuietWindowPresentation YES` writes the argument domain
        // under exactly this name; if the two ever diverge the switch silently
        // stops working and nothing fails loudly.
        XCTAssertEqual(QuietWindowPresentation.debugSwitch.key, "QuietWindowPresentation")
        XCTAssertEqual(QuietWindowPresentation.defaultsKey, "QuietWindowPresentation")
    }
}
