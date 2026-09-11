import Testing
@testable import AgenticToolkitMacOS

/// Pins `AppFeatureRegistry.features`' order (W-M1 in the review this fixes):
/// it used to be `Array(featureMap.values)`, a Swift `Dictionary`'s value
/// order, which is seeded per process and therefore not the order features
/// were registered in — and Whippet's `MenuManager` relies on that order for
/// the order File-menu groups appear in.
///
/// Three distinct `AppFeature` subclasses, not three instances of one, because
/// `AppFeature.init()` registers under `defaultName` — derived from
/// `type(of: self)` — and three same-typed instances would collide on one
/// name, each replacing the last rather than adding three entries.
@MainActor
private final class OrderTestFeatureA: AppFeature {}
@MainActor
private final class OrderTestFeatureB: AppFeature {}
@MainActor
private final class OrderTestFeatureC: AppFeature {}

@Suite("AppFeatureRegistry ordering")
@MainActor
struct AppFeatureRegistryTests {

    @Test("features returns registrations in registration order")
    func registrationOrderPreserved() {
        let featureA = OrderTestFeatureA()
        let featureB = OrderTestFeatureB()
        let featureC = OrderTestFeatureC()
        defer {
            AppFeatureRegistry.shared.unregister(featureA)
            AppFeatureRegistry.shared.unregister(featureB)
            AppFeatureRegistry.shared.unregister(featureC)
        }

        // `AppFeatureRegistry.shared` is a process-wide singleton other
        // suites may also register into, so this filters to just the three
        // names under test rather than asserting on `features` whole — the
        // claim is about relative order, not exclusive occupancy.
        let testNames: Set<String> = ["OrderTestFeatureA", "OrderTestFeatureB", "OrderTestFeatureC"]
        let orderedTestNames = AppFeatureRegistry.shared.features
            .map(\.featureName)
            .filter { testNames.contains($0) }

        #expect(orderedTestNames == ["OrderTestFeatureA", "OrderTestFeatureB", "OrderTestFeatureC"])
    }

    @Test("unregister removes from both featureMap and features")
    func unregisterRemovesFromBoth() {
        let feature = OrderTestFeatureA()
        AppFeatureRegistry.shared.unregister(feature)

        #expect(AppFeatureRegistry.shared.feature(named: "OrderTestFeatureA") == nil)
        #expect(!AppFeatureRegistry.shared.features.contains { $0 === feature })
    }
}

// MARK: - Shutdown

@MainActor
private final class ShutdownJournal {
    private(set) var entries: [String] = []

    func record(_ entry: String) {
        entries.append(entry)
    }
}

/// Records both shutdown hooks, and can park inside the async one so a test
/// can look at what the registry did — or did not — start meanwhile.
@MainActor
private class ShutdownRecordingFeature: AppFeature {
    private let journal: ShutdownJournal
    private let holdsTerminate: Bool
    private var gate: CheckedContinuation<Void, Never>?

    init(journal: ShutdownJournal, holdsTerminate: Bool = false) {
        self.journal = journal
        self.holdsTerminate = holdsTerminate
        super.init()
    }

    override func stop() {
        journal.record("stop:\(featureName)")
    }

    override func terminate() async {
        journal.record("terminate-begin:\(featureName)")
        if holdsTerminate {
            await withCheckedContinuation { gate = $0 }
        }
        journal.record("terminate-end:\(featureName)")
    }

    func releaseHeldTerminate() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
private final class ShutdownFeatureFirst: ShutdownRecordingFeature {}
@MainActor
private final class ShutdownFeatureSecond: ShutdownRecordingFeature {}

/// The shutdown split the app delegate depends on: `stop()` is the synchronous
/// half and `terminate()` the awaited one, and a feature's flush is entitled to
/// assume the features ahead of it are already done with theirs. A `terminateAll`
/// that fanned out concurrently — or that returned before the hooks finished —
/// would lose exactly the debounced saves the split exists to keep.
///
/// These build their own registry rather than driving `AppFeatureRegistry.shared`:
/// the singleton is process-wide, and calling `stopAll()` on it would tear down
/// whatever other suites in this bundle have registered.
@Suite("AppFeatureRegistry shutdown")
@MainActor
struct AppFeatureRegistryShutdownTests {

    private func makeRegistry(
        journal: ShutdownJournal,
        firstHolds: Bool = false
    ) -> (AppFeatureRegistry, ShutdownFeatureFirst, ShutdownFeatureSecond) {
        let registry = AppFeatureRegistry()
        let first = ShutdownFeatureFirst(journal: journal, holdsTerminate: firstHolds)
        let second = ShutdownFeatureSecond(journal: journal)
        // `AppFeature.init()` registers into the singleton; these belong to the
        // local registry only.
        AppFeatureRegistry.shared.unregister(first)
        AppFeatureRegistry.shared.unregister(second)
        registry.register(first)
        registry.register(second)
        return (registry, first, second)
    }

    @Test("stopAll runs every feature's synchronous hook, in registration order")
    func stopAllRunsEveryHookInOrder() {
        let journal = ShutdownJournal()
        let (registry, _, _) = makeRegistry(journal: journal)

        registry.stopAll()

        #expect(journal.entries == ["stop:ShutdownFeatureFirst", "stop:ShutdownFeatureSecond"])
    }

    @Test("terminateAll awaits each feature's hook to completion before the next begins")
    func terminateAllIsSequentialAndAwaited() async {
        let journal = ShutdownJournal()
        let (registry, first, _) = makeRegistry(journal: journal, firstHolds: true)

        let shutdown = Task { @MainActor in await registry.terminateAll() }
        var started = false
        for _ in 0..<100 where !started {
            try? await Task.sleep(for: .milliseconds(10))
            started = journal.entries.contains("terminate-begin:ShutdownFeatureFirst")
        }
        #expect(started, "terminateAll never reached the first feature's hook")
        #expect(
            !journal.entries.contains("terminate-begin:ShutdownFeatureSecond"),
            "the second feature's flush began while the first was still running"
        )

        first.releaseHeldTerminate()
        await shutdown.value

        #expect(journal.entries == [
            "terminate-begin:ShutdownFeatureFirst",
            "terminate-end:ShutdownFeatureFirst",
            "terminate-begin:ShutdownFeatureSecond",
            "terminate-end:ShutdownFeatureSecond"
        ])
    }
}
