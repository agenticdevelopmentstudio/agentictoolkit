import AppKit
import Testing
@testable import AgenticToolkitMacOS

/// Pins `NewItemRegistry`'s resolution rules (task-9): nobody claiming
/// resolves to `nil`, a lone claimant wins regardless of priority, two
/// claimants resolve by the higher `priority`, and a non-claimant is skipped
/// even when its priority would otherwise win. `claimsKeyWindow` is
/// injectable specifically so these can be asserted with no real window.
@Suite("NewItemRegistry")
@MainActor
struct NewItemRegistryTests {

    private func provider(
        priority: Int = 0,
        claims: Bool,
        title: String
    ) -> NewItemProvider {
        NewItemProvider(
            priority: priority,
            claimsKeyWindow: { claims },
            title: { title },
            action: {}
        )
    }

    @Test("No providers resolves to nil")
    func noProvidersResolvesToNil() {
        #expect(NewItemRegistry.resolve([]) == nil)
    }

    @Test("No claimant resolves to nil")
    func noClaimantResolvesToNil() {
        let providers = [
            provider(claims: false, title: "New Terminal Session"),
            provider(claims: false, title: "New Note")
        ]
        #expect(NewItemRegistry.resolve(providers) == nil)
    }

    @Test("A single claimant wins")
    func singleClaimantWins() {
        let providers = [
            provider(claims: false, title: "New Terminal Session"),
            provider(claims: true, title: "New Note")
        ]
        #expect(NewItemRegistry.resolve(providers)?.title() == "New Note")
    }

    @Test("Two claimants resolve by the higher priority")
    func twoClaimantsResolveByPriority() {
        let providers = [
            provider(priority: 0, claims: true, title: "New Terminal Session"),
            provider(priority: 10, claims: true, title: "New Note")
        ]
        #expect(NewItemRegistry.resolve(providers)?.title() == "New Note")
    }

    @Test("A non-claimant is skipped even at higher priority")
    func nonClaimantSkippedEvenAtHigherPriority() {
        let providers = [
            provider(priority: 100, claims: false, title: "New Terminal Session"),
            provider(priority: 0, claims: true, title: "New Note")
        ]
        #expect(NewItemRegistry.resolve(providers)?.title() == "New Note")
    }

    @Test("The resolved title is the provider's own")
    func resolvedTitleIsTheProvidersOwn() {
        let providers = [provider(claims: true, title: "New Folder")]
        #expect(NewItemRegistry.resolve(providers)?.title() == "New Folder")
    }
}

/// Pins the retitle sweep `MenuUpdateDelegate` adds beside its existing
/// visibility rules (task-9-grounding G13, Ruling 48): `menuNeedsUpdate(_:)`
/// applies the current title on every open, and a delegate holding only a
/// retitle still reports non-empty — the assertion that catches `isEmpty`
/// regressing to `rules.isEmpty` alone, which would stop `MenuManager` from
/// ever installing a retitle-only delegate (`:216-220` installs only when
/// `!isEmpty`, and `NSMenu.delegate` is weak).
@Suite("MenuUpdateDelegate retitling")
@MainActor
struct MenuUpdateDelegateRetitleTests {

    @Test("menuNeedsUpdate applies the current title")
    func menuNeedsUpdateAppliesTheCurrentTitle() {
        let delegate = MenuUpdateDelegate()
        let item = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
        var currentTitle = "New Note"
        delegate.addRetitle(item, title: { currentTitle })

        delegate.menuNeedsUpdate(NSMenu())
        #expect(item.title == "New Note")

        currentTitle = "New Terminal Session"
        delegate.menuNeedsUpdate(NSMenu())
        #expect(item.title == "New Terminal Session")
    }

    @Test("A delegate holding only a retitle reports isEmpty == false")
    func retitleOnlyDelegateIsNotEmpty() {
        let delegate = MenuUpdateDelegate()
        #expect(delegate.isEmpty)

        delegate.addRetitle(NSMenuItem(title: "New", action: nil, keyEquivalent: "")) { "New Note" }
        #expect(!delegate.isEmpty)
    }
}
