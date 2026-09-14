import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Stands in for the adaptor that would normally own a subscription, so
/// `ExtensionEventEmitter.removeListeners(ownedBy:)` has something to key on
/// without dragging `MainThreadDiagnostics` into a suite about the emitter.
@MainActor
private final class TestListenerOwner {}

/// Carries a `JSValue?` out of `MainActor.assumeIsolated`, on the same terms
/// as `MainThreadDiagnostics.swift`'s own `UncheckedJSValueBox`: nothing
/// crosses an isolation domain — the block and the `assumeIsolated` body both
/// run on the main actor — but `assumeIsolated`'s return type is checked
/// against `Sendable` and a bare `JSValue?` is not.
private struct TestJSValueBox: @unchecked Sendable {
    let value: JSValue?
}

/// `ExtensionEventEmitter` — this host's port of VS Code's
/// `DebounceEmitter`/`PauseableEmitter`/`Event.map` stack
/// (`event.ts:1544-1615`, pinned commit
/// `3addbda66f9e80c3ed1b943822ab823bb6747b02`) and the callable `Event<T>`
/// of `vscode.d.ts:1766`.
///
/// Driven through a **real `JSContext`** and real extension-visible
/// JavaScript, never a Swift-side listener double: the whole surface under
/// test is the boundary between a JavaScript function and Swift, and a double
/// for the JavaScript half would only ever agree with itself — the reasoning
/// `MainThreadLanguagesTests` records for its own side. The one thing doubled
/// is the window, through `ManualExtensionEventWindow`, because the
/// alternative is a test that sleeps for 50 ms and therefore measures the
/// machine's load rather than the window.
///
/// The diagnostics-specific half of the pipeline — flatten-then-dedup, order,
/// freezing, and the five mutating operations — is exercised in
/// `MainThreadDiagnosticsTests`, against the real `vscode.languages` member.
/// This suite is the machinery underneath it.
///
/// Each `@Test`'s doc names exactly one of the brief's numbered mutations and
/// names no mutation an earlier test in this file already kills. The
/// no-leading-edge test comes first for that reason: the fixed-window test
/// below it delivers exactly one event for three fires, which would already
/// turn red for a leading edge, so claiming that mutation there as well would
/// be a second claim on a kill this file has already made.
@MainActor
@Suite
struct ExtensionEventTests {

    // MARK: - Harness

    private struct Harness {
        let context: JSContext
        let window: ManualExtensionEventWindow
        let emitter: ExtensionEventEmitter<[String]>
        let owner: TestListenerOwner
    }

    /// A context with one callable `Event<string[]>` installed as the global
    /// `onDidChange`, over an emitter whose payload is a plain `[String]`.
    ///
    /// `merge` is upstream's `all => all.flat()` verbatim
    /// (`extHostDiagnostics.ts:240`); `map` is the identity, because the
    /// mapping *stage* is what this suite needs to exist, not any particular
    /// mapper — `MainThreadDiagnosticsTests` tests the real one.
    private func makeHarness(delay: TimeInterval = 0.050) throws -> Harness {
        let context = try #require(JSContext())
        let window = ManualExtensionEventWindow()
        let owner = TestListenerOwner()
        let emitter = ExtensionEventEmitter<[String]>(
            path: "test.onDidChange",
            delay: delay,
            window: window,
            merge: { $0.flatMap { $0 } },
            map: { payload, context in JSValue(object: payload, in: context) }
        )
        let subscribe: @convention(block) () -> JSValue? = { [weak emitter, weak owner] in
            MainActor.assumeIsolated {
                guard let emitter, let owner, let context = JSContext.current() else {
                    return TestJSValueBox(value: nil)
                }
                return TestJSValueBox(
                    value: emitter.subscribe(
                        arguments: VSCodeAPI.currentArguments(), in: context, owner: owner))
            }.value
        }
        context.setObject(subscribe, forKeyedSubscript: "onDidChange" as NSString)
        context.evaluateScript("globalThis.__deliveries = [];")
        return Harness(context: context, window: window, emitter: emitter, owner: owner)
    }

    /// `globalThis.__deliveries.length` — how many times a listener installed
    /// by `recordingListenerSource` has been called.
    private func deliveryCount(_ harness: Harness) throws -> Int {
        let value = harness.context.evaluateScript("globalThis.__deliveries.length")
        let unwrapped = try #require(value)
        return Int(unwrapped.toInt32())
    }

    /// The payload of delivery `index`, flattened back to `[String]`.
    private func delivery(_ index: Int, in harness: Harness) throws -> [String] {
        let value = harness.context.evaluateScript(
            "globalThis.__deliveries[\(index)].join(',')")
        let unwrapped = try #require(value)
        let joined = try #require(unwrapped.toString())
        return joined.isEmpty ? [] : joined.components(separatedBy: ",")
    }

    /// A listener that pushes each event it receives onto
    /// `globalThis.__deliveries`.
    private static let recordingListenerSource = """
    onDidChange(function (event) { globalThis.__deliveries.push(event); });
    """

    // MARK: - Mutation 3

    /// **No leading edge.** `DebounceEmitter.fire` calls `this.pause()`
    /// (`event.ts:1607`) *before* `super.fire(event)` (`event.ts:1613`), so
    /// the very first event of a window is queued like every other one and
    /// nothing at all is delivered when the window opens.
    ///
    /// Kills an implementation that delivers the first event immediately and
    /// only coalesces the rest. The window is deliberately left open across
    /// the assertion — that is the whole claim — and then closed, so that a
    /// fixture which somehow never reached the emitter at all cannot pass:
    /// the event must actually arrive once the window closes.
    @Test
    func nothingIsDeliveredWhenTheWindowOpens() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript(ExtensionEventTests.recordingListenerSource)

        harness.emitter.fire(["a"])

        #expect(harness.window.hasOpenWindow)
        #expect(try deliveryCount(harness) == 0)

        harness.window.closeOpenWindows()
        #expect(try deliveryCount(harness) == 1)
    }

    // MARK: - Mutation 1

    /// **The window is fixed, not trailing-edge.** `event.ts:1606`'s
    /// `if (!this._handle)` arms the timer only when none is pending, so
    /// three fires inside one window extend nothing and arrive together at
    /// that window's close.
    ///
    /// `openCount == 1` is the assertion that does the killing, and it is not
    /// redundant with the delivery count: `ExtensionEventWindowScheduling`
    /// has no cancel, so a trailing-edge implementation could only push the
    /// deadline out by opening a *second* window per fire — after which
    /// closing them all still yields a single delivery (the later closes find
    /// an emptied queue), and only `openCount` says what happened. The
    /// delay is asserted too, so an implementation that opens one window with
    /// some other number cannot pass.
    @Test
    func threeFiresInOneWindowOpenOneWindowAndArriveTogether() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript(ExtensionEventTests.recordingListenerSource)

        harness.emitter.fire(["a"])
        harness.emitter.fire(["b"])
        harness.emitter.fire(["c"])

        #expect(harness.window.openCount == 1)
        #expect(harness.window.requestedDelays == [0.050])

        harness.window.closeOpenWindows()

        #expect(try deliveryCount(harness) == 1)
        #expect(try delivery(0, in: harness) == ["a", "b", "c"])
    }

    // MARK: - Mutation 2

    /// **A second window opens after the first closes.** `event.ts:1609`
    /// clears `_handle` inside the timeout, before `resume()` runs, so the
    /// next `fire` arms a fresh timer.
    ///
    /// Kills an implementation that never clears its handle: with the flag
    /// stuck, the second `fire` opens no window, `openCount` stays at 1, and
    /// the second `closeOpenWindows()` has nothing to close, so only one
    /// delivery ever arrives.
    @Test
    func aSecondFireAfterTheFirstWindowClosesOpensAnotherWindow() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript(ExtensionEventTests.recordingListenerSource)

        harness.emitter.fire(["first"])
        harness.window.closeOpenWindows()
        harness.emitter.fire(["second"])
        harness.window.closeOpenWindows()

        #expect(harness.window.openCount == 2)
        #expect(try deliveryCount(harness) == 2)
        #expect(try delivery(0, in: harness) == ["first"])
        #expect(try delivery(1, in: harness) == ["second"])
    }

    // MARK: - Mutation 4

    /// **With zero listeners the event is dropped, not queued.**
    /// `event.ts:1585`'s `if (this._size)` guards the queue push, so an
    /// extension that subscribes after a change has already fired never
    /// receives that change — and `event.ts:1568`'s `if (_eventQueue.size >
    /// 0)` means the window it was fired into closes with no event at all
    /// rather than an empty one.
    ///
    /// Kills an implementation that queues unconditionally, which would hand
    /// the new subscriber a backlog. The second half is what makes this
    /// distinguishable from a fixture that simply never reached the emitter:
    /// a subsequent real event does arrive at the same listener, so the
    /// silence above was a drop and not a dead wire.
    @Test
    func anEventFiredWithNoListenersIsNotDeliveredToALaterSubscriber() throws {
        let harness = try makeHarness()

        harness.emitter.fire(["dropped"])
        #expect(harness.window.openCount == 1)

        harness.context.evaluateScript(ExtensionEventTests.recordingListenerSource)
        harness.window.closeOpenWindows()

        #expect(try deliveryCount(harness) == 0)

        harness.emitter.fire(["kept"])
        harness.window.closeOpenWindows()

        #expect(try deliveryCount(harness) == 1)
        #expect(try delivery(0, in: harness) == ["kept"])
    }

    // MARK: - Mutation 8

    /// **`thisArgs` is honoured**, and honoured on `event.ts:1286`'s
    /// *truthiness* test rather than a mere `!== undefined`: a truthy second
    /// argument becomes the listener's `this`, while the `null` of the
    /// idiomatic `onDidChangeDiagnostics(fn, null, context.subscriptions)`
    /// binds nothing at all.
    ///
    /// Kills an implementation that drops the second argument (the bound
    /// listener would read `undefined`) and one that binds any non-`undefined`
    /// value (the `null` listener would read the target's tag).
    @Test
    func aTruthyThisArgsIsBoundAndNullIsNot() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript("""
        globalThis.__target = { tag: 'bound' };
        globalThis.__boundSaw = 'unset';
        globalThis.__nullSaw = 'unset';
        onDidChange(function () { globalThis.__boundSaw = this.tag; }, globalThis.__target);
        onDidChange(function () { globalThis.__nullSaw = this === globalThis.__target; }, null);
        """)

        harness.emitter.fire(["x"])
        harness.window.closeOpenWindows()

        let boundSaw = try #require(harness.context.evaluateScript("globalThis.__boundSaw"))
        #expect(boundSaw.toString() == "bound")
        let nullSaw = try #require(harness.context.evaluateScript("globalThis.__nullSaw"))
        #expect(nullSaw.isBoolean)
        #expect(nullSaw.toBool() == false)
    }

    // MARK: - Mutation 9

    /// **The `disposables` array receives the disposable, and the same
    /// disposable is returned.** One object: `event.ts:1322` builds
    /// `result`, `event.ts:1326` hands it to `addToDisposables` (which does
    /// `disposables.push(result)` for an array, `event.ts:1973-1979`), and
    /// `event.ts:1328` returns that same `result` — both effects, which is
    /// how
    /// `onDidChangeDiagnostics(fn, null, context.subscriptions)` works.
    ///
    /// An implementation doing only one turns exactly one of these two
    /// assertions red: the length check fails if nothing is pushed, and the
    /// identity check fails if a second, separate disposable is pushed.
    @Test
    func theDisposableIsBothReturnedAndPushedOntoTheDisposablesArray() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript("""
        globalThis.__bag = [];
        globalThis.__returned = onDidChange(function () {}, null, globalThis.__bag);
        """)

        let length = try #require(harness.context.evaluateScript("globalThis.__bag.length"))
        #expect(Int(length.toInt32()) == 1)

        let identical = try #require(
            harness.context.evaluateScript("globalThis.__bag[0] === globalThis.__returned"))
        #expect(identical.isBoolean)
        #expect(identical.toBool() == true)
    }

    // MARK: - Mutation 10

    /// **Disposing a listener stops delivery, and disposing twice is a
    /// no-op** — the idempotence `VSCodeAPI.disposable(in:onDispose:)`
    /// already guarantees, reused rather than re-implemented.
    ///
    /// Two listeners, not one: with a single listener a second `dispose()`
    /// that wrongly removed "whatever is there now" would be invisible.
    /// Here the survivor is what proves the second call removed nothing, and
    /// `listenerCount` proves the first call removed exactly one.
    @Test
    func disposingAListenerStopsItAndDisposingTwiceRemovesNothingElse() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript("""
        globalThis.__first = 0;
        globalThis.__second = 0;
        globalThis.__firstDisposable =
            onDidChange(function () { globalThis.__first += 1; });
        onDidChange(function () { globalThis.__second += 1; });
        """)
        #expect(harness.emitter.listenerCount == 2)

        harness.emitter.fire(["before"])
        harness.window.closeOpenWindows()

        harness.context.evaluateScript("""
        globalThis.__firstDisposable.dispose();
        globalThis.__firstDisposable.dispose();
        """)
        #expect(harness.emitter.listenerCount == 1)

        harness.emitter.fire(["after"])
        harness.window.closeOpenWindows()

        let first = try #require(harness.context.evaluateScript("globalThis.__first"))
        #expect(Int(first.toInt32()) == 1)
        let second = try #require(harness.context.evaluateScript("globalThis.__second"))
        #expect(Int(second.toInt32()) == 2)
    }

    // MARK: - Mutation 11

    /// **One listener throwing does not prevent the others from being
    /// called, and does not leave the emitter broken for the next window.**
    ///
    /// This is what upstream does, read rather than assumed:
    /// `Emitter._deliver` wraps the call in `try`/`catch`
    /// (`event.ts:1390-1394`) and hands the exception to `onUnexpectedError`
    /// — it is *reported*, never rethrown — and `_deliverQueue`'s loop
    /// (`event.ts:1400-1402`) carries on to the next listener. The emitter is
    /// left clean because `PauseableEmitter.resume` has already decremented
    /// `_isPaused` to zero and cleared `_eventQueue` before `super.fire` runs
    /// (`event.ts:1563-1571`), and `DebounceEmitter`'s timeout has already
    /// cleared `_handle` (`event.ts:1609`). Pinned here as: log it, keep
    /// going, and stay usable.
    ///
    /// Kills an implementation that lets the first listener's exception
    /// abandon the delivery loop (the survivor would never reach 1) and one
    /// that leaves the emitter paused or its window flag stuck (the survivor
    /// would never reach 2).
    @Test
    func aThrowingListenerDoesNotStopTheOthersOrBreakTheNextWindow() throws {
        let harness = try makeHarness()
        harness.context.evaluateScript("""
        globalThis.__survivor = 0;
        onDidChange(function () { throw new Error('boom'); });
        onDidChange(function () { globalThis.__survivor += 1; });
        """)

        harness.emitter.fire(["first"])
        harness.window.closeOpenWindows()

        let afterFirst = try #require(harness.context.evaluateScript("globalThis.__survivor"))
        #expect(Int(afterFirst.toInt32()) == 1)

        harness.emitter.fire(["second"])
        harness.window.closeOpenWindows()

        #expect(harness.window.openCount == 2)
        let afterSecond = try #require(harness.context.evaluateScript("globalThis.__survivor"))
        #expect(Int(afterSecond.toInt32()) == 2)
    }
}
