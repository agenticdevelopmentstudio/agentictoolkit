import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class QuietWindowPresentationTests: XCTestCase {

    /// A defaults domain of this test's own, so neither the developer's real
    /// preferences nor a sibling test can decide the answer.
    private func scratchDefaults(
        _ contents: [String: Any] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UserDefaults {
        let suite = "QuietWindowPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite), file: file, line: line)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        for (key, value) in contents { defaults.set(value, forKey: key) }
        return defaults
    }

    func testATestHostIsAlwaysQuietWhateverTheDefaultsSay() throws {
        let defaults = try scratchDefaults([QuietWindowPresentation.defaultsKey: false])

        XCTAssertTrue(
            QuietWindowPresentation.resolve(isTestHost: true, defaults: defaults),
            "a suite must never need a launch argument to stop interrupting whoever is running it")
    }

    func testTheLaunchArgumentTurnsQuietPresentationOnOutsideATestHost() throws {
        let defaults = try scratchDefaults([QuietWindowPresentation.defaultsKey: true])

        // The Debug-only half: this is what `open -n -g -a <App> --args
        // -QuietWindowPresentation YES` sets, and it is how an automated
        // session drives the app while its user works elsewhere.
        XCTAssertTrue(QuietWindowPresentation.resolve(isTestHost: false, defaults: defaults))
    }

    func testAnOrdinaryLaunchIsNotQuiet() throws {
        let defaults = try scratchDefaults()

        // The behavior every shipping user gets: clicking "Settings" means
        // "put settings in front of me".
        XCTAssertFalse(QuietWindowPresentation.resolve(isTestHost: false, defaults: defaults))
    }

    func testTheProcessRunningThisSuiteIsQuiet() {
        XCTAssertTrue(QuietWindowPresentation.isEnabled,
            "isEnabled must read the live environment, not just resolve(isTestHost:defaults:)")
    }

    // MARK: - What the flag is wired to

    func testQuietPresentationSuppressesFrontForcing() {
        // The ordering half, which `SingleWindowController` already owned.
        XCTAssertFalse(SingleWindowController.forcesWindowFront)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        // A hand-built NSWindow releases itself on close, which over-releases
        // the reference this test still holds — the crash reads as an unrelated
        // test-host exit, so leave the ownership with ARC and just order it out.
        window.isReleasedWhenClosed = false
        addTeardownBlock { window.orderOut(nil) }
        return window
    }

    func testAQuietlyShownWindowIsVisibleButSunkBehindTheDesktop() throws {
        let window = makeWindow()

        window.makeKeyAndOrderFrontQuietly()

        // On screen and laid out, because that is what the suite asserts about...
        XCTAssertTrue(window.isVisible)
        XCTAssertNotNil(window.screen)
        // ...and behind the desktop picture, because the person at the keyboard
        // must not see it.
        XCTAssertEqual(
            window.level,
            NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow))))
    }

    /// The claim that matters for driving a window: sinking costs nothing a
    /// plain `makeKeyAndOrderFront(nil)` would have bought.
    ///
    /// Stated as a comparison rather than `XCTAssertTrue(isKeyWindow)` because
    /// key status is the *app's* to give: an inactive process — which a test
    /// host is, and which a quietly launched Debug app is too — has no key
    /// window at all, so the bare assertion measures the runner's activation
    /// state rather than anything this code does.
    func testSinkingCostsNoKeyStatusAPlainOrderFrontWouldHaveGiven() throws {
        let control = makeWindow()
        control.makeKeyAndOrderFront(nil)
        let loudly = control.isKeyWindow

        let quiet = makeWindow()
        quiet.makeKeyAndOrderFrontQuietly()

        XCTAssertEqual(quiet.isKeyWindow, loudly)
    }
}
