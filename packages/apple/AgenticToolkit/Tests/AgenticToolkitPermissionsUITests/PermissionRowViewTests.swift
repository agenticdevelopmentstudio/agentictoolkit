import AppKit
import Testing
import AgenticToolkitPermissions
@testable import AgenticToolkitPermissionsUI

private struct StubChecker: PermissionChecking {
    let result: PermissionStatus
    func status(_ permission: Permission) async -> PermissionStatus { result }
    func request(_ permission: Permission) async -> PermissionStatus { result }
}

@MainActor
@Suite("Permission row view")
struct PermissionRowViewTests {
    private func row(_ status: PermissionStatus) -> PermissionRowView {
        PermissionRowView(permission: .accessibility, checker: StubChecker(result: status), onAction: { _ in })
    }

    @Test("row shows Granted when the checker reports granted")
    func showsGranted() async {
        let row = row(.granted)
        await row.refresh()
        #expect(row.statusText == "Granted")
    }

    @Test("row shows Not Granted when the checker reports denied")
    func showsDenied() async {
        let row = row(.denied)
        await row.refresh()
        #expect(row.statusText == "Not Granted")
    }

    @Test("row shows Unknown when the status is undetermined")
    func showsUndetermined() async {
        let row = row(.undetermined)
        await row.refresh()
        #expect(row.statusText == "Unknown")
    }

    @Test("a granted row offers to revoke instead of to open settings")
    func grantedOffersRevoke() async {
        let row = row(.granted)
        await row.refresh()
        #expect(row.actionTitle == "Revoke")
    }

    @Test("a row that is not granted offers to open settings")
    func ungrantedOffersOpenSettings() async {
        for status in [PermissionStatus.denied, .undetermined] {
            let row = row(status)
            await row.refresh()
            #expect(row.actionTitle == "Open Settings")
        }
    }
}
