<!-- leaf: implement-extension-host-core-1/extensions-extension-identity-component--edge-cases · source: extension-host-core-extensions-extension-identity-component.md -->

# ExtensionIdentityComponent

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-identity-component--edge-cases#<slug>`):

- `empty-input` MUST — value == "" MUST return false (traced to emptyIsRefused).
- `boundary-values-at-the-control-character-edges` MUST — U+001F MUST be refused, U+0020 MUST be accepted, U+007E MUST be accepted, U+007F MUST be refused, and U+0080 MUST be …
- `boundary-a-value-that-is-only-a-dot` MUST — "." and ".." MUST be refused identically to a longer leading-dot name such as ".ssh" (traced to aLeadingDotIsRefused).
- `concurrent-access` MUST — not applicable in the shared-mutable-state sense — isSafe is a pure function of its argument, …
- `already-encoded-separators-are-not-decoded` MUST — a value already containing an encoded separator, such as "a%2Fb" or "a%2E%2E", MUST be accepted; the caller that …
- `unbounded-length` MUST — isSafe MUST accept or refuse a value of any length according only to the shape rules above; the source enforces no …

## Edge Cases

- **Empty input**: `value == ""` MUST return `false` (traced to
  `emptyIsRefused`).
- **Boundary values at the control-character edges**: `U+001F` MUST be
  refused, `U+0020` MUST be accepted, `U+007E` MUST be accepted, `U+007F`
  MUST be refused, and `U+0080` MUST be accepted (traced to
  `theControlRangeEdgesAreRight`).
- **Boundary: a value that is only a dot**: `"."` and `".."` MUST be refused
  identically to a longer leading-dot name such as `".ssh"` (traced to
  `aLeadingDotIsRefused`).
- **Malformed input**: not applicable as a distinct condition — `value` is a
  Swift `String`, already a well-formed sequence of Unicode scalars for any
  argument a caller can construct, so `isSafe` has no notion of "malformed"
  input; it never throws or traps regardless of content, including
  combining sequences and emoji (traced to `internationalisedNamesAreAccepted`
  and the absence of any input-shape precondition in the source).
- **Concurrent access**: not applicable in the shared-mutable-state sense —
  `isSafe` is a pure function of its argument, `ExtensionIdentityComponent`
  has no cases and cannot be instantiated, and the source declares no stored
  property anywhere in the type. Concurrent calls from multiple threads or
  actors MUST produce results that depend only on each call's own `value`
  argument, never on the order or overlap of other calls.
- **Error states (dependency unavailable)**: not applicable — `isSafe`
  performs no file, network, or database access; the entire function body
  reads only the scalars of `value`, so there is no dependency that can be
  unavailable.
- **Offline / disconnected state**: not applicable — `isSafe` does not
  operate over a network; it is a synchronous, local string computation.
- **Already-encoded separators are not decoded**: a value already containing
  an encoded separator, such as `"a%2Fb"` or `"a%2E%2E"`, MUST be accepted;
  the caller that splices the accepted value in verbatim is responsible for
  never decoding it afterward, since decoding after this check would
  reintroduce a separator behind the check (traced to
  `anEncodedSeparatorIsNotASeparator`).
- **Unbounded length**: `isSafe` MUST accept or refuse a value of any length
  according only to the shape rules above; the source enforces no minimum
  length beyond non-emptiness and no maximum length at all (traced to the
  absence of any length check in the source).
