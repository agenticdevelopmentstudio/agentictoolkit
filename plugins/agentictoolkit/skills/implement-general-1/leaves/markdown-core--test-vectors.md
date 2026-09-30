<!-- leaf: implement-general-1/markdown-core--test-vectors · source: markdown-core.md -->

# MarkdownCore

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| markdown-core-001 | delete-tombstones-both-flags | `deleteDocument` on a live document | Both delete columns set on the document row and every marker row (`deleteSetsBothFlags`) |
| markdown-core-002 | update-refuses-authored-drift | `updateDocument` called with visibility changed from the stored row | Throws the dedicated-intent error naming the visibility field (`updateRefusesVisibilityDrift`) |
| markdown-core-003 | publish-invariant | `publishDocument` called with an empty route | Throws the inconsistent-publication error (`publishRefusesABlankRoute`) |
| markdown-core-004 | outbox-order-is-sequence | Operations enqueued out of creation order but in sequence order | The pending-operations read returns them in sequence order (`queueIsOrderedBySequenceNotTimestamp`) |
| markdown-core-005 | opposing-intents-cancel | `publishDocument` followed by `unpublishDocument` before the queue drains | Exactly one operation remains queued (`opposingIntentsCancelInsteadOfMergingInPlace`, `cancellingLeavesOneOpPerPair`) |
| markdown-core-006 | cycle-refusal | `addCategoryEdge` where the proposed parent is already a descendant of the proposed child | Throws the category-cycle error (`cycleIsRefused`); a diamond shape is still allowed (`diamondIsAllowed`) |
| markdown-core-007 | revive-on-conflict | `createKeyword` for a label whose only holder is tombstoned | The tombstoned row is revived, not duplicated (`tombstonedKeywordIsRevived`) |
| markdown-core-008 | number-range-clamping | A pulled JSON number outside the 64-bit signed integer range | The value is stored as a lossy double rather than trapping (`oversizedNumbersDoNotTrap`) |
| markdown-core-009 | unencodable-value-throws | A pulled array or object value bound for a scalar column | Throws rather than binding a null (`unencodableValueThrows`) |
| markdown-core-010 | postgres-form-repair | `MarkdownTimestamp.date` given a Postgres wire-form timestamp with a space separator and a two-digit offset | Parses to the same instant the writer would produce for the ISO-8601 spelling (`postgresFormsNormalise`) |
