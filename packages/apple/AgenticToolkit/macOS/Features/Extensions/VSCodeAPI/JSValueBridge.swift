//
//  JSValueBridge.swift
//  AgenticToolkit
//

import Foundation
import JavaScriptCore

/// The handful of one-line `JSValue` constructions every `MainThread*`
/// adaptor needs, in one place.
///
/// Each of these existed two or three times over — `MainThreadWindow`,
/// `MainThreadWorkspace`, `MainThreadDiagnostics` and
/// `MainThreadLanguageModels` each grew its own `private static` copy, and two
/// of them documented themselves as copies of a third ("this is a copy, not a
/// shared helper", "licensed as a third independent copy"). That reasoning was
/// sound about the *access control* — a `private static` member is unreachable
/// from a sibling file even inside one module — and wrong about the remedy: the
/// fix for an unreachable helper is to give it a reachable home, not to write
/// it again. This is that home.
///
/// **Two return shapes, deliberately.** A promise settlement takes `Any` and
/// cannot be handed `nil`, so those builders fall back to `NSNull()`: settling
/// with *something* keeps an extension's `await` from hanging forever on a
/// failure it cannot see. A synchronous member result is a `JSValue?` and
/// answering `nil` is a legitimate answer, so those builders return the
/// optional unwidened. Both spellings are here rather than one, because
/// collapsing them would force every synchronous call site to widen to `Any`
/// and then narrow again.
///
/// Not an actor-isolated type and not a protocol: every member is a pure
/// function of its arguments, so there is nothing to isolate and nothing to
/// substitute.
enum JSValueBridge {

    // MARK: - Values

    /// A genuine JavaScript `undefined`, or `nil` if the bridge cannot build
    /// one — for a synchronous member result, where `nil` is answerable.
    static func undefined(in context: JSContext) -> JSValue? {
        JSValue(undefinedIn: context)
    }

    /// A genuine JavaScript `undefined`, falling back to `NSNull` —
    /// JavaScript `null` — if `JSValue(undefinedIn:)` itself fails to answer,
    /// which nothing observed while building these adaptors ever caused. For a
    /// promise settlement, which has no way to say `nil`.
    static func undefinedOrNull(in context: JSContext) -> Any {
        JSValue(undefinedIn: context) ?? NSNull()
    }

    /// A JavaScript array holding `values`, or `nil` if the bridge cannot
    /// build one — the `JSValue?` shape, for a synchronous member result.
    ///
    /// `JSValue(object:in:)` bridges a *new* JS array on every call, so
    /// mutating one call's result never affects the next.
    static func array(of values: [JSValue], in context: JSContext) -> JSValue? {
        JSValue(object: values, in: context)
    }

    /// A JavaScript array holding `values`, falling back to `NSNull()` —
    /// the `Any` shape, for a promise settlement. See `undefinedOrNull(in:)`
    /// for why the fallback is a value rather than nothing.
    static func arrayOrNull(of values: [JSValue], in context: JSContext) -> Any {
        JSValue(object: values, in: context) ?? NSNull()
    }

    /// A JavaScript string holding `value`, built fresh in `context`, falling
    /// back to `NSNull()` for the same reason `arrayOrNull(of:in:)` does.
    ///
    /// Used both to settle a promise with an accepted answer — including the
    /// empty string — and to build an argument to an extension's own callback.
    static func stringOrNull(_ value: String, in context: JSContext) -> Any {
        JSValue(object: value, in: context) ?? NSNull()
    }

    // MARK: - Rejections

    /// Rejects `reject` with a JavaScript `Error` carrying `message`.
    ///
    /// An `Error` and not a bare string, so an extension's `catch` sees
    /// `error.message` and `error instanceof Error` — which is what
    /// `VSCodeAPI.rejectedPromise(message:in:)` builds for the synchronous
    /// refusals, and the asynchronous ones should not be a different shape.
    ///
    /// No `stack`, and nothing can be done about it here:
    /// `JSValue(newErrorFromMessage:in:)` constructs the object rather than
    /// throwing from JavaScript, so there is no JavaScript frame to record
    /// and `error.stack` is `undefined`. An extension's handler that logs
    /// `e.stack` therefore logs "undefined" — which is why the message is
    /// written to name the member and the reason on its own, rather than
    /// leaning on a trace to supply the context.
    ///
    /// Silent when the context is gone: there is then nothing left to reject
    /// into.
    static func rejectWithError(_ reject: JSValue, message: String) {
        guard let context = reject.context,
              let errorValue = JSValue(newErrorFromMessage: message, in: context) else {
            return
        }
        reject.call(withArguments: [errorValue])
    }

    /// Rejects `reject` with the same wording `VSCodeAPI.member`'s own
    /// teardown path uses, so an extension's `catch` sees one consistent
    /// message for "this adaptor is gone" everywhere it can happen.
    static func rejectTornDown(_ reject: JSValue, path: String) {
        rejectWithError(reject, message: "\(path) is unavailable: this extension's host has been torn down.")
    }

    // MARK: - Reads

    /// A `String` only for a property that is genuinely a JavaScript string —
    /// `nil` for absent, and `nil` for a number or an object rather than a
    /// coercion of it.
    ///
    /// Used for fields that are decoration or an optional constraint: an
    /// unusable one is omitted rather than made to reject the whole call, and
    /// an `undefined` property is read as "no constraint on this field," never
    /// as an empty-string constraint.
    static func stringOptionalField(_ value: JSValue?) -> String? {
        guard let value, value.isString else { return nil }
        return value.toString()
    }
}
