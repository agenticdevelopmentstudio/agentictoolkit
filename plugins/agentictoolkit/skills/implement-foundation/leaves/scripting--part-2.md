<!-- leaf: implement-foundation/scripting--part-2 · source: foundation-scripting.md -->

# Foundation Scripting — continued (part 2)

## Design Decisions

### Advisory main-thread requirement is not enforced

**Decision**: `AppleScriptRunner.run(_:)` performs no thread check, assertion, or automatic dispatch to the main thread before calling `NSAppleScript(source:).executeAndReturnError`; the main-thread requirement is stated only in a doc comment as guidance to the caller.

**Rationale**: the doc comment itself states the requirement varies by macOS version, so a hard-coded thread assertion here would fail closed on versions where the restriction does not apply, and forcing an internal dispatch to main would turn every call into an implicitly asynchronous operation, breaking the synchronous, directly-returned `Result` contract every existing caller relies on.

**Approved**: pending

### `.compileFailed` is kept as a defensive case despite being unreachable today

**Decision**: `AppleScriptRunner.Result` keeps a `.compileFailed` case even though `AppleScriptRunnerTests`' own comment states `NSAppleScript(source:)` never returns `nil` in practice — parse/tokenizer errors surface later, through `.runtimeFailed`.

**Rationale**: `NSAppleScript(source:)` is declared as a failable initializer (`NSAppleScript?`), so the type system requires a `nil` case regardless of today's observed behavior; naming that case explicitly is cheaper and clearer than force-unwrapping and asserting an invariant that a future Foundation change could silently invalidate.

**Approved**: pending

### Fail-fast main-actor trapping instead of a runtime-checked precondition

**Decision**: both `MainActorScriptCommand.performDefaultImplementation()` and `applicationElementSpecifier(key:uniqueID:)` bridge onto the main actor with `MainActor.assumeIsolated`, which traps if invoked off the main thread, rather than a runtime check that returns an error or `nil`.

**Rationale**: Cocoa Scripting's own contract guarantees `performDefaultImplementation()` is always invoked on the main thread when the script suite is registered in the app's `Info.plist`; trapping converts a violation of that guarantee into an immediate, loud failure at the call site instead of letting undefined AppKit/main-actor state propagate silently, consistent with agenticdevelopercookbook://principles/fail-fast.

**Approved**: pending

### Box-based Sendable bridging instead of an `@unchecked Sendable` closure

**Decision**: both main-actor bridging call sites wrap their captured state and result in a private, file-local `final class Box: @unchecked Sendable` rather than marking the capturing closure itself `@unchecked Sendable`.

**Rationale**: per `MainActorScriptCommand.swift`'s own comment, `assumeIsolated`'s `sending` closure parameter rejects captures of a non-final `@unchecked Sendable` `self` under Swift 6 region analysis, but a `final class @unchecked Sendable` Box holding `self` (and, for `applicationElementSpecifier`, the `key`, `uniqueID`, and result) satisfies the region checker; this is the codebase's one standing pattern for this bridge, applied twice, rather than two independent workarounds.

**Approved**: pending

### Hardcoded, never-localized "unknown error" fallback

**Decision**: `AppleScriptRunner.run(_:)` substitutes the literal English string "unknown error" for a missing `NSAppleScript.errorMessage` value rather than a localized string, a nil message, or a different fallback.

**Rationale**: `runtimeFailed(message:number:)`'s `message` is typed as a non-optional `String`, so some literal value is required when the dictionary entry is absent; no localization layer exists anywhere in this component's three files for this or any other string (see Localization), so the fallback is plain, hardcoded English by default rather than by a deliberate localization decision.

**Approved**: pending
