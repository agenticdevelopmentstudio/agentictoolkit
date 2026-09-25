import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

final class AccountMenuModelTests: XCTestCase {
    func testAvatarLabelPrefersDisplayName() {
        let model = AccountMenuModel(
            user: HubUser(id: "u1", email: "ada@example.com", name: "Ada Byron", slug: "ada", avatarURL: nil)
        )
        XCTAssertEqual(model.avatarLabel, "Ada Byron")
        XCTAssertEqual(model.initials, "AB")
    }

    func testAvatarLabelFallsBackToSlugThenEmailLocalPart() {
        XCTAssertEqual(AccountMenuModel.avatarLabel(name: "  ", slug: "ada", email: "ada@example.com"), "ada")
        XCTAssertEqual(AccountMenuModel.avatarLabel(name: "", slug: nil, email: "ada@example.com"), "ada")
        XCTAssertEqual(AccountMenuModel.avatarLabel(name: "", slug: "", email: "no-at-sign"), "no-at-sign")
    }

    func testMenuItemsInSpecOrder() {
        let model = AccountMenuModel(user: HubUser(id: "u1", email: "a@b.c", name: "A", slug: nil, avatarURL: nil))
        XCTAssertEqual(model.items, [.home, .profile, .settings, .logOut])
        XCTAssertEqual(model.items.map(\.label), ["Home", "Profile", "Settings", "Log out"])
    }
}
