import XCTest
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

@MainActor
final class SettingObservingTests: XCTestCase {

    /// A closure-backed row reads through to its storage, writes through to it,
    /// and notifies — the three things every ComposableSettings view relies on.
    func testClosureObserverReadsWritesAndNotifies() async {
        var backing = 7
        let observer = ClosureSettingObserver<Int>(get: { backing }, set: { backing = $0 })

        XCTAssertEqual(observer.value, 7, "reads through to the backing store")

        let notified = expectation(description: "onChange fires")
        var seen: Int?
        observer.onChange = { newValue in
            seen = newValue
            notified.fulfill()
        }

        observer.value = 42
        XCTAssertEqual(backing, 42, "writes through to the backing store")

        await fulfillment(of: [notified], timeout: 1.0)
        XCTAssertEqual(seen, 42, "onChange carries the new value")
    }

    /// `onChange` fires *after* the write has landed, matching
    /// `UserSettingObserver`: views re-read `viewModel.value` from the callback
    /// rather than trusting the parameter, and must not see the stale value.
    func testOnChangeFiresAfterTheWriteLands() async {
        var backing = 0
        let observer = ClosureSettingObserver<Int>(get: { backing }, set: { backing = $0 })

        let notified = expectation(description: "onChange fires")
        var observedThroughGetter: Int?
        observer.onChange = { _ in
            observedThroughGetter = backing
            notified.fulfill()
        }

        observer.value = 5
        await fulfillment(of: [notified], timeout: 1.0)
        XCTAssertEqual(observedThroughGetter, 5, "the store is current when onChange runs")
    }

    /// The closure-backed ViewModel init produces a row indistinguishable from a
    /// UserSetting-backed one from a view's point of view.
    func testViewModelClosureInitDrivesACheckbox() {
        var backing = false
        let model = ComposableSettings.ViewModel<Bool>(
            title: "Billing enabled",
            get: { backing },
            set: { backing = $0 },
            explanation: "Track time for this repo."
        )
        let checkbox = ComposableSettings.CheckboxView(with: model)

        XCTAssertEqual(checkbox.toggle.state, .off)
        model.settingObserver.value = true
        XCTAssertTrue(backing, "the view model writes through")
    }

    /// The existing UserSetting path still satisfies the protocol, so no call
    /// site changes.
    func testUserSettingObserverConformsAndStillWorks() {
        let setting = UserSetting<Bool>("agentic_toolkit_setting_observing_test", default: false)
        let observer: any SettingObserving<Bool> = UserSettingObserver(setting)
        observer.value = true
        XCTAssertTrue(setting.value)
        setting.value = false
    }
}
