<!-- leaf: implement-general-2/send-invitation-modal--edge-cases · source: send-invitation-modal.md -->

# SendInvitationModal

## Edge Cases

- Recipients are seeded once at mount and are never mutated by this modal (`RecipientInput` renders read-only); re-seeding for a new selection only happens if the caller changes the `key` prop to force a remount.
- Pre-seeded recipients alone do not make the form "populated" — only note text does, so an unmodified, freshly opened modal closes immediately on Cancel/Esc/backdrop even though its sections show recipients.
- A single whitespace character in either note counts as populated and triggers the discard confirm.
- The Send payload always includes one entry per rendered section, each carrying that section's untrimmed note, sent as `""` when the note is empty.
- Send is disabled only when neither `emails` nor `phones` was seeded, so no section renders.
- While `busy`, Cancel/Esc/backdrop are blocked outright — no discard confirm is shown even for a populated form.
- State (including notes and the discard confirm) resets on close, so reopening via a remount re-seeds from the current props.
