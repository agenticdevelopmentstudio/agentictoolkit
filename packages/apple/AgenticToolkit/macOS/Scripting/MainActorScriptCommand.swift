import AppKit
import Foundation

/// Base class for `NSScriptCommand` subclasses that need to run on the main
/// actor — which is nearly all of them, since they typically touch AppKit
/// state (windows, view controllers, etc.).
///
/// AppleScript dispatches commands on an arbitrary thread, so subclasses
/// would otherwise need to paper over the Sendable gap manually with
/// `@unchecked Sendable` + `MainActor.assumeIsolated { ... }` on every
/// command. This base absorbs that boilerplate: subclasses override the
/// `@MainActor` `performMain()` method and return the same type they'd
/// return from `performDefaultImplementation()`.
///
/// Example:
/// ```swift
/// @objc(StenographerOpenSettingsCommand)
/// public final class StenographerOpenSettingsCommand: MainActorScriptCommand {
///     public override func performMain() -> Any? {
///         SettingsWindowController.present(...)
///         return SettingsWindowController.current != nil
///     }
/// }
/// ```
///
/// The assumption-of-isolation is safe because Cocoa Scripting always
/// invokes command handlers via `NSScriptCommand.performDefaultImplementation`
/// on the main thread when the script suite is registered in a `.app`'s
/// `Info.plist`. The `@unchecked Sendable` is required because
/// `NSScriptCommand` itself carries mutable state and isn't marked Sendable.
open class MainActorScriptCommand: NSScriptCommand, @unchecked Sendable {

    /// Override this to implement the command. Runs on the main actor.
    /// Default implementation returns `nil`.
    @MainActor
    open func performMain() -> Any? { nil }

    public override func performDefaultImplementation() -> Any? {
        // Cocoa Scripting invokes this on the main thread, so hopping onto
        // the main actor here is a no-op at runtime. The Box pattern is
        // the codebase's standard escape hatch for `MainActor.assumeIsolated`
        // bridging — its `sending` closure rejects captures of a non-final
        // `@unchecked Sendable` self under Swift 6 region analysis, but
        // capturing a `final class @unchecked Sendable` Box that holds self
        // is fine. The Box also carries the result back, since `Any?`
        // doesn't satisfy `assumeIsolated`'s `T: Sendable` requirement.
        final class Box: @unchecked Sendable {
            let cmd: MainActorScriptCommand
            var result: Any?
            init(_ cmd: MainActorScriptCommand) { self.cmd = cmd }
        }
        let box = Box(self)
        MainActor.assumeIsolated {
            box.result = box.cmd.performMain()
        }
        return box.result
    }
}

/// The specifier for an element hanging directly off `application`, built off
/// the main actor.
///
/// AppKit asks for `objectSpecifier` from non-isolated dispatch while
/// everything it needs is main-thread state, and `NSScriptObjectSpecifier` is
/// not `Sendable` — so the answer comes back in a Box. Every scriptable wrapper
/// in this framework needs exactly that, which is why it is written once here
/// rather than a fifth time in the next wrapper.
///
/// - Parameters:
///   - key: the `application` element key the `.sdef` declares — `"panes"`,
///     `"projectTabs"`, `"projectWindows"`, `"terminalSessions"`.
///   - uniqueID: read on the main actor, because every wrapper's id is.
public func applicationElementSpecifier(
    key: String,
    uniqueID: @escaping @MainActor () -> String
) -> NSScriptObjectSpecifier? {
    // The Box carries the closure across as well as the result: this file's
    // own `performDefaultImplementation` explains why `assumeIsolated`'s
    // `sending` closure wants everything it touches inside one.
    final class Box: @unchecked Sendable {
        let key: String
        let uniqueID: @MainActor () -> String
        var value: NSScriptObjectSpecifier?
        init(key: String, uniqueID: @escaping @MainActor () -> String) {
            self.key = key
            self.uniqueID = uniqueID
        }
    }
    let box = Box(key: key, uniqueID: uniqueID)
    MainActor.assumeIsolated {
        guard let appDescription = NSApp.classDescription as? NSScriptClassDescription else { return }
        box.value = NSUniqueIDSpecifier(
            containerClassDescription: appDescription,
            containerSpecifier: nil,
            key: box.key,
            uniqueID: box.uniqueID())
    }
    return box.value
}
