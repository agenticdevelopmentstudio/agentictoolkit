<!-- leaf: implement-general-2/transfer-ownership-section--states · source: transfer-ownership-section.md -->

# TransferOwnershipSection

## States

| State | Appearance change |
|-------|------------------|
| Default (collapsed) | `Disclosure` closed; nothing else renders |
| Disclosed | Explanatory body text and the destination dropdown trigger become visible |
| Dropdown open | Menu of `targets` visible; entries with `children` render as nested submenus |
| Menu item — current target | Disabled; label reads "{name} (current)" |
| Target chosen, preflight pending | Dialog opens; body shows "Checking…" |
| Preview loaded, `tokens > 0` | Token-revocation warning line shown with the `TriangleAlert` icon |
| Preview loaded, `revoking.length > 0` | "These will lose access:" list shown |
| Preview loaded, `revoking.length === 0` | "No access is revoked." shown |
| Confirm gate armed (`confirmed === true`) | Transfer button enabled, `warning` variant |
| Confirming (transfer in flight) | Dialog close control hidden, Cancel disabled, Input disabled, Transfer button reads "Transferring…" |
| Preview error | Inline error shown via `ErrorText`; dialog stays open |
| Transfer error | Inline error shown via `ErrorText`; dialog stays open; busy state clears |
