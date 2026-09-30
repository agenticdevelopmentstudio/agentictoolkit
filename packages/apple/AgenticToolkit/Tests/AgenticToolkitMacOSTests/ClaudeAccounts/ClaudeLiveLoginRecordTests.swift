import AgenticToolkitCore
@testable import AgenticToolkitMacOS
import XCTest

/// Which saved record is the live account's — the one whose refresh token is
/// Claude Code's to spend, and the one a switch away must bring up to date.
final class ClaudeLiveLoginRecordTests: XCTestCase {

    private func located(
        _ name: String, _ kind: ClaudeCredentialKind, identity: String = ""
    ) -> ClaudeAccountKeychainStore.Located {
        let account = ClaudeSavedAccount(name: name, kind: kind, identity: identity)
        return .init(account: account, location: .login, itemKey: account.itemKey)
    }

    func testTheLoginFiledUnderTheLiveNameIsTheLiveRecord() {
        let records = [located("a@x.com", .oauth), located("b@x.com", .oauth)]
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "u")
        XCTAssertEqual(
            ClaudeAccountKeychainStore.savedLogin(for: live, in: records)?.account.name, "b@x.com")
    }

    func testASetupTokenUnderTheSameNameIsNeverTheLiveRecord() {
        // A setup token is never refreshed and never installed — syncing the
        // live login into it would turn it into a second login record.
        let records = [located("b@x.com", .longLived), located("b@x.com", .oauth)]
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "u")
        XCTAssertEqual(
            ClaudeAccountKeychainStore.savedLogin(for: live, in: records)?.account.kind, .oauth)
    }

    func testARecordRenamedByTheUserIsFoundByTheEmailItWasCapturedFrom() {
        let records = [located("work", .oauth, identity: "b@x.com")]
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "u")
        XCTAssertEqual(
            ClaudeAccountKeychainStore.savedLogin(for: live, in: records)?.account.name, "work")
    }

    func testNoLoginMeansNoLiveRecord() {
        let records = [located("", .oauth)]
        XCTAssertNil(ClaudeAccountKeychainStore.savedLogin(for: ClaudeLoginIdentity(), in: records))
    }

    func testTheLiveRecordIsMatchedIgnoringCase() {
        let records = [located("B@X.com", .oauth)]
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "")
        XCTAssertEqual(
            ClaudeAccountKeychainStore.savedLogin(for: live, in: records)?.account.name, "B@X.com")
    }

    func testTheUuidOutranksAStaleRecordSharingTheName() {
        // An email reassigned to a new account: the old record still carries the
        // name, but only the one with the live uuid is this login.
        var stale = ClaudeSavedAccount(name: "b@x.com", kind: .oauth, identity: "b@x.com")
        stale.accountUUID = "old"
        var current = ClaudeSavedAccount(name: "work", kind: .oauth, identity: "b@x.com")
        current.accountUUID = "new"
        let records = [stale, current].map {
            ClaudeAccountKeychainStore.Located(account: $0, location: .login, itemKey: $0.itemKey)
        }
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "new")
        XCTAssertEqual(
            ClaudeAccountKeychainStore.savedLogin(for: live, in: records)?.account.name, "work")
    }

    // MARK: - Live against saved

    private func login(
        _ name: String, refresh: String, expiresAt: Double?
    ) -> ClaudeAccountKeychainStore.Located {
        var account = ClaudeSavedAccount(name: name, kind: .oauth)
        account.oauth = ClaudeOAuthCredential(
            accessToken: "a-\(refresh)", refreshToken: refresh, expiresAt: expiresAt)
        return .init(account: account, location: .shared, itemKey: account.itemKey)
    }

    private func standing(
        _ live: ClaudeOAuthCredential, _ saved: ClaudeAccountKeychainStore.Located,
        _ others: [ClaudeAccountKeychainStore.Located] = []
    ) -> ClaudeAccountKeychainStore.LiveLoginStanding {
        ClaudeAccountKeychainStore.standing(of: live, against: saved, among: [saved] + others)
    }

    func testTheSamePairNeedsNothing() {
        let saved = login("a@x.com", refresh: "r1", expiresAt: 1000)
        XCTAssertEqual(standing(saved.account.oauth!, saved), .same)
    }

    func testANewerLivePairIsFiledOverTheSavedCopy() {
        let saved = login("a@x.com", refresh: "r1", expiresAt: 1000)
        let live = ClaudeOAuthCredential(accessToken: "a2", refreshToken: "r2", expiresAt: 2000)
        XCTAssertEqual(standing(live, saved), .liveNewer)
    }

    /// Another Mac refreshed the shared iCloud record, which voided the pair
    /// Claude Code holds here — copying that dead pair back would kill it
    /// everywhere.
    func testANewerSavedCopyIsNeverOverwrittenByAnOlderLivePair() {
        let saved = login("a@x.com", refresh: "r2", expiresAt: 2000)
        let live = ClaudeOAuthCredential(accessToken: "a1", refreshToken: "r1", expiresAt: 1000)
        XCTAssertEqual(standing(live, saved), .savedNewer)
    }

    func testAnUnknownExpiryKeepsTheLivePair() {
        let saved = login("a@x.com", refresh: "r2", expiresAt: nil)
        let live = ClaudeOAuthCredential(accessToken: "a1", refreshToken: "r1", expiresAt: 1000)
        XCTAssertEqual(standing(live, saved), .liveNewer)
    }

    /// `~/.claude.json` still names the old account while Claude Code's item
    /// already holds another's login — filing it would overwrite one account's
    /// record with the other's credential.
    func testALivePairAnotherRecordHoldsIsNeverFiled() {
        let saved = login("a@x.com", refresh: "r1", expiresAt: 1000)
        let other = login("b@x.com", refresh: "rb", expiresAt: 1500)
        let live = ClaudeOAuthCredential(accessToken: "ab", refreshToken: "rb", expiresAt: 3000)
        XCTAssertEqual(standing(live, saved, [other]), .foreign)
    }

    func testAnAccountThatWasNeverSavedHasNoLiveRecord() {
        // The sync updates an existing record only; saving is autosave's call.
        let records = [located("a@x.com", .oauth)]
        let live = ClaudeLoginIdentity(email: "b@x.com", uuid: "u")
        XCTAssertNil(ClaudeAccountKeychainStore.savedLogin(for: live, in: records))
    }
}
