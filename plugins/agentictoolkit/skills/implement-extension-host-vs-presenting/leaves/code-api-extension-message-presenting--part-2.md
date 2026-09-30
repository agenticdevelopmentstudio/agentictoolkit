<!-- leaf: implement-extension-host-vs-presenting/code-api-extension-message-presenting--part-2 · source: extension-host-vs-code-api-extension-message-presenting.md -->

# ExtensionMessagePresenting — continued (part 2)

## Design Decisions

**Decision**: `closeAffordanceIndices` is a list of indices rather than a single optional index.
**Rationale**: stated in the source's own doc comment — upstream (`extHostMessageService.ts`) keeps the `isCloseAffordance` flag on every item that set it, logging only a warning for the second and later ones, and `mainThreadMessageService.ts` routes every flagged command's index through `cancelButton = button` in turn, so the last one wins the cancel slot. A model carrying only the first flagged index cannot represent a second one, and would render it as an ordinary button — a divergence from upstream this design avoids.
**Approved**: pending

**Decision**: `ExtensionMessageRequest` declares no explicit `public init`, leaving its memberwise initializer at internal access.
**Rationale**: not stated in the source; this follows from Swift's own rule that a struct's synthesized memberwise initializer is `internal` unless an explicit `public` one is written, regardless of the struct's own access level. Flagged here so a port does not assume "module-private construction" was a deliberate design choice recorded anywhere in this file — it is a byproduct of what the file omits, worth a conscious choice on any platform being ported to.
**Approved**: pending

**Decision**: `presentMessage(_:)` never throws; an unpresentable message resolves the same as a user dismissal.
**Rationale**: per `NSAlertMessagePresenter`'s own doc comment, an extension calling `show*Message` must already handle "the user dismissed without choosing an item" (`vscode.d.ts`'s own contract), so folding "could not be presented at all" into that same outcome needs no new error type or case, at the cost of losing the distinction on the extension side.
**Approved**: pending

**Decision**: `isModal` is carried on the request but the protocol does not require a conformer to honor it.
**Rationale**: per `NSAlertMessagePresenter`'s own doc comment, this repo "has no toast primitive today, and inventing one is outside this task," so its one conformer presents every request modally regardless of `isModal`; the field is preserved on the request specifically so a later, non-modal presenter can read and honor it without a source change to `ExtensionMessageRequest` itself.
**Approved**: pending

**Decision**: this recipe's Behavioral Requirements section is shorter than its sibling `extension-host-vs-code-api-ai-plugin-language-model-provider`.
**Rationale**: `ExtensionMessagePresenting.swift` is a pure data-and-protocol seam with no executable logic of its own — no persistence, no network access, no request-building — while that sibling documents a full production conformer with resolution, streaming, and error-mapping logic. The depth difference tracks a genuine difference in the two files' complexity, not an authoring gap.
**Approved**: pending
