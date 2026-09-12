import AppKit
import Foundation

/// Whether window presentation must stay out of the way of whoever is at the
/// keyboard: no app activation, no window pulled above other applications'.
///
/// Two situations turn this on, and they are the same situation twice. A test
/// host turns it on always — a suite that throws fully-drawn windows over
/// someone's work is pure damage, which is what `SingleWindowController`'s
/// `forcesWindowFront` already established for ordering and this generalizes
/// to activation. A **Debug** build turns it on when launched with
/// `-QuietWindowPresentation YES`, which is how an automated session drives
/// the app — opening windows, selecting panels, taking screenshots — while
/// its user is working in another application entirely.
///
/// The Debug half does not exist in a shipping binary. A released app has no
/// automation driving it, and its user clicking "Settings" means "put settings
/// in front of me"; a switch that suppressed that would only ever be a way to
/// ship the wrong behavior by accident.
@MainActor
public enum QuietWindowPresentation {

    /// The Debug half: `open -n -g -a <App> --args -QuietWindowPresentation YES`.
    public static let debugSwitch = DebugLaunchSwitch("QuietWindowPresentation")

    /// The `UserDefaults` key, which is also the launch-argument name.
    public static var defaultsKey: String { debugSwitch.key }

    /// Whether presentation should stay quiet in this process.
    public static var isEnabled: Bool {
        resolve(isTestHost: NSWindow.isRunningInTests, defaults: .standard)
    }

    /// The decision, with its two inputs passed in so both branches are
    /// testable: under XCTest `isEnabled` would otherwise always short-circuit
    /// to `true` and the Debug branch could never be exercised.
    public static func resolve(isTestHost: Bool, defaults: UserDefaults) -> Bool {
        isTestHost || debugSwitch.isOn(defaults: defaults)
    }
}
