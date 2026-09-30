<!-- leaf: implement-extension-host-vs-1/code-api-js-value-bridge--part-2 · source: extension-host-vs-code-api-js-value-bridge.md -->

# JSValueBridge — continued (part 2)

## Design Decisions

**Decision**: Two return shapes exist for equivalent values — `undefined(in:)`/`array(of:in:)` return `JSValue?`, while `undefinedOrNull(in:)`/`arrayOrNull(of:in:)`/`stringOrNull(_:in:)` return `Any` with an `NSNull()` fallback — rather than collapsing to one signature.
**Rationale**: per the source file's own header, a `Promise` settlement takes `Any` and cannot be handed `nil` (an unsettled promise would leave an extension's `await` hanging on a failure it cannot see), so those builders fall back to `NSNull()`; a synchronous member result is `JSValue?`, where `nil` is itself a legitimate answer. Collapsing the two would force every synchronous call site to widen its result to `Any` and then immediately narrow it back. See **undefined-value**/**undefined-or-null-value** and **array-construction**/**array-or-null-construction**.
**Approved**: pending

**Decision**: `JSValueBridge` declares no actor isolation of its own — no `@MainActor`, no `actor`, no `Sendable` — even though every current call site is `@MainActor`.
**Rationale**: the type is a caseless enum with no stored state, so per **pure-value-construction** and **no-actor-isolation-declared** there is nothing to isolate; its `JSContext`/`JSValue` parameters are non-Sendable classes, so the Swift compiler already confines any given instance of them to whichever isolation domain created it before this bridge is called. Declaring `@MainActor` here would add a redundant constraint that a future call site building its own off-main-actor `JSContext` would then have to work around.
**Approved**: pending

**Decision**: `rejectTornDown(_:path:)`'s exact wording is not the only copy of a teardown rejection in this codebase: `MainThreadLanguageModels.swift` rebuilds the same wording in a private `rejectLanguageModelTornDown` function rather than calling `rejectTornDown`, so it can attach the extra `code` property a language-model rejection carries that this bridge's plain `Error` does not.
**Rationale**: recorded here so a future reader of **reject-torn-down-wording** does not assume every `vscode.lm.*` teardown rejection routes through this file. `MainThreadLanguageModels.swift`'s own comment (near its `rejectLanguageModelTornDown` declaration) explains the divergence is deliberate rather than a missed refactor, and this recipe's contract covers only what `JSValueBridge.swift` itself does.
**Approved**: pending

**Decision**: `arrayOrNull(of:in:)` has no dedicated test method in `JSValueBridgeTests.swift`, unlike every other public member of this file.
**Rationale**: its implementation is `JSValue(object: values, in: context) ?? NSNull()`, the same expression `array(of:in:)` already exercises under **array-construction**/**array-construction-is-fresh**, differing only in the `Any` box and the `NSNull()` fallback **array-or-null-construction** requires. Recorded here as a completeness fact traced to the test file itself, per **js-value-bridge-005**, rather than raised as an open question — the behavior is fully specified by the shared implementation and the sibling test on `array(of:in:)`, even though no test method calls `arrayOrNull` directly.
**Approved**: pending

**Decision**: this recipe is deliberately shorter than sibling `extension-host-vs-code-api-*` recipes for stateful adaptors (`MainThreadWindow`, `MainThreadDiagnostics`, and similar).
**Rationale**: `JSValueBridge` is a genuinely smaller component — eight one-line pure functions and no installed JS classes, no state machine, and no `JSContext` lifecycle of its own — so its behavioral surface (fifteen requirements, zero states) is proportionate to its actual scope rather than under-authored, per the cross-recipe-consistency guideline's "genuinely warranted" allowance.
**Approved**: pending
