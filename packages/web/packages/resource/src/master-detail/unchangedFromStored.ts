/**
 * True when `value` is still the value the record was STORED with: the one test every
 * master/detail validator uses to exempt ("grandfather") a value the user did not touch.
 *
 * Why the exemption exists: a row the BACKEND wrote need not satisfy a rule the client added
 * later, and refusing it holds every other field's Save hostage to a value nobody edited. It has
 * shipped three ways: the auto-provisioned `participants` / `admins` teams, whose plain-slug
 * identifiers fail the reverse-domain format (Save permanently greyed out on the teams every
 * workspace has); SSO-provisioned users stored with a NULL email, read back as "" (a rename
 * refused with "Email is required."); and project names differing only in case, which the
 * backend's exact-match unique index lets coexist while the client's case-folded uniqueness check
 * refused both of them on every unrelated edit.
 *
 * Why ONE function: the six validators that exempt a stored value (the four in projects, the
 * team's, the user's) each spelled this comparison themselves, and not the same way — one did not
 * trim the stored side, one treated a create's blank draft as a stored record — so an untouched
 * value could be exempt in one pane and refused in the next. Which checks a validator skips is a
 * real per-field decision and stays with the validator; whether the value is untouched is not.
 *
 * - `stored` null or undefined means there IS no stored record — a create, because
 *   useMasterDetailForm passes `base` as null while creating — so nothing is exempt. The hook used
 *   to pass `blank()` there, and a blank draft "matched" it: userValidate waived "Email is
 *   required." for a brand-new user.
 * - Both sides are trimmed. The validators judge the trimmed draft everywhere else, and a stored
 *   value carrying whitespace the backend accepted is still one the user did not touch.
 * - Case is NOT folded: re-casing a value is an edit, and an edit is held to the rules.
 * - "" against "" is deliberately true: a record stored with no value (the SSO user's NULL email)
 *   that the user leaves empty is untouched.
 */
export function unchangedFromStored(value: string, stored: string | null | undefined): boolean {
  return stored != null && value.trim() === stored.trim();
}
