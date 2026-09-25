import AgenticDeveloperHubClient
import XCTest
@testable import AgenticToolkitHubService

final class HubUserTests: XCTestCase {
    func testMapsGeneratedUserAndDropsEmptyAvatar() {
        let generated = Components.Schemas.User(
            id: "u1", email: "ada@example.com", name: "Ada Byron", avatarUrl: "",
            slug: "ada", publicProfileEnabled: true, profileVisibility: .hub, capabilities: ["x"]
        )
        let user = HubUser(generated)
        let expected = HubUser(id: "u1", email: "ada@example.com", name: "Ada Byron", slug: "ada", avatarURL: nil)
        XCTAssertEqual(user, expected)
    }

    func testKeepsAValidAvatarURL() {
        let generated = Components.Schemas.User(
            id: "u1", email: "ada@example.com", name: "Ada", avatarUrl: "https://cdn.example.com/a.png",
            slug: nil, publicProfileEnabled: false, profileVisibility: ._private, capabilities: []
        )
        XCTAssertEqual(HubUser(generated).avatarURL, URL(string: "https://cdn.example.com/a.png"))
    }

    func testDisplayLabelAndInitials() {
        let byron = HubUser(id: "1", email: "ada@example.com", name: "Ada Byron", slug: nil, avatarURL: nil)
        XCTAssertEqual(byron.initials, "AB")
        let lowercased = HubUser(id: "1", email: "ada@example.com", name: "ada", slug: nil, avatarURL: nil)
        XCTAssertEqual(lowercased.initials, "A")
        let blank = HubUser(id: "1", email: "zed@example.com", name: "  ", slug: nil, avatarURL: nil)
        XCTAssertEqual(blank.displayLabel, "zed@example.com")
        XCTAssertEqual(blank.initials, "Z")
    }

    func testCachedUserStoreRoundTrips() {
        let isolated = IsolatedDefaults()
        defer { isolated.tearDown() }
        let store = CachedUserStore(defaults: isolated.defaults)
        XCTAssertNil(store.load())
        let user = HubUser(id: "u1", email: "a@b.c", name: "A", slug: "a", avatarURL: URL(string: "https://x.y/a.png"))
        store.save(user)
        XCTAssertEqual(store.load(), user)
        XCTAssertNotNil(isolated.defaults.data(forKey: CachedUserStore.key))
        store.clear()
        XCTAssertNil(store.load())
    }
}
