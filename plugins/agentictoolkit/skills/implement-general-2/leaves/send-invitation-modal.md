<!-- leaf: implement-general-2/send-invitation-modal · source: send-invitation-modal.md -->

**Rules** (cite as `implement-general-2/send-invitation-modal#<slug>`):

- `seed-sections-from-props` MUST
- `hide-empty-sections` MUST
- `recipients-are-read-only` MUST
- `provide-note-per-section` MUST
- `assemble-send-payload` MUST
- `disable-send-when-empty` MUST
- `confirm-cancel-when-populated` MUST
- `no-enter-to-send` MUST
- `block-dismissal-when-busy` MUST
- `reset-on-close` MUST
- `label-controls` MUST
- `custom-title` MUST

# SendInvitationModal

## Overview

A modal in `@agentic-toolkit/adh-ui` for sending invitations over email and/or SMS. It
composes `Dialog` + `RecipientInput` + `Textarea` + `AlertModal` + `Button`. It is
invoked with seed lists of emails/phones from a recipient selection made elsewhere in
the caller's app. The actual send is delegated entirely to a caller-supplied `onSend`
callback.

It is a controlled dialog with up to two sections — **SMS** and **Email** — each
shown only when its seed list is non-empty. Each section displays a read-only
recipient list and an optional admin note. The footer cancels (with confirm if
populated) or sends.

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| AlertAndDialog | agenticdevelopertoolkit://recipes/alert-and-dialog | The `Dialog` shell (`DialogContent max-w-lg`) + the discard-confirm `AlertModal` | yes | modal semantics; discard-confirm copy |
| RecipientInput | agenticdevelopertoolkit://recipes/recipient-input | Per-section recipient list (`kind="email"` / `kind="phone"`) | yes | `kind`, seeded `value`, `readOnly` |

Composed shared primitives without their own recipe domains: `Textarea` (the
per-section admin note), `FieldGroup`/`Field`/`Label` (section structure +
labels), and `Button` (footer Cancel/Send).

## Integration Requirements

- **seed-sections-from-props**: On open, the Email section MUST seed its `RecipientInput` from `emails` and the SMS section MUST seed from `phones`. Seeding happens once, at mount: changes to `emails`/`phones` while the modal stays mounted do NOT re-seed it — the caller MUST pass a changing `key` prop to force a remount when seeding a new selection.
- **hide-empty-sections**: A section MUST NOT be rendered when its seed list is empty or absent (an email-only batch shows only the Email section).
- **recipients-are-read-only**: Each rendered section's `RecipientInput` MUST render read-only. This modal performs no validation or deduplication of `emails`/`phones`; the recipients shown are exactly the caller-provided seed list, unchanged for the life of the mount.
- **provide-note-per-section**: Each rendered section MUST include an optional admin-note `Textarea`.
- **assemble-send-payload**: Send MUST assemble a `SendInvitationPayload` containing one entry per rendered section (every rendered section has ≥1 recipient by construction, since recipients are read-only and always equal to the seed), each with its full recipient list and its note text included verbatim — untrimmed, and as `""` when empty — and MUST call `onSend` with it.
- **disable-send-when-empty**: Send MUST be disabled when no section is rendered, i.e. both `emails` and `phones` are empty or absent.
- **confirm-cancel-when-populated**: Cancel, Esc, or a backdrop click MUST run the same populated check: when the form is populated — at least one of the email or SMS note is non-empty, including a whitespace-only note; pre-seeded recipients alone never count as populated — it MUST open an `AlertModal` discard confirm ("Discard this invitation?" / Cancel · Discard, with Discard `destructive` — red and Enter-to-confirm disabled), closing only on confirm; when not populated it MUST close immediately.
- **no-enter-to-send**: Enter MUST NOT trigger Send from anywhere in the modal — the Send control has no default/submit binding, and Enter in the note `Textarea` inserts a newline rather than submitting. This is a separate rule from confirm-cancel-when-populated's own Enter-to-confirm-discard rule for the Discard button.
- **block-dismissal-when-busy**: When `busy` is true, the Send `Button` MUST be disabled and MUST show a spinner in place of its label, and the modal MUST block all dismissal outright — Cancel, Esc, and backdrop click are ignored with no discard confirm shown, even when the form is populated.
- **reset-on-close**: The modal MUST reset its state (recipients, notes, and the discard-confirm) on close.
- **label-controls**: Each `RecipientInput` and `Textarea` MUST be labeled, and the `Dialog` MUST provide modal semantics with focus trap and restore.
- **custom-title**: The `Dialog` title MUST render the `title` prop's text, defaulting to "Send invitation" when the prop is omitted.

## Layout

```
┌ Send invitation ───────────────────────────────────────┐
│  SMS                                                    │  ← only if phones seed non-empty
│  Recipients  ( +1 555 0100 )                            │  ← read-only, seeded
│  Note (opt.) [                              ]           │
│                                                         │
│  EMAIL                                                  │  ← only if emails seed non-empty
│  Recipients  ( ada@x.io )( grace@x.io )                 │  ← read-only, seeded
│  Note (opt.) [                              ]           │
│                                                         │
│                                  [ Cancel ]  [ Send ]   │
└─────────────────────────────────────────────────────────┘
```

- `DialogContent` (`max-w-lg`); sections as `FieldGroup` blocks; labels via `Field`/`Label`. Footer right-justified `[ Cancel ][ Send ]`; Send uses the `Button` component's default variant with no color override — the gold accent styles the dialog `Title`, not the Send button.
- No raw hex; no `!important`.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| email recipients (`string[]`) | SendInvitationModal (seeded once from `emails` at mount) | Email `RecipientInput` (read-only), Send payload | Down only | Component state, seeded from props |
| sms recipients (`string[]`) | SendInvitationModal (seeded once from `phones` at mount) | SMS `RecipientInput` (read-only), Send payload | Down only | Component state, seeded from props |
| email note / sms note | SendInvitationModal | Section `Textarea`s, Send payload | Down / Up | Component state |
| discardConfirm open | SendInvitationModal | AlertAndDialog (AlertModal) | Down | Boolean state |
| busy | Caller | Send + dismissal guard + spinner | Down | Prop |
| open | Caller | Dialog | Down | Prop (`open`); `onClose` up |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | seed-sections-from-props, hide-empty-sections | open with `emails` only | only the Email section renders, seeded from `emails` |
| T2 | hide-empty-sections | open with `phones` only | only the SMS section renders |
| T3 | hide-empty-sections | open with both | both sections render |
| T4 | assemble-send-payload | open with `emails=["a@x.io","b@x.io"]`, `phones=["+15550100"]`; type "Hi" into the email note; click Send | `onSend` called with `{ email: { recipients: ["a@x.io","b@x.io"], note: "Hi" }, sms: { recipients: ["+15550100"], note: "" } }` |
| T5 | disable-send-when-empty | open with `emails` and `phones` both empty/absent | no section renders; Send disabled |
| T6 | provide-note-per-section | open with `emails` only | Email section shows a labeled, optional note `Textarea` |
| T7 | recipients-are-read-only | attempt to remove a seeded recipient chip | no removal occurs; `RecipientInput` accepts no edits |
| T8 | confirm-cancel-when-populated | Cancel on a freshly opened, unedited modal | closes immediately (pre-seeded recipients alone are not "populated") |
| T9 | confirm-cancel-when-populated | type text into a note, then Cancel | discard confirm opens |
| T10 | confirm-cancel-when-populated | type text into a note, then press Esc | discard confirm opens |
| T11 | confirm-cancel-when-populated | type text into a note, then click the backdrop | discard confirm opens |
| T12 | confirm-cancel-when-populated | discard confirm open, click Discard | modal closes and resets |
| T13 | confirm-cancel-when-populated | discard confirm open, click Cancel (stay) | confirm closes; modal remains open with its text intact |
| T14 | no-enter-to-send | focus the note `Textarea`, press Enter | a newline is inserted; Send is not triggered |
| T15 | block-dismissal-when-busy | `busy=true`, Esc/backdrop/Cancel | dismissal blocked; Send disabled; spinner shown; no discard confirm even if populated |
| T16 | reset-on-close | populate a note, close via Discard, reopen (new `key`) | note is empty again; recipients re-seeded from current props |
| T17 | label-controls | inspect rendered DOM | each `RecipientInput` and `Textarea` has an accessible label; `Dialog` traps and restores focus |
| T18 | custom-title | open without a `title` prop, then with `title="Invite teammates"` | dialog heading reads "Send invitation", then "Invite teammates" |

## API

```ts
interface SendInvitationPayload {
  email?: { recipients: string[]; note: string }
  sms?: { recipients: string[]; note: string }
}
interface SendInvitationModalProps {
  open: boolean
  emails?: string[]      // seed Email section; section hidden when empty/absent
  phones?: string[]      // seed SMS section; section hidden when empty/absent
  onSend: (payload: SendInvitationPayload) => void
  onClose: () => void
  busy?: boolean
  title?: string         // default "Send invitation"
}
export function SendInvitationModal(props: SendInvitationModalProps): React.ReactElement
```

