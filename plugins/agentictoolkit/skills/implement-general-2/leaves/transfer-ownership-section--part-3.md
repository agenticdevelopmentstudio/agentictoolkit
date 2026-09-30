<!-- leaf: implement-general-2/transfer-ownership-section--part-3 · source: transfer-ownership-section.md -->

# TransferOwnershipSection — continued (part 3)

## Design Decisions

**Decision**: Trim both sides of the confirm comparison (`entityLabel` and the typed value) instead
of an exact match.
**Rationale**: `entityLabel` here can be a user-editable display name, not always a machine
identifier, so trailing whitespace would render identically to its absence; a strict compare
would leave the button permanently un-armable with nothing on screen to explain why.
**Approved**: pending

**Decision**: Seal the dialog against dismissal only while the final transfer (`onConfirm`) is
pending, never while the preflight (`onPreview`) is pending.
**Rationale**: `onPreview` performs no server write, so a slow or hung preflight has no correctness
claim on the user's ability to back out; sealing it too would trap them behind "Checking…" with
no exit.
**Approved**: pending

**Decision**: Style the Transfer button `warning`, not `destructive`.
**Rationale**: a transfer moves the object and drops other principals' access to it, but nothing is
destroyed and the move can be made again in the other direction; the red destructive treatment is
reserved for what cannot be undone.
**Approved**: pending

**Decision**: Guard the async preflight race with a monotonically incrementing `previewSeq` ref
rather than cancelling the `onPreview` promise itself.
**Rationale**: `onPreview` is a caller-supplied `Promise` with no cancellation contract; a sequence
number lets a late resolution be detected and ignored without requiring the caller to support
`AbortController`-style cancellation.
**Approved**: pending

**Decision**: Widen the confirmation dialog to `max-w-xl`.
**Rationale**: every load-bearing line of text in the dialog is an identifier, and at the platform's
default `max-w-md` a mid-length one wraps confusingly inside itself.
**Approved**: pending
