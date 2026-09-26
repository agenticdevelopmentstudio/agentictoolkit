---
id: 633ab7e7-828e-4e7d-b2dc-9ba189536b6e
title: "SendInvitationModal"
domain: agentictoolkit://cookbook/adh-ui/blocks/send-invitation-modal
type: recipe
version: 1.2.1
status: review
language: en
created: 2026-06-26
modified: 2026-09-25
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "A controlled dialog that sends invitations over email and/or SMS, with a recipient list + optional note per section, seeded from caller lists."
platforms:
  - typescript
  - web
tags:
  - modal
  - dialog
  - invitations
  - recipients
ingredients:
  - agenticdevelopertoolkit://recipes/alert-and-dialog
  - agenticdevelopertoolkit://recipes/recipient-input
depends-on: []
related: []
references: []
---

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

## Edge Cases

- Recipients are seeded once at mount and are never mutated by this modal (`RecipientInput` renders read-only); re-seeding for a new selection only happens if the caller changes the `key` prop to force a remount.
- Pre-seeded recipients alone do not make the form "populated" — only note text does, so an unmodified, freshly opened modal closes immediately on Cancel/Esc/backdrop even though its sections show recipients.
- A single whitespace character in either note counts as populated and triggers the discard confirm.
- The Send payload always includes one entry per rendered section, each carrying that section's untrimmed note, sent as `""` when the note is empty.
- Send is disabled only when neither `emails` nor `phones` was seeded, so no section renders.
- While `busy`, Cancel/Esc/backdrop are blocked outright — no discard confirm is shown even for a populated form.
- State (including notes and the discard confirm) resets on close, so reopening via a remount re-seeds from the current props.

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

## Platform Notes

- **SwiftUI**: Present via a custom modal container (e.g. a `.sheet`) holding the same two conditional sections (SMS, then Email). Because `.interactiveDismissDisabled(busy)` only gates swipe-to-dismiss on `busy`, route the swipe gesture through the same populated check as Cancel (e.g. an intercepted drag on the sheet background) rather than relying on it alone — see **confirm-cancel-when-populated** and **block-dismissal-when-busy**. Recipients render read-only as a wrapping row of non-removable chip `Text`/`Label` views bound to `@State private var emailRecipients: [String]` / `smsRecipients`, seeded once at init; the note is a `TextEditor`. Footer buttons are `Button("Cancel")` (`.buttonStyle(.plain)`, no `.keyboardShortcut`, so Enter never triggers it) and `Button("Send")` (`.buttonStyle(.borderedProminent)`, default tint — no gold; the gold accent is reserved for the dialog title — `.disabled(!canSend || busy)`, also with no `.keyboardShortcut(.defaultAction)` so Enter never triggers Send), with a `ProgressView()` swapped in for the label while busy. The discard confirm uses `.confirmationDialog` with a `.destructive`-role button and no default (Enter-triggered) action — a separate rule from Send's own no-Enter behavior above.
- **Compose**: Present as a custom `Dialog` (not `AlertDialog`, to host two sections, SMS then Email). `DialogProperties(dismissOnClickOutside = !busy, dismissOnBackPress = !busy)` blocks dismissal while busy per **block-dismissal-when-busy**; when not busy, wire `onDismissRequest` to run the same populated check as Cancel rather than dismissing directly, per **confirm-cancel-when-populated**. Each section's recipients render read-only as a `FlowRow` of Material 3 `InputChip`s (no remove icon) over a list seeded once from the incoming prop; the note is a multiline `OutlinedTextField`. The footer is `TextButton("Cancel")` + `Button("Send", enabled = canSend && !busy)`, neither bound to the IME/hardware Enter action, so Enter never triggers Send, with a `CircularProgressIndicator` inside the button label while busy. Discard confirms with a second `AlertDialog` whose confirm button uses the M3 error color and is not the dialog's default/Enter-bound action, mirroring the source's destructive-styled, non-Enter-to-confirm discard action.
- **React/Web (TypeScript)** (source platform): Block at `packages/web/packages/adh-ui/src/blocks/send-invitation-modal.tsx`. Composes `Dialog*`, `RecipientInput` (read-only), `Textarea`, `FieldGroup`, `Field`, `AlertModal`, `Button`. Consumed by callers that seed `emails`/`phones` from a recipient selection made elsewhere in the app, then remount (via a changing `key`) to re-seed for a new selection. Add a demo to `ui-showcase` (+ regenerate sources), and verify responsively via Playwright (ui-showcase) at 375 / 768 / 1440 — sections stack and the footer (`[ Cancel ][ Send ]`) stays reachable on mobile.
- **AppKit / UIKit**: On macOS, present via `NSWindow.beginSheet` hosting the same two-section layout; since recipients render read-only, macOS needs no editable token control — a non-interactive `NSCollectionView` (or a wrapping `NSStackView` of chip-styled labels) of chip cells is enough, mirroring iOS below; the note is an `NSTextView` in a scroll view; footer `NSButton`s use `.bezelStyle(.rounded)`, with the Send button's `keyEquivalent` cleared so Enter never triggers Send, per **no-enter-to-send** — a separate rule from the Discard alert's own non-Enter-to-confirm behavior below. Discard confirms with an `NSAlert` (`.alertStyle = .warning`) whose destructively-styled button is not bound to Return, matching **confirm-cancel-when-populated**'s own non-Enter-to-confirm discard. On iOS, present as a `UIViewController` with `.pageSheet`/`.formSheet` presentation and `isModalInPresentation = busy` to block swipe-to-dismiss while busy, plus `presentationControllerDidAttemptToDismiss` to run the same populated check as Cancel when not busy; recipients render in a compositional-layout `UICollectionView` of non-removable chip cells; the note is a `UITextView`; footer buttons are `UIButton` configurations (`.plain()` Cancel, `.filled()` Send, `isEnabled = canSend && !busy`, neither set as the view's default/Return-bound action) with a `UIActivityIndicatorView` shown in the Send button while busy; discard confirms via a `UIAlertController(preferredStyle: .alert)` with a `.destructive` action that is likewise not the alert's Return-bound action.
- **WinUI 3**: Host in a `ContentDialog` (`DefaultButton="None"`, `PrimaryButtonText="Send"`, `SecondaryButtonText="Cancel"`, `IsPrimaryButtonEnabled` bound to `CanSend`) — `DefaultButton` is `None` rather than `Primary` so Enter never triggers Send, per **no-enter-to-send**. WinUI has no built-in chip/token input, so each recipients row needs a custom `ItemsControl` with a `WrapPanel` `ItemsPanelTemplate` hosting non-removable chip-styled `Border`/`TextBlock` items, bound to a fixed `ObservableCollection<string>` populated once at open; the note is a `TextBox` with `AcceptsReturn="True" TextWrapping="Wrap"`. `ContentDialog` cannot show a spinner inside its own footer buttons, so the busy state is shown by setting `PrimaryButtonText` to an empty string and overlaying a `ProgressRing IsActive="{x:Bind Busy}"` in the dialog content. Dismissal handling goes through the `Closing` event: when `Busy` is true, set `args.Cancel = true` unconditionally (**block-dismissal-when-busy**); when not busy, run the same populated check as Cancel there too — cancel the close and show the discard `ContentDialog` instead of letting `Closing` dismiss directly — so that `ContentDialog`'s built-in Escape handling doesn't bypass **confirm-cancel-when-populated**. Because WinUI does not allow two `ContentDialog`s open on the same `XamlRoot` at once, the discard confirm MUST close the first dialog (`await`ing its `ShowAsync` result) before showing a second `ContentDialog` styled as a warning (`DefaultButton="Close"`, an error-brush-styled `SecondaryButtonText="Discard"`) — a sequencing constraint with no analog in the web source's alert-stacked-over-dialog presentation.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-ui/src/blocks/send-invitation-modal.tsx` |

## Design Decisions

- **Decision**: A section is hidden entirely when its seed list is empty.
  **Rationale**: An email-only batch should not present an empty SMS section.
  **Approved**: pending

- **Decision**: Each section carries its own admin-note box.
  **Rationale**: Email and SMS messages differ enough in tone and length — SMS favors brevity — that a shared note would force a compromise; the component tracks `emailNote` and `smsNote` as independent state so each channel's message can be written separately.
  **Approved**: pending

- **Decision**: Recipients render read-only in this modal.
  **Rationale**: They are seeded from a selection the caller already made elsewhere (e.g. picking pending users), which the backend keys the invite off of; letting an admin edit them here would let the invite diverge from what was actually selected.
  **Approved**: pending

- **Decision**: Discard confirmation depends only on whether a note has been typed — pre-seeded recipients alone do not count as "populated".
  **Rationale**: Recipients are read-only and always present when a section renders, so treating them as populated would force a confirm on every single Cancel; only user-entered note text represents work that could be lost.
  **Approved**: pending

- **Decision**: Enter never triggers Send.
  **Rationale**: The note field is a multi-line `Textarea` where Enter must insert a newline, so Send requires an explicit activation of the Send control rather than an implicit keyboard submit.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|---|---|---|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | Accessibility |
| [semantic-markup](agenticdevelopercookbook://compliance/accessibility#semantic-markup) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [reduced-motion](agenticdevelopercookbook://compliance/accessibility#reduced-motion) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | failed | Security |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy & Data |

Statuses rest on: `ariaLabel`'d `RecipientInput`s, text-labeled `Button`s, and the `Dialog` primitive's built-in focus trap/restore for the passed Accessibility checks, against the default theme spacing/typography the source doesn't itself verify for the partial ones and the `animate-spin` busy indicator shown with no `prefers-reduced-motion` gating in source; the hardcoded English strings ("Send invitation", "Cancel", "Send", "Note (optional)", the aria-labels) for the failed Internationalization checks, against the `Textarea`'s unrestricted-Unicode input for the passed one; the `Textarea` note forwarded to `onSend` with no validation or trimming for the failed Security check; and the single optional note field layered on top of the caller-seeded, read-only recipient lists for the passed Privacy & Data check.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-23 | Mike Fullerton | Lint pass: corrected the populated/dirty and recipient-editing claims to match the read-only `RecipientInput` and note-only dirty check in source; added recipients-are-read-only, no-enter-to-send, and custom-title requirements; tightened busy and payload-shape wording; fixed the React/Web block path and dropped app-specific Phase/Pending-Users/sub-project wording, removing the phase-rollout design decision; corrected the Send-button color claim and the WinUI/AppKit/SwiftUI/Compose/iOS Enter-key and swipe-dismiss platform notes; moved the API block into its own section before Platform Notes; reformatted the Design Decisions Approved line and rebuilt Compliance with real Accessibility/Internationalization/Security/Privacy & Data checks; added test vectors for note-per-section, read-only recipients, reset-on-close, label-controls, Esc/backdrop, Discard/Cancel-in-confirm, Enter, and custom-title, and gave T4 a concrete payload. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Set status to review; filled the WinUI 3 Platform Notes bullet and completed SwiftUI/Compose/AppKit-UIKit translation guidance; dropped `must-` prefix from requirement ids; reformatted Design Decisions and Compliance per cookbook conventions. |
| 1.0.0 | 2026-06-26 | Mike Fullerton | Initial conversion from legacy UI spec. |
