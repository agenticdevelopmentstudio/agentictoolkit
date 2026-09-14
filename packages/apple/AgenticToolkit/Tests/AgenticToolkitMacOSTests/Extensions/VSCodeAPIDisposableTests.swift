import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitMacOS

/// `VSCodeAPI.disposable(in:onDispose:)` (`VSCodeAPI.swift:1040`): the shared
/// `{ dispose() }` object builder every disposable-returning adaptor member
/// hands back to an extension. Its own idempotence — a second `dispose()`
/// call is a no-op, per `disposed` at `VSCodeAPI.swift:1045` and the
/// guard/set pair at `:1048-1049` — is exercised only indirectly elsewhere:
/// `MainThreadCommandsTests` and `MainThreadLanguagesTests` each build a
/// disposable through this helper and dispose it, but every one of their own
/// `onDispose` closures is independently idempotent (removing an already-gone
/// registration is itself a no-op), so none of them would fail if the guard
/// here were deleted and `onDispose` ran twice. This suite is the only place
/// traced (not a sweep of the repo) that pins the guard directly, with an
/// `onDispose` that is *not* independently idempotent — a bare counter
/// increment — so a second call is only harmless if the guard itself does
/// the work.
@MainActor
@Suite
struct VSCodeAPIDisposableTests {

    private func makeContext() throws -> JSContext {
        try #require(JSContext())
    }

    /// Calling the returned object's `dispose()` twice runs `onDispose` once
    /// — the mutation this kills is deleting (or inverting) the
    /// `guard !disposed else { return }` / `disposed = true` pair at
    /// `VSCodeAPI.swift:1048-1049`: with either gone, a non-idempotent
    /// `onDispose` (this counter) would observe 2, not 1.
    @Test
    func disposingTwiceRunsOnDisposeExactlyOnce() throws {
        let context = try makeContext()
        var disposeCount = 0
        let maybeDisposable = VSCodeAPI.disposable(in: context, onDispose: {
            disposeCount += 1
        })
        let disposable = try #require(maybeDisposable)
        context.setObject(disposable, forKeyedSubscript: "d" as NSString)
        context.evaluateScript("d.dispose(); d.dispose();")
        #expect(context.exception == nil)
        #expect(disposeCount == 1)
    }

    /// A single `dispose()` call still runs `onDispose` — the mutation this
    /// names is a guard that runs `onDispose` on the *second* call rather than
    /// the first (`guard disposed else { disposed = true; return }`): after two
    /// calls that leaves `disposeCount == 1`, so
    /// `disposingTwiceRunsOnDisposeExactlyOnce` above still passes, while after
    /// one call it leaves `disposeCount == 0`, which this test catches.
    ///
    /// What this test adds is the *direct* pin, not exclusivity. The mutant
    /// is also caught incidentally by a test that asserts the effect **after
    /// the first `dispose()` call, before any second call can repair the
    /// state** — that assertion observes exactly the call the mutant
    /// suppresses, regardless of whether a later call on the same handle
    /// follows it. Three were traced against the mutant by hand and do catch
    /// it under that rule: `MainThreadCommandsTests`'
    /// `theDisposableUnregistersAndIsIdempotent` (its assertion sits between
    /// its two `dispose()` calls), and `MainThreadLanguagesTests`'
    /// `disposeRemovesTheRegistrationFromTheStore` and
    /// `twoConfigurationsForOneLanguageBothSurviveAndDisposingOneLeavesTheOther`
    /// (each asserts after its one call, with no second call at all). Each
    /// fails for a second reason (a registration that never went away), so
    /// none of them localises the defect; this one does. Three is what was
    /// traced, not a count of the repo — no sweep was done, and others may also
    /// catch it incidentally. Nothing here rests on the number: the point is
    /// that incidental catches exist, so this test is not the only one.
    ///
    /// `MainThreadLanguagesTests`'
    /// `disposingTwiceIsANoOpAndDoesNotTouchALaterRegistration` does not
    /// qualify under that same rule: both `dispose()` calls happen inside
    /// `activate()` with no assertion between them, so nothing observes the
    /// state the mutant's suppressed first call would have left before the
    /// second call can repair it. Correct code removes on call 1 and no-ops
    /// on call 2; the mutant no-ops on call 1 and removes on call 2; and
    /// because both calls are bound to the same handle the store ends in the
    /// same state either way — one registration, the later one. That test's
    /// own doc already declines the neighbouring *dropped*-guard mutant for a
    /// related reason.
    ///
    /// The suite doc's "only place traced" claim above is about *deleting*
    /// the guard, which those idempotent `onDispose` closures absorb — a
    /// different mutant, and (like that claim) not a repo-wide sweep.
    @Test
    func disposingOnceRunsOnDisposeOnce() throws {
        let context = try makeContext()
        var disposeCount = 0
        let maybeDisposable = VSCodeAPI.disposable(in: context, onDispose: {
            disposeCount += 1
        })
        let disposable = try #require(maybeDisposable)
        context.setObject(disposable, forKeyedSubscript: "d" as NSString)
        context.evaluateScript("d.dispose();")
        #expect(context.exception == nil)
        #expect(disposeCount == 1)
    }
}
