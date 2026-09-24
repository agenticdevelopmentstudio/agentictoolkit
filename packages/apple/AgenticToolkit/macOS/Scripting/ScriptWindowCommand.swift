import AppKit
import Foundation

/// Base class for commands that take a text or window-name argument.
///
/// Every refusal sets a real `NSScriptCommand` error rather than returning a
/// quiet `false`: a script that misspelled a window name and got `false` back
/// would read it as "that window is closed" and carry on.
open class ScriptWindowCommand: MainActorScriptCommand, @unchecked Sendable {

    /// The direct parameter as a trimmed, non-empty string.
    public func requireText() -> String? {
        guard let text = directParameter as? String else {
            fail(NSArgumentsWrongScriptError, "This command takes a text argument.")
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fail(NSArgumentsWrongScriptError, "This command's text argument must not be empty.")
            return nil
        }
        return trimmed
    }

    /// The direct parameter as a registered window.
    ///
    /// - Parameter defaultingToFirst: whether a missing parameter means the
    ///   first registered window. True only for commands whose sdef marks the
    ///   window parameter optional.
    @MainActor
    public func requireWindow(defaultingToFirst: Bool = false) -> ScriptWindow? {
        if directParameter == nil && defaultingToFirst {
            guard let first = ScriptWindows.first else {
                fail(NSInternalScriptError, "No windows are registered for scripting.")
                return nil
            }
            return first
        }
        guard let entry = ScriptWindows.named(directParameter) else {
            let known = ScriptWindows.names.joined(separator: ", ")
            fail(NSArgumentsWrongScriptError, "Unknown window name. Known windows: \(known).")
            return nil
        }
        return entry
    }

    public func fail(_ number: Int, _ message: String) {
        scriptErrorNumber = number
        scriptErrorString = message
    }
}
