<!-- leaf: implement-general-2/rdid-editor--test-vectors · source: rdid-editor.md -->

# RdidEditor

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| rdid-editor-001 | renders-associated-label | `label="Name"`, `id="leaf"` | A `<label for="leaf">Name</label>` renders, and the input has `id="leaf"` |
| rdid-editor-002 | generates-stable-input-id | `id` omitted | The rendered `<label>`'s `for` attribute matches the rendered `<input>`'s `id` attribute (both non-empty) |
| rdid-editor-003 | renders-static-prefix | `prefix="persona.acme."`, `value="bob"` | Static text `persona.acme.` renders before the input; the input's value is `bob`, not `persona.acme.bob` |
| rdid-editor-004 | renders-single-input-without-prefix | `prefix=""`, `value="my-org"` | No prefix element renders; a single full-width input shows value `my-org` |
| rdid-editor-005 | displays-controlled-value | `value="acme-2"` | The rendered input's value is exactly `acme-2` |
| rdid-editor-006 | lowercases-input-on-change | User types `ACME` into the input | `onChange` is called with `"acme"` |
| rdid-editor-007 | forwards-placeholder | `placeholder="my-slug"` | The rendered input has `placeholder="my-slug"` |
| rdid-editor-008 | shows-hint-below-input | `hint="Lowercase, hyphens only"`, `error` omitted | The footnote below the input reads `Lowercase, hyphens only` |
| rdid-editor-009 | shows-error-in-place-of-hint | `hint="Lowercase, hyphens only"`, `error="Required."` | The footnote below the input reads `Required.`, not the hint text |
| rdid-editor-010 | marks-input-invalid-on-error | `error="Required."` | The rendered input has `aria-invalid="true"` |
| rdid-editor-011 | omits-invalid-attribute-without-error | `error` omitted | The rendered input has no `aria-invalid` attribute at all |
| rdid-editor-012 | disables-input-when-disabled | `disabled={true}` | The rendered input has the native `disabled` attribute and rejects typed input |
| rdid-editor-013 | supports-native-keyboard-input | Component focused via `Tab` | The input receives focus and accepts typed characters with no custom key interception |
| rdid-editor-014 | generates-stable-input-id | `id` omitted; component re-rendered with a new `value` | The rendered `<input>`'s generated `id` is identical before and after the re-render |
| rdid-editor-015 | shows-hint-below-input, shows-error-in-place-of-hint | `hint` and `error` both omitted | No footnote element renders below the input |
