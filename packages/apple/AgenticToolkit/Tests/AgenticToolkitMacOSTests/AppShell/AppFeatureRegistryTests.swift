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
