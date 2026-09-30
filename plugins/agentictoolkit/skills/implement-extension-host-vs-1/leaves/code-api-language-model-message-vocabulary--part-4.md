<!-- leaf: implement-extension-host-vs-1/code-api-language-model-message-vocabulary--part-4 · source: extension-host-vs-code-api-language-model-message-vocabulary.md -->

# LanguageModelMessageVocabulary — continued (part 4)

## Design Decisions

**Decision**: All eight members are constructed inside one evaluated IIFE rather than eight independent `evaluateScript` calls, one per member.
**Rationale**: `LanguageModelChatMessage`'s `content` setter constructs a `LanguageModelTextPart`, and `LanguageModelDataPart.json`/`.text` construct a `LanguageModelDataPart` through the shared `utf8EncodeToUint8Array` function; all three need to see each other as ordinary lexical bindings inside the same closure rather than re-finding one another off `globalThis` on every call, which would also reintroduce the exact per-call re-lookup cost the single-cached-container pattern (shared with `Uri.swift`'s `installUriClass(in:)`) exists to avoid.
**Approved**: pending

**Decision**: `LanguageModelDataPart.image` applies no default `mime` when the argument is omitted, while `.json` and `.text` both default theirs.
**Rationale**: not stated in the source's comments beyond the line-by-line `vscode.d.ts`/`extHostTypes.ts` citations for the file as a whole; there is no single natural default MIME type for arbitrary image bytes the way `'text/x-json'` and `'text/plain'` serve `.json`/`.text`, and the given sources include no upstream citation specific to `.image`'s own default behavior. This recipe states the observed behavior — no default is applied — as a requirement (**data-part-image-factory**) rather than inferring a rationale the source does not give.
**Approved**: pending

**Decision**: a present-but-malformed value is never checked by any of the eight members' constructors — `input`, `content`, `data`, and `value` are all stored exactly as given, with no `TypeError` path anywhere in this file, unlike the validating constructors in `DiagnosticTypes.swift`.
**Rationale**: matches `extHostTypes.ts`'s own implementation for these eight declarations, none of which validates its constructor arguments (only `Diagnostic` and `DiagnosticRelatedInformation`, in a different file, do). Adding validation here that upstream does not have would diverge from the vocabulary this file exists to mirror.
**Approved**: pending
