---
id: 633ab7e7-828e-4e7d-b2dc-9ba189536b6e
title: "SendInvitationModal"
domain: agentictoolkit://recipes/send-invitation-modal
type: recipe
version: 1.1.0
status: review
language: en
created: 2026-06-26
modified: 2026-09-23
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
invoked with seed lists of emails/phones (e.g. from the admin "Pending Users"
selection). The actual send is a caller callback (`onSend`) — stubbed in Phase 2,
wired in Phase 3.

It is a controlled dialog with up to two sections — **Email** and **SMS** — each
shown only when its seed list is non-empty. Each section edits a recipient list
and an optional admin note. The footer cancels (with confirm if dirty) or sends.

## Ingredients

| Name | Domain | Role | Required | Configuration |
|---|---|---|---|---|
| AlertAndDialog | agenticdevelopertoolkit://recipes/alert-and-dialog | The `Dialog` shell (`DialogContent max-w-lg`) + the discard-confirm `AlertModal` | yes | modal semantics; discard-confirm copy |
| RecipientInput | agenticdevelopertoolkit://recipes/recipient-input | Per-section recipient list (`kind="email"` / `kind="phone"`) | yes | `kind`, seeded `value` |

Composed shared primitives without their own recipe domains: `Textarea` (the
per-section admin note), `FieldGroup`/`Field`/`Label` (section structure +
labels), and `Button` (footer Cancel/Send).

## Integration Requirements

- **seed-sections-from-props**: On open, the Email section MUST seed its `RecipientInput` from `emails` and the SMS section MUST seed from `phones`.
- **hide-empty-sections**: A section MUST NOT be rendered when its seed list is empty or absent (an email-only batch shows only the Email section).
- **provide-note-per-section**: Each rendered section MUST include an optional admin-note `Textarea`.
- **assemble-send-payload**: Send MUST assemble a `SendInvitationPayload` containing only the rendered sections that still have ≥1 recipient, and MUST call `onSend` with it.
- **disable-send-when-empty**: Send MUST be disabled when no rendered section has any recipient.
- **confirm-cancel-when-populated**: Cancel, Esc, or a backdrop click MUST open an `AlertModal` discard confirm ("Discard this invitation?" / Cancel · Discard, with Discard `destructive` — red and Enter-to-confirm disabled) when the form is populated (any section has ≥1 recipient or any note has text), closing only on confirm; when not populated it MUST close immediately.
- **block-dismissal-when-busy**: When `busy` is true the modal MUST show a spinner and MUST block dismissal.
- **reset-on-close**: The modal MUST reset its state on close.
- **label-controls**: Each `RecipientInput` and `Textarea` MUST be labeled, and the `Dialog` MUST provide modal semantics with focus trap and restore.

## Layout

```
┌ Send invitation ───────────────────────────────────────┐
│  EMAIL                                                  │  ← only if emails seed non-empty
│  Recipients  [ (ada@x.io ×)(grace@x.io ×) ┃ ]           │
│  Note (opt.) [                              ]           │
│                                                         │
│  SMS                                                    │  ← only if phones seed non-empty
│  Recipients  [ (+1 555 0100 ×) ┃ ]                      │
│  Note (opt.) [                              ]           │
│                                                         │
│                                  [ Cancel ]  [ Send ]   │
└─────────────────────────────────────────────────────────┘
```

- `DialogContent` (`max-w-lg`); sections as `FieldGroup` blocks; labels via `Field`/`Label`. Footer right-justified `[ Cancel ][ Send ]` (Send = gold).
- No raw hex; no `!important`.

## Shared State

| State | Source | Consumer | Direction | Mechanism |
|---|---|---|---|---|
| email recipients (`string[]`) | SendInvitationModal (seeded from `emails`) | Email `RecipientInput`, Send payload | Down / Up | Component state + `RecipientInput` onChange |
| sms recipients (`string[]`) | SendInvitationModal (seeded from `phones`) | SMS `RecipientInput`, Send payload | Down / Up | Component state + `RecipientInput` onChange |
| email note / sms note | SendInvitationModal | Section `Textarea`s, Send payload | Down / Up | Component state |
| discardConfirm open | SendInvitationModal | AlertAndDialog (AlertModal) | Down | Boolean state |
| busy | Caller | Send + dismissal guard + spinner | Down | Prop |
| open | Caller | Dialog | Down | Prop (`open`); `onClose` up |

## Integration Test Vectors

| ID | Requirements | Input | Expected |
|---|---|---|---|
| T1 | seed-sections-from-props, hide-empty-sections | open with `emails` only | only the Email section renders, seeded |
| T2 | hide-empty-sections | open with `phones` only | only the SMS section renders |
| T3 | hide-empty-sections | open with both | both sections render |
| T4 | assemble-send-payload | Send with recipients in one section | payload contains only the non-empty section |
| T5 | disable-send-when-empty | clear all recipients | Send disabled |
| T6 | confirm-cancel-when-populated | Cancel with recipients/note present | discard confirm opens |
| T7 | confirm-cancel-when-populated | Cancel when not populated | closes immediately |
| T8 | block-dismissal-when-busy | `busy=true`, Esc/backdrop/Cancel | dismissal blocked; spinner shown |

## Edge Cases

- A modal seeded with recipients is considered populated, so an immediate Cancel still confirms.
- The Send payload omits any section that has been emptied of recipients, even if it was rendered.
- Send is disabled while every rendered section has zero recipients.
- Backdrop and Esc follow the same dirty check as Cancel.
- State resets on close, so reopening re-seeds from the current props.

## Platform Notes

- **SwiftUI**: Present via a custom modal container (e.g. a `.sheet` with `.interactiveDismissDisabled(busy)` to block dismissal while busy) holding the same two conditional sections. Recipients render as a wrapping row of removable chip `Button`s bound to `@State private var emailRecipients: [String]` / `smsRecipients`; the note is a `TextEditor`. Footer buttons are `Button("Cancel")` (`.buttonStyle(.plain)`) and `Button("Send")` (`.buttonStyle(.borderedProminent)`, tinted gold, `.disabled(!canSend || busy)`), with a `ProgressView()` swapped in for the label while busy. The discard confirm uses `.confirmationDialog` with a `.destructive`-role button and no default (Enter-triggered) action, matching the source's non-Enter-to-confirm behavior.
- **Compose**: Present as a custom `Dialog` (not `AlertDialog`, to host two sections) with `DialogProperties(dismissOnClickOutside = !busy, dismissOnBackPress = !busy)` for the busy-dismissal block. Each section's recipients render as a `FlowRow` of Material 3 `InputChip`s with trailing remove icons over `remember { mutableStateListOf<String>() }`; the note is a multiline `OutlinedTextField`. The footer is `TextButton("Cancel")` + `Button("Send", enabled = canSend && !busy)` with a `CircularProgressIndicator` inside the button label while busy. Discard confirms with a second `AlertDialog` whose confirm button uses the M3 error color, mirroring the source's destructive-styled, non-default discard action.
- **React/Web (TypeScript)** (source platform): New block at `websites/shared/ui/src/blocks/send-invitation-modal.tsx`. Composes `Dialog*`, `RecipientInput`, `Textarea`, `FieldGroup`, `Field`, `AlertModal`, `Button`. Consumed by the admin "Pending Users" topic (sub-project 4) "Send invitation" action. Add a demo to `ui-showcase` (+ regenerate sources), and verify responsively via Playwright (ui-showcase) at 375 / 768 / 1440 — sections stack and the footer (`[ Cancel ][ Send ]`) stays reachable on mobile.
- **AppKit / UIKit**: On macOS, present via `NSWindow.beginSheet` hosting the same two-section layout; the closest native analog to `RecipientInput`'s editable chip list is `NSTokenField` (bind `objectValue` to the recipient array); the note is an `NSTextView` in a scroll view; footer `NSButton`s use `.bezelStyle(.rounded)`, with the Send button's `keyEquivalent` cleared so Enter does not submit, matching the source's non-Enter-to-confirm discard. Discard confirms with an `NSAlert` (`.alertStyle = .warning`) with a destructively-styled button. On iOS, present as a `UIViewController` with `.pageSheet`/`.formSheet` presentation and `isModalInPresentation = busy` to block swipe-to-dismiss while busy; recipients render in a compositional-layout `UICollectionView` of removable chip cells; the note is a `UITextView`; footer buttons are `UIButton` configurations (`.plain()` Cancel, `.filled()` Send, `isEnabled = canSend && !busy`) with a `UIActivityIndicatorView` shown in the Send button while busy; discard confirms via a `UIAlertController(preferredStyle: .alert)` with a `.destructive` action.
- **WinUI 3**: Host in a `ContentDialog` (`DefaultButton="Primary"`, `PrimaryButtonText="Send"`, `SecondaryButtonText="Cancel"`, `IsPrimaryButtonEnabled` bound to `CanSend`). WinUI has no built-in chip/token input, so each recipients row needs a custom `ItemsControl` with a `WrapPanel` `ItemsPanelTemplate` hosting removable-chip `Button`s, bound to an `ObservableCollection<string>`; the note is a `TextBox` with `AcceptsReturn="True" TextWrapping="Wrap"`. `ContentDialog` cannot show a spinner inside its own footer buttons, so the busy state is shown by setting `PrimaryButtonText` to an empty string and overlaying a `ProgressRing IsActive="{x:Bind Busy}"` in the dialog content; busy-dismissal is blocked by handling the `Closing` event and setting `args.Cancel = true` when `Busy` is true, since `ContentDialog` has no dismissal-blocking property of its own. Because WinUI does not allow two `ContentDialog`s open on the same `XamlRoot` at once, the discard confirm MUST close the first dialog (`await`ing its `ShowAsync` result) before showing a second `ContentDialog` styled as a warning (`DefaultButton="Close"`, an error-brush-styled `SecondaryButtonText="Discard"`) — a sequencing constraint with no analog in the web source's alert-stacked-over-dialog presentation.

API (`@agentic-toolkit/adh-ui/blocks/send-invitation-modal`):

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

## Design Decisions

- **Decision**: A section is hidden entirely when its seed list is empty.
  **Rationale**: An email-only batch should not present an empty SMS section.
  `Approved: pending`

- **Decision**: Each section carries its own admin-note box.
  **Rationale**: Per the brief — email and SMS invitations may warrant distinct notes.
  `Approved: pending`

- **Decision**: Cancel confirms whenever the form is populated (a seeded modal counts as populated).
  **Rationale**: Prevents accidental loss of a prepared invitation.
  `Approved: pending`

- **Decision**: `onSend` is stubbed in Phase 2 and wired in Phase 3.
  **Rationale**: Phased rollout of the feature.
  `Approved: pending`

## Compliance

| Check | Status | Category |
|---|---|---|
| [recipe-formatting](agenticdevelopercookbook://compliance/artifact-formatting#recipe-formatting) | passed | artifact-formatting |
| [no-raw-hex-no-important](agenticdevelopercookbook://compliance/adh-ui-guidelines#no-raw-hex-no-important) | passed | adh-ui-guidelines |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Set status to review; filled the WinUI 3 Platform Notes bullet and completed SwiftUI/Compose/AppKit-UIKit translation guidance; dropped `must-` prefix from requirement ids; reformatted Design Decisions and Compliance per cookbook conventions. |
| 1.0.0 | 2026-06-26 | Mike Fullerton | Initial conversion from legacy UI spec. |
