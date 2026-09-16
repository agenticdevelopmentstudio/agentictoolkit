//
//  WindowFooterStatusBarPresenterTests.swift
//  AgenticToolkitMacOSTests
//

import Testing
import AppKit
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// `WindowFooterStatusBarPresenter`, the AppKit conformer for
/// `vscode.window.createStatusBarItem` that renders into
/// `WindowFooterBar.trailingAccessories`.
///
/// `MainThreadWindowStatusBarTests` already pins `vscode.window`'s own
/// contract against a `RecordingStatusBarPresenter` double — it never
/// constructs this type. This suite is the one that drives the real AppKit
/// conformer: a real `WindowFooterBar`, real `NSStackView` arranged
/// subviews, and real `NSAccessibility` identifiers read back off them.
@MainActor
@Suite
struct WindowFooterStatusBarPresenterTests {

    /// A fresh footer plus the container this presenter is documented to own
    /// exactly one of (`extensions.statusbar.container`). Every test reads
    /// through this rather than `footer.trailingAccessories` directly, since
    /// the container is the thing whose `arrangedSubviews` carry the items.
    private func container(in footer: WindowFooterBar) throws -> NSStackView {
        try #require(
            footer.trailingAccessories.first {
                $0.identifier == NSUserInterfaceItemIdentifier("extensions.statusbar.container")
            } as? NSStackView
        )
    }

    /// A minimal request, overriding only what a given test cares about. The
    /// twelve-parameter memberwise initializer has no defaults, so every
    /// suite that builds several requests needs one place that names the
    /// eight fields none of them vary.
    private func request(
        internalID: String,
        id: String = "item",
        alignment: ExtensionStatusBarAlignment = .left,
        priority: Double? = nil,
        text: String = "text",
        command: String? = nil
    ) -> ExtensionStatusBarItemRequest {
        ExtensionStatusBarItemRequest(
            internalID: internalID,
            id: id,
            alignment: alignment,
            priority: priority,
            name: nil,
            text: text,
            tooltip: nil,
            color: nil,
            backgroundColor: nil,
            command: command,
            accessibilityLabel: nil,
            accessibilityRole: nil
        )
    }

    // MARK: - internalID, not id, is the accessibility identity

    /// The behaviour this presenter exists to get right, per its own doc on
    /// `makeItemView`: two items that share the VS Code-visible `id` — which
    /// is exactly what happens when one extension calls
    /// `createStatusBarItem()` twice with no id argument, since `id` then
    /// falls back to the extension identifier for both — must still produce
    /// two views an accessibility client (or a UI test) can address
    /// individually. If the presenter ever keyed the identifier on `id`
    /// instead of `internalID`, this test would see one string twice instead
    /// of two distinct ones.
    @Test("two id-less items from one extension get two distinct accessibility identifiers")
    func twoIDLessItemsGetDistinctAccessibilityIdentifiers() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        // Both requests carry the same VS Code-visible `id` — "ext.status",
        // the shape `createStatusBarItem()` produces with no id argument —
        // but distinct `internalID`s, which is what the adaptor mints per
        // call regardless of what the extension passed.
        presenter.putOrUpdateStatusBarItem(request(internalID: "internal-1", id: "ext.status"))
        presenter.putOrUpdateStatusBarItem(request(internalID: "internal-2", id: "ext.status"))

        let views = try container(in: footer).arrangedSubviews
        try #require(views.count == 2)
        let identifiers = Set(views.map { $0.accessibilityIdentifier() })

        #expect(identifiers == [
            "extensions.statusbar.item.internal-1",
            "extensions.statusbar.item.internal-2"
        ])
    }

    // MARK: - putOrUpdateStatusBarItem

    @Test("putting a new item renders it into the footer's container")
    func puttingANewItemRendersIt() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "a", text: "Hello"))

        let views = try container(in: footer).arrangedSubviews
        #expect(views.count == 1)
        #expect(views.first?.accessibilityIdentifier() == "extensions.statusbar.item.a")
    }

    /// Updating an existing `internalID` reuses the same view rather than
    /// tearing it down and rebuilding it — `render()`'s own doc gives the
    /// reasons (tooltip, cursor rects, accessibility identity all survive a
    /// per-second `item.text = …` write). Pinned here by view identity, not
    /// merely by the text on screen.
    @Test("putting an already-shown item again reuses its view rather than replacing it")
    func puttingAnAlreadyShownItemAgainReusesItsView() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "a", text: "first"))
        let firstView = try #require(try container(in: footer).arrangedSubviews.first)

        presenter.putOrUpdateStatusBarItem(request(internalID: "a", text: "second"))
        let views = try container(in: footer).arrangedSubviews
        #expect(views.count == 1)
        #expect(views.first === firstView)
    }

    // MARK: - removeStatusBarItem

    @Test("removing a shown item takes its view out of the container")
    func removingAShownItemTakesItsViewOut() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "a"))
        presenter.removeStatusBarItem(internalID: "a")

        #expect(try container(in: footer).arrangedSubviews.isEmpty)
    }

    /// The protocol documents this as safe — `removeStatusBarItem` for an id
    /// never shown is a no-op, not a crash or a spurious render. Asserted via
    /// the container not existing at all, since a no-op `render()` would
    /// create it emptily where a genuine change would not (this presenter
    /// only ever appends the container, never removes it).
    @Test("removing an id that was never shown does nothing")
    func removingAnIDNeverShownDoesNothing() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.removeStatusBarItem(internalID: "never-shown")

        #expect(footer.trailingAccessories.isEmpty)
    }

    // MARK: - windowsDidChange

    /// A no-op with nothing up: a footer that has never received an item
    /// gets no container at all from a bare `windowsDidChange()`, matching
    /// the method's own doc ("a new window has nothing to receive").
    @Test("windowsDidChange with nothing shown touches no footer")
    func windowsDidChangeWithNothingShownTouchesNoFooter() {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.windowsDidChange()

        #expect(footer.trailingAccessories.isEmpty)
    }

    /// The behaviour `windowsDidChange`'s doc calls out by name: a window
    /// that opens *after* the last `putOrUpdateStatusBarItem` call has never
    /// been rendered into, so without this method being called on it, it
    /// shows nothing. Modeled here by handing the presenter a `footers`
    /// closure whose second window arrives only after an item is already up.
    @Test("windowsDidChange renders already-shown items into a window opened afterward")
    func windowsDidChangeRendersIntoAWindowOpenedAfterward() throws {
        let firstFooter = WindowFooterBar(accessibilityPrefix: "first")
        var footers: [WindowFooterBar] = [firstFooter]
        let presenter = WindowFooterStatusBarPresenter(footers: { footers }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "a"))

        let secondFooter = WindowFooterBar(accessibilityPrefix: "second")
        footers.append(secondFooter)
        #expect(secondFooter.trailingAccessories.isEmpty)

        presenter.windowsDidChange()

        #expect(try !container(in: secondFooter).arrangedSubviews.isEmpty)
    }

    // MARK: - Ordering

    /// Left-aligned items before right-aligned ones, regardless of the order
    /// they were put up in — the presenter's only substitute for VS Code's
    /// two physically separate slots, per the type's own "One slot, two
    /// alignments" doc.
    @Test("left-aligned items render before right-aligned ones")
    func leftAlignedItemsRenderBeforeRightAlignedOnes() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        // Put the right-aligned item up first, so a presenter that merely
        // preserved insertion order would get this wrong.
        presenter.putOrUpdateStatusBarItem(request(internalID: "right", alignment: .right))
        presenter.putOrUpdateStatusBarItem(request(internalID: "left", alignment: .left))

        let ids = try container(in: footer).arrangedSubviews.map { $0.accessibilityIdentifier() }
        #expect(ids == [
            "extensions.statusbar.item.left",
            "extensions.statusbar.item.right"
        ])
    }

    /// Within one alignment group, higher priority renders first.
    @Test("within an alignment, higher priority renders first")
    func withinAnAlignmentHigherPriorityRendersFirst() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "low", priority: 1))
        presenter.putOrUpdateStatusBarItem(request(internalID: "high", priority: 5))

        let ids = try container(in: footer).arrangedSubviews.map { $0.accessibilityIdentifier() }
        #expect(ids == [
            "extensions.statusbar.item.high",
            "extensions.statusbar.item.low"
        ])
    }

    /// `nil` priority must sort last, never as though it were `0` — Ruling 8
    /// of task 5.5c, quoted in `orderedItems`'s own doc. An item with
    /// `priority: -5` genuinely asked to be ranked below zero, so it must
    /// still out-rank an item that asked for no priority at all.
    @Test("an item with no priority sorts after one with a negative priority")
    func noPrioritySortsAfterANegativePriority() throws {
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(footers: { [footer] }, onCommand: { _ in })

        presenter.putOrUpdateStatusBarItem(request(internalID: "none", priority: nil))
        presenter.putOrUpdateStatusBarItem(request(internalID: "negative", priority: -5))

        let ids = try container(in: footer).arrangedSubviews.map { $0.accessibilityIdentifier() }
        #expect(ids == [
            "extensions.statusbar.item.negative",
            "extensions.statusbar.item.none"
        ])
    }

    // MARK: - Click routing

    /// `StatusItemView` is private, so this suite can only reach it as the
    /// plain `NSView` `container(in:)` returns — but `mouseDown(with:)` is an
    /// `override` of an AppKit selector, so Objective-C message dispatch
    /// still finds the private override at runtime even though Swift's own
    /// name lookup cannot see the subclass. This is what actually pins the
    /// click route: a click on the rendered view reaches the exact
    /// `onCommand` closure the presenter was constructed with, carrying the
    /// request's `command` string unchanged.
    @Test("clicking a rendered item with a command runs onCommand with that command")
    func clickingARenderedItemWithACommandRunsOnCommand() throws {
        var received: [String] = []
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(
            footers: { [footer] },
            onCommand: { received.append($0) }
        )

        presenter.putOrUpdateStatusBarItem(request(internalID: "a", command: "ext.doThing"))
        let view = try #require(container(in: footer).arrangedSubviews.first)

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDown(with: event)

        #expect(received == ["ext.doThing"])
    }

    /// An item with no `command` never reaches `onCommand` at all — the view
    /// falls back to `super.mouseDown`, which is AppKit's own no-op default
    /// for a plain `NSView`.
    @Test("clicking a rendered item with no command does not call onCommand")
    func clickingARenderedItemWithNoCommandDoesNotCallOnCommand() throws {
        var received: [String] = []
        let footer = WindowFooterBar(accessibilityPrefix: "test")
        let presenter = WindowFooterStatusBarPresenter(
            footers: { [footer] },
            onCommand: { received.append($0) }
        )

        presenter.putOrUpdateStatusBarItem(request(internalID: "a", command: nil))
        let view = try #require(container(in: footer).arrangedSubviews.first)

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        view.mouseDown(with: event)

        #expect(received.isEmpty)
    }
}
