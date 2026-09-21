import Testing
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// What an extension's `setTimeout` delay becomes before anything sleeps on
/// it.
///
/// The only arithmetic in this host that can take the *app* down rather than
/// the extension. `Duration.seconds(Double)` scales its argument into
/// fixed-width attoseconds and traps on a value it cannot represent, and the
/// value reaching it came straight out of JavaScript — so
/// `setTimeout(fn, Number.MAX_VALUE)`, which is one line in one extension,
/// used to kill every other extension and the window with it. The isolation
/// this host exists to provide is exactly the thing that was lost.
///
/// Asserted against the clamp rather than against a timer that fires, because
/// the interesting inputs are the ones that must *not* be slept on: waiting
/// out `Number.MAX_VALUE` is not a test anyone can run, and a test that
/// scheduled it and asserted the app was still up would be asserting the
/// absence of a trap it had no way to observe.
@MainActor
struct ExtensionHostTimerClampTests {

    private func clamp(_ milliseconds: Double) -> Double {
        ExtensionHost.clampedTimerDelaySeconds(milliseconds: milliseconds)
    }

    // MARK: - The ordinary case still works

    /// The control. A clamp that answered zero for everything would satisfy
    /// every safety assertion below and quietly turn every extension's
    /// debounce into a busy loop.
    @Test("an ordinary delay is milliseconds converted to seconds")
    func anOrdinaryDelayIsConverted() {
        #expect(clamp(0) == 0)
        #expect(clamp(1) == 0.001)
        #expect(clamp(250) == 0.25)
        #expect(clamp(1000) == 1)
        #expect(clamp(90_000) == 90)
    }

    /// `setTimeout(fn)` with no delay at all reaches here as 0, and the answer
    /// has to be a sleep of zero rather than a refusal: "next tick" is the
    /// single most common thing an extension asks a timer for.
    @Test("no delay is a zero sleep, not a skipped one")
    func zeroIsAZeroSleep() {
        #expect(clamp(0) == 0)
        #expect(!clamp(0).isNaN)
    }

    // MARK: - Inputs JavaScript can produce and Swift cannot sleep on

    /// The one that crashed. `Number.MAX_VALUE` is a literal an extension can
    /// type, and `.greatestFiniteMagnitude` is the same value arriving from
    /// the bridge.
    @Test("the largest Double an extension can pass is clamped, not trapped")
    func theLargestDoubleIsClamped() {
        let clamped = clamp(.greatestFiniteMagnitude)

        #expect(clamped == ExtensionHost.maximumTimerDelayMilliseconds / 1000)
        #expect(clamped.isFinite)
    }

    /// `setTimeout(fn, Infinity)` — which is what `1/0` or an unguarded
    /// arithmetic on a missing config value produces, not something anyone
    /// types on purpose.
    @Test("an infinite delay is clamped to the ceiling")
    func infinityIsClamped() {
        let clamped = clamp(.infinity)

        #expect(clamped == ExtensionHost.maximumTimerDelayMilliseconds / 1000)
        #expect(clamped.isFinite)
    }

    /// `NaN` is the subtle one, and the reason the `max` comes first. Every
    /// comparison against `NaN` is false, so `min(.nan, ceiling)` answers
    /// `NaN` and hands it straight to `Duration.seconds` — the clamp would
    /// look present and do nothing. `max(0, .nan)` is 0.
    @Test("a NaN delay becomes zero rather than surviving the clamp")
    func nanBecomesZero() {
        let clamped = clamp(.nan)

        #expect(!clamped.isNaN)
        #expect(clamped == 0)
    }

    /// `setTimeout(fn, -1)` is legal JavaScript and means "immediately".
    /// Negative attoseconds are not a thing Swift will sleep for.
    @Test("a negative delay is an immediate one")
    func negativeIsImmediate() {
        #expect(clamp(-1) == 0)
        #expect(clamp(-.infinity) == 0)
        #expect(clamp(-.greatestFiniteMagnitude) == 0)
    }

    // MARK: - The ceiling itself

    /// Exactly at the ceiling passes through unchanged — the boundary is
    /// inclusive, so the longest delay an extension can legitimately ask for
    /// is honoured rather than shortened by a millisecond.
    @Test("a delay exactly at the ceiling is not shortened")
    func theCeilingItselfIsHonoured() {
        let ceiling = ExtensionHost.maximumTimerDelayMilliseconds

        #expect(clamp(ceiling) == ceiling / 1000)
        #expect(clamp(ceiling - 1) == (ceiling - 1) / 1000)
    }

    /// The ceiling is `setTimeout`'s own signed 32-bit limit, about 24.8 days.
    /// Pinned because it is a compatibility choice, not an implementation
    /// detail: every browser and Node truncate there, so an extension written
    /// against them already treats a longer delay as undefined behaviour.
    @Test("the ceiling is the 32-bit setTimeout limit")
    func theCeilingIsTheSetTimeoutLimit() {
        #expect(ExtensionHost.maximumTimerDelayMilliseconds == 2_147_483_647)
        #expect(ExtensionHost.maximumTimerDelayMilliseconds
            == Double(Int32.max))
    }

    /// Whatever comes out is something `Duration.seconds` can hold — which is
    /// the entire point, stated once as a property rather than as a
    /// consequence of the six cases above.
    @Test("every clamped delay is a duration Swift can represent")
    func everyAnswerIsRepresentable() {
        let inputs: [Double] = [
            .nan, .infinity, -.infinity, .greatestFiniteMagnitude,
            -.greatestFiniteMagnitude, .leastNonzeroMagnitude,
            -0.0, 0, 1, 2_147_483_648, 1e300, -1e300
        ]

        for input in inputs {
            let clamped = clamp(input)
            #expect(clamped.isFinite, "\(input) produced \(clamped)")
            #expect(clamped >= 0, "\(input) produced \(clamped)")
            #expect(clamped <= ExtensionHost.maximumTimerDelayMilliseconds / 1000,
                    "\(input) produced \(clamped)")
            // The assertion the crash was: this is the call that trapped.
            _ = Duration.seconds(clamped)
        }
    }
}
