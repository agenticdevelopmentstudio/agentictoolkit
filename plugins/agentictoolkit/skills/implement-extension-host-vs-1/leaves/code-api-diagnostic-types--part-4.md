<!-- leaf: implement-extension-host-vs-1/code-api-diagnostic-types--part-4 · source: extension-host-vs-code-api-diagnostic-types.md -->

# DiagnosticTypes — continued (part 4)

## Design Decisions

**Decision**: `Diagnostic` requires a real `Range` instance and `DiagnosticRelatedInformation` requires a real `Location` instance at construction time (`requireGeometryInstance`), rather than accepting any value shaped like one.
**Rationale**: upstream VS Code checks `range` structurally (`Range.isRange`) and does not check `location` at all, then reads a duck-typed value back happily; this host's readers (`range(from:in:)`, `location(from:in:)`, both in `TextGeometry.swift`) already refuse anything that is not a real instance via `isInstance(of:)`. Accepting at construction what the reader will later refuse would surface an extension's mistake one call removed, at `collection.set(uri, [d])`, naming neither the argument nor the line that built it; refusing in the constructor puts the failure where the extension's own code made the mistake.
**Approved**: pending

**Decision**: `Diagnostic`'s constructor never assigns `source`, `code`, `relatedInformation`, or `tags` at all when not supplied, rather than assigning them `undefined`.
**Rationale**: matches `diagnostic.ts`'s constructor, which only ever assigns `range`, `message`, and `severity`; this is what makes `'source' in diagnostic` genuinely `false` until an extension sets it, exactly as real VS Code behaves. An implementation that unconditionally wrote `this.source = source` would make that membership check always `true`, a detectable behavioral divergence from the upstream declaration real extensions may rely on.
**Approved**: pending

**Decision**: `diagnostic(from:in:)` treats a present-but-undecodable optional field (a `source` that is a number, a `code` matching none of the three shapes, a malformed `relatedInformation`/`tags` element) as a failure of the *entire* decode, returning `nil` rather than a partial `ExtensionDiagnostic` with that one field dropped.
**Rationale**: the source's own inline comment traces a concrete production incident to the opposite choice: reading `code: null` or `source: null` as "present but undecodable" once dropped every diagnostic in a file for every extension that asked, because a downstream array reader (`MainThreadDiagnostics`, not among the given sources) itself refuses a whole file's array when one element refuses. Distinguishing `null`/`undefined` ("absent") from a genuinely malformed present value, and refusing the whole diagnostic only for the latter, is the fix; treating every malformed field as if the diagnostic silently lost that one field would reintroduce a different silent-data-loss failure mode one level up.
**Approved**: pending

**Decision**: this file's own doc comment characterizes the `range`/`location` validity check inside `requireGeometryInstance` as "a validity gate, not an identity check" and describes it as dispatching structurally on `.start`/`.end`-shaped properties, "the same structural way `Range.prototype.contains` already dispatches." The actual `requireGeometryInstance` implementation performs `value instanceof geometryClass`, where `geometryClass` is looked up dynamically via `globalThis[textGeometryGlobalName][name]` — a genuine identity check against the class TextGeometry.swift installed, not a structural check of `.start`/`.end`.
**Rationale**: not stated in the source; this is a divergence between the file's header prose and its own code, not a design choice this recipe can attribute to either. Practically it makes no behavioral difference for a well-formed `Range`/`Location` instance, since a real instance is both `instanceof` its class and shaped correctly — but it does mean a hypothetical duck-typed literal carrying `.start`/`.end` properties, which the header's prose implies would pass, is in fact refused by the actual `instanceof` check, per **diagnostic-constructor-validates-range**/**related-information-constructor-validates-location**, which this recipe states from the code rather than the header.
**Approved**: pending
