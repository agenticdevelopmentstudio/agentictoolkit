/**
 * Password-manager opt-out for this package's own fields.
 *
 * A deliberate copy of `@agenticdevelopertoolkit/ui/lib/autofill`, which is the fleet's list of
 * record and carries the full rationale (which vendor reads which attribute, and
 * why `autocomplete="off"` alone moves none of them). It is copied rather than
 * imported because this package ships zero runtime dependencies on purpose — a
 * site can render a registry with nothing but React, and `@agenticdevelopertoolkit/ui` is in
 * neither its peers nor its deps (see the note in editors/FieldDefEditor.tsx).
 * Six string literals are the cheaper of the two prices.
 *
 * It is also what the two public directory sites (`sites/registries`,
 * `sites/consultants`) import for their search boxes: they depend on this
 * package and not on the UI kit either, and had spelled the six attributes out a
 * third and fourth time until this became an export. `<adh-tools>/sites/scripts/verify_autofill_copies.py`
 * is what keeps every copy in step — the prose above used to be the only thing
 * holding them together, and it did not: the chat composer's copy sat one
 * attribute short of this one for as long as it existed.
 *
 * The ATTRIBUTES are copied; `noAutofillPropsFor` deliberately is NOT. That
 * helper exists for a component forwarding arbitrary props, so a field naming a
 * real autofill token can take itself back out. Registry fields hold a
 * *record's* data — an entry's name, its contact email, its URL — never the
 * reader's own credentials, so nothing here ever wants a manager and a copy of
 * the helper would be a branch with no caller.
 */
export const noAutofillProps = {
  autoComplete: 'off',
  'data-form-type': 'other',
  'data-1p-ignore': 'true',
  'data-lpignore': 'true',
  'data-bwignore': 'true',
  'data-protonpass-ignore': 'true',
} as const
