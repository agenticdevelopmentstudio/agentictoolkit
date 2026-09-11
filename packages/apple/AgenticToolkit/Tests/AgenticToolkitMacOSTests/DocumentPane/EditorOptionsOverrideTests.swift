import XCTest
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

@MainActor
final class EditorOptionsOverrideTests: XCTestCase {

    func testAnUntouchedPaneFollowsTheGlobalSetting() {
        let override = EditorOptionsOverride(store: EphemeralPaneStateStore())
        XCTAssertFalse(override.isOverridden)
        XCTAssertEqual(override.showLineNumbers, UserSettings.editorShowLineNumbers.value)
        XCTAssertEqual(override.showOverview, UserSettings.editorShowOverview.value)
        XCTAssertEqual(override.showInvisibles, UserSettings.editorShowInvisibles.value)
    }

    func testSettingOneOptionPinsOnlyThatOption() {
        let override = EditorOptionsOverride(store: EphemeralPaneStateStore())
        let globalOverview = override.showOverview

        override.setShowLineNumbers(!UserSettings.editorShowLineNumbers.value)

        XCTAssertTrue(override.isOverridden)
        XCTAssertEqual(override.showLineNumbers, !UserSettings.editorShowLineNumbers.value)
        XCTAssertEqual(override.showOverview, globalOverview, "an unset option keeps following the global")
    }

    func testResetDeletesTheStoredRowRatherThanFreezingTheCurrentGlobal() {
        let store = EphemeralPaneStateStore()
        let override = EditorOptionsOverride(store: store)
        override.setShowInvisibles(true)
        override.flushPendingPersist()
        XCTAssertNotNil(store.paneStateValue(forKey: EditorOptionsOverride.stateKey))

        override.reset()

        XCTAssertFalse(override.isOverridden)
        XCTAssertNil(store.paneStateValue(forKey: EditorOptionsOverride.stateKey),
                     "reset must delete the row so the pane follows the app again")
    }

    func testAStoredOverrideIsReadBackByASecondInstanceOnTheSameStore() {
        let store = EphemeralPaneStateStore()
        let first = EditorOptionsOverride(store: store)
        first.setShowOverview(false)
        first.flushPendingPersist()

        let second = EditorOptionsOverride(store: store)

        XCTAssertTrue(second.isOverridden)
        XCTAssertFalse(second.showOverview)
    }

    func testAnUnparseableRowIsReadAsNoOverride() {
        let store = EphemeralPaneStateStore()
        store.setPaneStateValue("{not json", forKey: EditorOptionsOverride.stateKey)

        let override = EditorOptionsOverride(store: store)

        XCTAssertFalse(override.isOverridden)
    }

    func testChangingTheGlobalNotifiesAnUnpinnedPane() {
        let override = EditorOptionsOverride(store: EphemeralPaneStateStore())
        var notifications = 0
        override.onChange = { notifications += 1 }

        UserSettings.editorShowInvisibles.value.toggle()
        defer { UserSettings.editorShowInvisibles.value.toggle() }

        XCTAssertGreaterThan(notifications, 0)
    }
}
