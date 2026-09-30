<!-- leaf: implement-extension-host-vs-2/code-api-text-geometry--part-5 · source: extension-host-vs-code-api-text-geometry.md -->

# TextGeometry — continued (part 5)

## Design Decisions

**Decision**: `Range`'s constructor swaps `start`/`end` even when they are equal-but-distinct `Position` objects, not only when strictly out of order.
**Rationale**: `vscode.d.ts`'s prose reads as "equal positions are not swapped," but the implementation's own condition, `start.isBefore(end)`, is strict, so two equal-but-distinct positions take the `else` branch and are swapped anyway — traced to the source's own header commentary; unobservable by value, so this recipe follows the implementation and pins no test on object identity for this case.
**Approved**: pending

**Decision**: `Location` instances are the one case in this file not frozen via `Object.freeze`, even though `Position` and `Range` both are.
**Rationale**: `vscode.d.ts` declare `uri`/`range` as plain, assignable stored properties, and upstream's `Location` really is mutable — `location.range = someRange` is ordinary extension code, and a frozen instance would fail it. `Location`'s class object and prototype are still frozen inside the same evaluation as everything else; only the per-instance freeze is withheld, and only for this one class.
**Approved**: pending

**Decision**: `Position.Min`, `Position.Max`, `Position.of`, `Position.isPosition`, and `Range.isRange` are implemented as private helper functions inside the evaluated closure rather than as static members on the published `Position`/`Range` classes.
**Rationale**: none of the five is in `vscode.d.ts`'s declared `Position`/`Range` surface — only upstream's own implementation carries them — and a static `vscode.Position.Min` that a real, `tsc`-compiled VS Code extension can never legally call would be exactly the kind of host-only surface this file's own header says it is trying not to accumulate.
**Approved**: pending

**Decision**: **main-actor-isolation** has no row in Conformance Test Vectors.
**Rationale**: it is a compiler-enforced fact about `VSCodeAPI`'s own `@MainActor` declaration, not a runtime branch a `JSContext` script or a single Swift call can exercise as a PASS/FAIL test; this recipe follows the same precedent the `LanguageModelMessageVocabulary` recipe already sets for the identical requirement on the identical enum, covering it instead under Edge Cases ("Concurrent access").
**Approved**: pending
