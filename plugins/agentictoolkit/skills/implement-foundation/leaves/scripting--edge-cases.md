<!-- leaf: implement-foundation/scripting--edge-cases · source: foundation-scripting.md -->

# Foundation Scripting

**Rules** (cite as `implement-foundation/scripting--edge-cases#<slug>`):

- `empty-applescript-source` MUST (null/empty input) — AppleScriptRunner.run("") MUST compile and execute successfully, returning .success(nil), per …
- `script-produces-no-textual-result` MUST (boundary of `success-result-value`) — when the executed script's result descriptor's stringValue is nil, AppleScriptRunner.run(_:) MUST still return …
- `extreme-or-unusual-error-numbers` MUST (boundary values) — AppleScript/OSA error numbers span the full Int domain, including negative codes (e.g. -1728); …
- `concurrent-calls-to-applescriptrunner-run` MUST (concurrent access) — each call constructs and owns its own NSAppleScript instance with no state shared inside AppleScriptRunner itself, so …
- `concurrent-performmain-invocations-on-one-mainactorscriptcommand-instance` MUST (concurrent access) — because performMain() is @MainActor-isolated and Cocoa Scripting always dispatches command handlers on the main thread, …
- `performdefaultimplementation-invoked-off-the-main-thread` MUST (error state, outside the stated contract) — MainActor.assumeIsolated MUST trap — a fatal runtime error, not a catchable error or a returned value — because the …
- `nsapp-classdescription-is-not-an-nsscriptclassdescription` MUST (error/unavailable-dependency state) — applicationElementSpecifier(key:uniqueID:) MUST return nil rather than trapping or constructing a malformed specifier.
- `compile-failure-path` MUST (error state) — NSAppleScript(source:) returning nil MUST route to .compileFailed; AppleScriptRunnerTests' own comment documents this …

## Edge Cases

- **Empty AppleScript source** (null/empty input): `AppleScriptRunner.run("")` MUST compile and execute successfully, returning `.success(nil)`, per `AppleScriptRunnerTests.emptySourceSucceeds` — `NSAppleScript` treats empty source as a valid, no-op script rather than a compile failure.
- **Script produces no textual result** (boundary of `success-result-value`): when the executed script's result descriptor's `stringValue` is `nil`, `AppleScriptRunner.run(_:)` MUST still return `.success(nil)` rather than promoting the absence of a value to `.compileFailed` or `.runtimeFailed`.
- **Extreme or unusual error numbers** (boundary values): AppleScript/OSA error numbers span the full `Int` domain, including negative codes (e.g. `-1728`); `AppleScriptRunner.run(_:)` MUST pass `NSAppleScript.errorNumber` through unmodified, with no range validation or clamping.
- **Concurrent calls to `AppleScriptRunner.run(_:)`** (concurrent access): each call constructs and owns its own `NSAppleScript` instance with no state shared inside `AppleScriptRunner` itself, so concurrent calls from independent threads MUST NOT corrupt one another's result; the source's own doc comment notes that `NSAppleScript` may nonetheless require all such calls to land on the main thread on some macOS versions, a requirement `AppleScriptRunner` does not enforce (see `caller-main-thread-marshaling`).
- **Concurrent `performMain()` invocations on one `MainActorScriptCommand` instance** (concurrent access): because `performMain()` is `@MainActor`-isolated and Cocoa Scripting always dispatches command handlers on the main thread, invocations MUST be serialized by the main actor's executor; the component adds no further locking because none is needed.
- **`performDefaultImplementation()` invoked off the main thread** (error state, outside the stated contract): `MainActor.assumeIsolated` MUST trap — a fatal runtime error, not a catchable error or a returned value — because the safety of that call rests on the documented assumption that Cocoa Scripting always invokes command handlers on the main thread when the script suite is registered in the app's `Info.plist`, not on a runtime-checked precondition.
- **`NSApp.classDescription` is not an `NSScriptClassDescription`** (error/unavailable-dependency state): `applicationElementSpecifier(key:uniqueID:)` MUST return `nil` rather than trapping or constructing a malformed specifier.
- **Compile failure path** (error state): `NSAppleScript(source:)` returning `nil` MUST route to `.compileFailed`; `AppleScriptRunnerTests`' own comment documents this path as unreachable in practice, since `NSAppleScript` accepts any string and defers all parse/tokenizer errors to `executeAndReturnError` — the case exists purely as a defensive catch against a documented-nullable initializer, not because any known input currently exercises it.
- **Offline / disconnected state**: Not applicable — none of the three sources perform network I/O. An AppleScript run through `AppleScriptRunner.run(_:)` may itself address another application or a network resource, but any such failure surfaces through that script's own `error`/return value and is reported through the ordinary `.runtimeFailed`/`.success` path, not through a distinct offline case in this component.
