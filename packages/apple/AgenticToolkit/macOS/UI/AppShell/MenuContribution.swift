import AppKit
import OSLog
import AgenticToolkitCore

/// One menu item a feature wants the host's `MenuManager` to install.
/// Coordinators return `[MenuContribution]` from `menuContributions()`;
/// `MenuManager` collects them, sorts by slot+order, and builds the
/// AppKit `NSMenuItem` hierarchy with closure-based actions (no
/// per-item `target`/`#selector` boilerplate on the part of the
/// contributor).
public struct MenuContribution {

    /// Where in the menu hierarchy the item belongs.
    public enum Slot: Hashable, Sendable {
        /// App menu (Whippet menu) — typically About / Settings… / Quit.
        case app
        /// File menu — typically New / Open / Close / Save.
        case file
        /// View menu — typically Toggle Sidebar / Enter Full Screen.
        case view
        /// Window menu — typically Minimize / Zoom / Bring All to Front +
        /// app-specific window pickers.
        case window
        /// Status-item dropdown. The `section` integer groups items between
        /// separators (lower = higher in the menu).
        case statusItem(section: Int)
    }

    public let slot: Slot
    public let title: String
    /// Sort key within the slot (and within the section for `.statusItem`).
    /// Lower comes first.
    public let order: Int
    /// Key equivalent (e.g. `"t"`) or empty string for none.
    public let key: String
    /// Modifier mask. Default `.command`.
    public let modifiers: NSEvent.ModifierFlags
    /// Optional dynamic enable check. Default always-enabled.
    public let isEnabled: () -> Bool
    /// Optional dynamic visibility check, evaluated when the menu opens.
    /// `nil` — the default — means always visible, and is distinct from a
    /// closure returning `false`: only a contribution that actually asks for
    /// dynamic visibility makes the host install a menu delegate.
    ///
    /// Use this only when the item is *meaningless* right now (a Scan item
    /// during a scan); an item that is merely unavailable should stay visible
    /// and disable itself, so the menu does not reshuffle under the pointer
    /// (`principle-of-least-astonishment`).
    public let isHidden: (() -> Bool)?
    /// What to do when the user activates the item.
    public let action: () -> Void

    public init(
        slot: Slot,
        title: String,
        order: Int = 0,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        isEnabled: @escaping () -> Bool = { true },
        isHidden: (() -> Bool)? = nil,
        action: @escaping () -> Void
    ) {
        self.slot = slot
        self.title = title
        self.order = order
        self.key = key
        self.modifiers = modifiers
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.action = action
    }

    /// Build a menu item that runs a **registered command** instead of a
    /// closure written inline here. Additive: the closure initializer above is
    /// untouched and every existing call site keeps compiling.
    ///
    /// `action` and `isEnabled` are synthesized rather than stored as a
    /// `commandID`, so `MenuManager` needs no change at all — it still reads
    /// `contribution.action` / `contribution.isEnabled` and hands them to
    /// `ClosureMenuItemTarget` exactly as before. The lookup is deliberately
    /// *late*: both closures ask the registry each time they run, so a menu
    /// item built before its command is registered still works, and a command
    /// replaced later (an extension reloading, in Stage 5) takes effect without
    /// rebuilding the menu.
    ///
    /// An id nothing has registered makes the item disabled, never
    /// silently-inert-but-enabled — `CommandRegistry.isEnabled(id:)` answers
    /// `false` for an unknown id.
    ///
    /// ## Why this is main-actor-safe
    ///
    /// `action` and `isEnabled` are plain `() -> Void` / `() -> Bool` — neither
    /// `@Sendable` nor `@MainActor` — while `CommandRegistry` is `@MainActor`.
    /// Under `SWIFT_STRICT_CONCURRENCY: complete` the guarantee that makes the
    /// registry calls below legal is **closure isolation inheritance**: this
    /// initializer is `@MainActor`, and a non-`@Sendable` closure literal formed
    /// inside an actor-isolated context is itself isolated to that actor. So
    /// both closures are statically main-actor-isolated at the point they are
    /// written — no `MainActor.assumeIsolated`, no `Task` hop, and no dynamic
    /// check that could trap at runtime.
    ///
    /// That isolation cannot be lost afterwards, which is the other half of the
    /// argument: because the closure types are non-`@Sendable` (and
    /// `MenuContribution` is itself non-`Sendable`), the compiler will not let
    /// either value cross into a different isolation domain, so there is no
    /// path by which they could be called off the main actor. It is the same
    /// guarantee the existing closure call sites already rely on — every
    /// coordinator forms its `action` inside a `@MainActor` `init` and calls
    /// `@MainActor` methods from it — and the consumer end matches: the only
    /// caller of `action` is `@MainActor ClosureMenuItemTarget
    /// .performMenuAction(_:)`, and of `isEnabled`, its `validateMenuItem(_:)`.
    ///
    /// - Parameters:
    ///   - commandID: The id to dispatch through `registry`.
    ///   - registry: The registry to look `commandID` up in. Captured strongly:
    ///     a menu lives as long as the app, and a registry the menu could
    ///     outlive would turn every item into a no-op.
    @MainActor
    public init(
        slot: Slot,
        title: String,
        commandID: String,
        registry: CommandRegistry,
        order: Int = 0,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        isHidden: (() -> Bool)? = nil
    ) {
        self.slot = slot
        self.title = title
        self.order = order
        self.key = key
        self.modifiers = modifiers
        self.isHidden = isHidden
        self.isEnabled = { registry.isEnabled(id: commandID) }
        self.action = {
            do {
                try registry.execute(id: commandID)
            } catch {
                // Reachable only if AppKit fires an item its own
                // `validateMenuItem(_:)` said was disabled, or if the id was
                // never registered. Neither is recoverable here and neither
                // should pass unnoticed, so it is logged rather than swallowed;
                // `execute` itself still throws for callers that can react.
                let reason = String(describing: error)
                MenuContribution.logger.error(
                    "Menu item '\(title, privacy: .public)' failed: \(reason, privacy: .public)"
                )
            }
        }
    }
}

extension MenuContribution: Loggable {
    public static nonisolated let logger = makeLogger()
}
