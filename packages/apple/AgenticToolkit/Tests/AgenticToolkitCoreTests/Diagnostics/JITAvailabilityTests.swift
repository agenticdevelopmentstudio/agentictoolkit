//
//  JITAvailabilityTests.swift
//  AgenticToolkitCoreTests
//

import Foundation
import Testing

@testable import AgenticToolkitCore

/// Whether a JavaScript engine in this process will be allowed to compile, and
/// what to say when it will not.
///
/// The verdict is a pure function of two facts read off this process's own code
/// signature, so it is pinned exhaustively here. The two readings themselves
/// depend on how the test runner was signed — not this repository's to fix, and
/// different locally and in CI — so they get a stability smoke test instead of
/// an assertion about their values.
///
/// Both readings were checked against three binaries signed three ways before
/// this type was written: ad-hoc + hardened + entitled, ad-hoc + hardened, and
/// ad-hoc alone. They read `(true, true)`, `(true, false)` and `(false, false)`
/// respectively, which is what makes them measurements rather than constants.
@Suite("JITAvailability")
struct JITAvailabilityTests {

    @Test("Hardened and entitled is the healthy production build")
    func hardenedAndEntitledIsSilent() {
        let availability = JITAvailability(isHardenedRuntime: true, hasJITEntitlement: true)

        #expect(availability.isDegraded == false)
        #expect(availability.diagnosis == nil)
    }

    /// The case a local Debug build lands in. Nothing enforces the entitlement,
    /// so its absence costs nothing and must not warn — a warning here would be
    /// on screen for every developer every day, which is how the one warning
    /// that matters gets learned into invisibility.
    @Test("Without the hardened runtime a missing entitlement is not a problem")
    func unhardenedIsSilent() {
        let availability = JITAvailability(isHardenedRuntime: false, hasJITEntitlement: false)

        #expect(availability.isDegraded == false)
        #expect(availability.diagnosis == nil)
    }

    @Test("Entitled without the hardened runtime is also not a problem")
    func unhardenedButEntitledIsSilent() {
        let availability = JITAvailability(isHardenedRuntime: false, hasJITEntitlement: true)

        #expect(availability.isDegraded == false)
        #expect(availability.diagnosis == nil)
    }

    /// The one combination this type exists to catch, and the only one that can
    /// reach a shipped build: the hardened runtime is enforcing and the
    /// entitlement that exempts JavaScriptCore is gone.
    @Test("Hardened without the entitlement is degraded, and names the entitlement")
    func hardenedWithoutEntitlementIsTheDefect() throws {
        let availability = JITAvailability(isHardenedRuntime: true, hasJITEntitlement: false)

        #expect(availability.isDegraded)

        let diagnosis = try #require(availability.diagnosis)
        // The cause, precisely enough to act on without going and looking it up.
        #expect(diagnosis.contains("com.apple.security.cs.allow-jit"))
        // The consequence, because whoever reads this is looking at extensions
        // that work and are slow and needs the two joined up.
        #expect(diagnosis.lowercased().contains("slow"))
        // Where the fix goes.
        #expect(diagnosis.contains("App.entitlements"))
    }

    @Test("The diagnosis is a whole sentence a person can act on")
    func diagnosisIsProse() throws {
        let diagnosis = try #require(
            JITAvailability(isHardenedRuntime: true, hasJITEntitlement: false).diagnosis
        )

        #expect(diagnosis.count > 60)
        #expect(diagnosis.hasSuffix("."))
    }

    /// Not an assertion about the answer — it legitimately differs by how the
    /// runner was signed — but about the readings being real, repeatable
    /// measurements rather than something that traps or drifts.
    @Test("The live reading answers, and answers the same way twice")
    func probeIsStable() {
        let first = JITAvailability.probe()
        let second = JITAvailability.probe()

        #expect(first.isHardenedRuntime == second.isHardenedRuntime)
        #expect(first.hasJITEntitlement == second.hasJITEntitlement)
    }

    /// `current` is what production reads, and it must be the memoized form of
    /// the same reading — one per call site would let a process-wide constant
    /// disagree with itself.
    @Test("current matches a fresh reading")
    func currentMatchesAProbe() {
        let probed = JITAvailability.probe()

        #expect(JITAvailability.current.isHardenedRuntime == probed.isHardenedRuntime)
        #expect(JITAvailability.current.hasJITEntitlement == probed.hasJITEntitlement)
    }
}
