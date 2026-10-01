---
id: b976c0d2-084c-4a47-928a-14e33983077f
title: Messaging Client
domain: agentictoolkit://cookbook/adh/hub/messaging/messaging-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The client-side contract for the Hub''s Messaging feature: a data-source operation set
  for status/templates/log/send, the wire types those operations carry, and the rail navigation,
  provider-status banners, and placeholder-gated send form built on top of them.'
platforms:
- swift
- macos
- ios
tags:
- hub
- messaging
- data-source
- forms
- templates
depends-on: []
related:
- agentictoolkit://cookbook/ui/navigation/htdv
references:
- packages/apple/AgenticToolkit/Hub/Features/Messaging/MessagingModels.swift (apple)
- packages/apple/AgenticToolkit/Hub/Features/Messaging/MessagingTopic.swift (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/MessagingTopicTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# Messaging Client

## Overview

This is the client-side contract for the Hub's "Messaging" product topic: a wire-type set
(a channel/status pair, a template, a log entry and a page of them, a send request and its
result) plus the data-source operation set every network call is delegated to; and the topic
logic that resolves the rail path into a "Send a message" compose form and a "Message log"
list/detail pair, using the injected data source for provider-connectivity status, template
listing, log paging, and the send call itself. Every thrown error from the template-listing,
log-listing, and send operations is normalized to a common error type before it reaches a caller;
a status-check failure is the one exception, deliberately swallowed to a degraded-but-usable
banner rather than propagated.

## Behavioral Requirements

**Data source contract**

- **provider-status**: the status operation MUST return, asynchronously, the connectivity status
  (an `email`/`sms` connectivity pair) for the given ecosystem, or throw.
- **template-listing**: the template-listing operation MUST return, asynchronously, the full list
  of templates available for composing a message, or throw.
- **message-log-listing**: the log operation MUST return, asynchronously, a page of log entries
  (the requested `page`/`pageSize` plus `items` and `total`) for the given ecosystem, or throw.
- **message-send**: the send operation MUST submit the given send request and return,
  asynchronously, a send result, or throw.

**Data shapes**

- **messaging-channel-identity**: the channel type MUST expose exactly two values, `email` and
  `sms`, with a fixed `title` ("Email"/"SMS"), `providerName` ("Postmark"/"Twilio"),
  `providerLabel` (`"{title} ({providerName})"`), and an icon identifier ("envelope"/"message")
  for each value.
- **template-placeholder-scan**: a template's placeholder list MUST contain the `{{name}}`
  placeholder names found across `subject`, `htmlBody`, `textBody`, and `smsBody` (treated as
  `""` when absent) joined in that order, trimmed, de-duplicated, in first-seen order — the
  `subject` counts because a template whose only placeholder sits in its subject would otherwise
  report none and skip the send form's required-variable gate entirely.
- **log-entry-shape**: a log entry MUST expose `id`, `customerId`, `ecosystemId`, `channel`,
  `recipient`, `body`, and `status` as required fields, and `subject`, `templateId`, `providerId`,
  `errorMessage`, `sentBy`, `origin`, and `createdAt` as independently optional fields.
- **log-page-shape**: a log page MUST expose `items` (the page's list of log entries), `total`,
  `page`, and `pageSize`.
- **send-request-shape**: a send request MUST expose a required `userId` and `channel`, with
  `subject`, `body`, `templateId`, `templateVars`, and `recipient` each independently optional.
- **send-result-shape**: a send result MUST expose a required `status` string plus independently
  optional `providerId` and `error` fields.

**Copy helpers**

- **status-line-text**: the status-line text MUST be `"Provider status unavailable"` for an
  absent status, and otherwise MUST join, with `" · "`, one `"{channel.title}: connected"` or
  `"{channel.title}: not connected"` segment per channel, in `email`, `sms` order.
- **banner-text-connected**: the banner text MUST be absent when the given channel's status is
  connected.
- **banner-text-not-connected**: the banner text MUST be `"{channel.providerLabel} is not
  connected — sends on this channel will fail. Connect a {channel.providerName} integration on
  this product's Integrations tab."` when the given channel's status is not connected.
- **banner-text-unknown**: the banner text MUST be `"Couldn't check whether
  {channel.providerLabel} is connected — sends on this channel may fail."` when the status is
  absent.
- **placeholder-extraction**: the placeholder scan MUST scan the given text with a pattern
  matching two braces, a captured run of non-brace characters, then two braces again, MUST trim
  each captured name, MUST skip an empty trimmed name, and MUST return the surviving names
  de-duplicated in first-seen order.

**Navigation**

- **rail-top-level**: resolving the rail path MUST return a navigation level with two items —
  `"send"` ("Send a message", leading to a detail view) and `"log"` ("Message log", leading to a
  list) — when the path's first segment is absent, with the `"send"` item's `sublabel` set from
  the status-line text.
- **rail-status-swallowed-at-top-level**: the top-level branch MUST fetch the status operation
  without propagating its failure, so a status-operation failure MUST NOT prevent the level from
  rendering — it MUST instead produce the status-line text for an absent status ("Provider status
  unavailable") as the `"send"` item's `sublabel`.
- **rail-send-route**: a path whose first segment is `"send"` MUST resolve to the send detail
  view.
- **rail-log-route**: a path whose first segment is `"log"` MUST resolve to the log child,
  resolved with the remaining path segments.
- **rail-unknown-route-empty**: a path whose first segment is neither `"send"` nor `"log"` MUST
  resolve to no content.

**Send form**

- **send-detail-load-errors-propagate**: the send detail MUST fetch the template-listing
  operation without swallowing its failure, and a failure MUST be wrapped into the common error
  type and rethrown — never swallowed.
- **send-detail-status-swallowed**: the send detail MUST also fetch the status operation without
  propagating its failure, the same graceful-degradation rule as
  `rail-status-swallowed-at-top-level`.
- **send-form-provider-banners**: for every channel whose banner text is present, the send detail
  MUST add one read-only field, keyed `"{channel}Status"` and labeled with that channel's provider
  label, whose value is that banner text, collected into a form section titled `"Provider status"`
  inserted at the front of the form's sections — and MUST NOT insert that section when no banner
  applies.
- **send-form-default-values**: the send form's initial values MUST set `"channel"` to `"email"`
  and `"templateId"` to `""`.
- **send-form-field-order**: building the send form MUST declare, in order, an unlabeled section
  with a required `"channel"` select (options `email`, `sms`), a required `"userId"` text field
  (label "Customer ID", placeholder "customer id"), and an optional `"recipient"` text field
  (label "Recipient override"), followed by a section titled "Content" with an optional
  `"templateId"` select (label "Content", options: the freeform option plus one option per
  template), an optional `"subject"` text field (label "Subject", placeholder "Email only"), an
  optional `"body"` text-area field (label "Message body", minimum 3 lines), and an optional
  `"templateVars"` JSON field (label "Template variables").
- **send-form-required-tiers**: only `"channel"` and `"userId"` MUST be marked required at the
  field level (rejected by the shared form validator before the save action runs); `"recipient"`,
  `"subject"`, `"body"`, and `"templateId"` MUST NOT be field-level required — their conditional
  requirements are enforced inside the save action instead.
- **send-freeform-subject-required-for-email**: when no template is selected and the channel is
  email, the save action MUST fail validation with "Enter a subject." when the trimmed
  `"subject"` value is blank.
- **send-freeform-body-required**: when no template is selected, the save action MUST fail
  validation with "Enter a message body." when the trimmed `"body"` value is blank, regardless of
  channel.
- **send-freeform-subject-suppressed-for-sms**: when no template is selected and the channel is
  SMS, the save action MUST set the send request's `subject` to absent even when a `"subject"`
  value was entered.
- **send-sms-recipient-required**: when the channel is SMS, the save action MUST fail validation
  with "A recipient phone number is required for SMS." when the trimmed `"recipient"` value is
  blank, checked before any other field is validated.
- **send-template-must-exist**: when `"templateId"` is non-blank, the save action MUST fail
  validation with "Choose a template." when no template in the list the send form was built from
  has that `id`.
- **send-template-placeholder-validation**: when a template is selected, the save action MUST
  parse `"templateVars"` and MUST fail validation with `Template needs a value for "{name}".` for
  the first placeholder (in the template's placeholder-list order) whose trimmed value is blank or
  absent, checking one placeholder at a time rather than collecting every missing one in a single
  failure.
- **send-template-vars-parsing**: parsing the template variables MUST return an empty object when
  the trimmed text is blank, MUST parse a non-blank text as JSON, and MUST fail validation with
  "Template variables must be a JSON object of strings." when the parsed value is not a JSON
  object whose every value is a string.
- **send-channel-fallback-to-email**: the save action MUST resolve `"channel"` against the two
  known values and MUST fall back to email when the submitted value does not match `"email"` or
  `"sms"`.
- **send-invokes-data-source**: on successful validation, the save action MUST call the send
  operation with the assembled send request, and any thrown error MUST be wrapped into the common
  error type and rethrown.
- **send-result-failure-messaging**: when the returned send result's `status` is not `"sent"`,
  the save action MUST fail validation with the trimmed `error` message when non-blank, or the
  fixed fallback message ("Could not send — check the recipient and provider config.") otherwise.
- **freeform-option-identity**: the freeform option MUST be the select option with `value: ""`
  and `title: "Freeform message"`, and MUST be the first option in the `"templateId"` select.
- **send-form-has-no-delete-action**: building the send form MUST NOT expose a delete action.

**Message log**

- **log-fetch-errors-propagate**: resolving the log child MUST fetch the log operation with
  `page: 1, pageSize: logPageSize` without swallowing its failure, and a failure MUST be wrapped
  into the common error type and rethrown.
- **log-list-item-mapping**: when no entry id follows in the path, resolving the log child MUST
  return a navigation level mapping each log page entry to an item with `label = recipient`,
  `sublabel = "{channel.title} · {status} · {displayDate(createdAt)}"`, an icon from the channel's
  icon identifier, and leading to a detail view, with an empty-state message of "No messages sent
  yet."
- **log-page-request-shape**: every call this logic makes to the log operation MUST request
  `page: 1` and `pageSize: logPageSize` (100).
- **log-pagination**: resolving the log child always requests `page: 1` and never reads the log
  page's `total` or requests `page: 2` or later, although the decoded wire shape (`total`, `page`,
  `pageSize`) carries what a paged view needs. The log shows at most the newest `logPageSize`
  (100) sent messages, with no indication that older entries exist.
- **log-entry-lookup**: when an entry id follows in the path, resolving the log child MUST return
  no content when no entry in the fetched page has that `id`, and otherwise MUST return a detail
  view for the matching log entry.
- **log-entry-detail-fields**: the entry detail MUST present, in order, read-only `"channel"`
  (`channel.title`), `"recipient"` (monospaced), `"subject"` (the trimmed subject or `"—"`), and
  `"status"` fields, then an `"error"` field only when `errorMessage` is non-blank, then `"body"`
  and `"sent"` (the formatted `createdAt`) — and MUST NOT present `sentBy`, `origin`,
  `templateId`, or `providerId` even though a log entry carries them.
- **log-entry-detail-identity**: the entry detail's `id` MUST be `"messaging-log-entry:{entry.id}"`
  and its `title` MUST be the trimmed `subject` or `"Message"` when blank.
- **log-entry-detail-has-no-actions**: the log entry detail MUST expose neither a save action nor
  a delete action — it is read-only.

## Appearance

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## States

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## Accessibility

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-msg-001 | placeholder-extraction | The placeholder scan applied to `"Hi {{name}}, {{ code }} and {{name}}"` | `["name", "code"]` — trimmed, de-duplicated, first-seen order |
| hub-msg-002 | template-placeholder-scan | A template's placeholder list, for a template with `subject: "Welcome, {{name}}!"`, `textBody: "Plain"`, `smsBody` absent | `["name"]` — counted even though the only placeholder is in `subject` |
| hub-msg-003 | status-line-text | The status-line text for `{email: true, sms: false}`, and for an absent status | `"Email: connected · SMS: not connected"` and `"Provider status unavailable"` |
| hub-msg-004 | banner-text-connected, banner-text-not-connected, banner-text-unknown | The banner text for the email channel with status `{email: true, sms: false}`; for the SMS channel with the same status; for the email channel with an absent status | Absent; a string ending `"...Integrations tab."`; `"Couldn't check whether Email (Postmark) is connected — sends on this channel may fail."` |
| hub-msg-005 | rail-top-level, rail-status-swallowed-at-top-level | Resolving the top-level rail against a fake data source whose status operation throws an offline error | Returns without throwing; the first item's `sublabel` is `"Provider status unavailable"` |
| hub-msg-006 | send-form-provider-banners, send-form-field-order | Resolving the send form with status `email: true, sms: false` | The form's field keys, in order, are `["smsStatus", "channel", "userId", "recipient", "templateId", "subject", "body", "templateVars"]` |
| hub-msg-007 | send-form-required-tiers | Save invoked with every field blank | The `userId` field's error is `"Customer ID is required"`; no send request is recorded (the save action never runs) |
| hub-msg-008 | send-freeform-subject-required-for-email, send-freeform-body-required | Save with `userId` set, `channel` left at its email default, `subject` then `body` supplied one at a time | First failure: the save error is `"Enter a subject."`; after `subject` is set, second failure: the save error is `"Enter a message body."` |
| hub-msg-009 | send-sms-recipient-required, send-freeform-subject-suppressed-for-sms | Save with `channel: "sms"`, `userId` and `body` set, `recipient` blank then supplied | First failure: the save error is `"A recipient phone number is required for SMS."`; after `recipient` is set, the send succeeds with the send request's `subject` absent |
| hub-msg-010 | send-template-placeholder-validation | Save with a template requiring `{{name}}` and `{{code}}`, `templateVars` omitted, then supplied one variable at a time | First failure: `"Template needs a value for \"name\"."`; second failure (after `name` supplied): `"Template needs a value for \"code\"."`; third attempt (both supplied) succeeds |
| hub-msg-011 | send-template-vars-parsing | `templateVars` set to `["a"]` (a JSON array) with a template selected | The save error is `"Template variables must be a JSON object of strings."` |
| hub-msg-012 | send-template-must-exist | Save with `templateId` set to an id absent from the templates the send form was built from | The save error is `"Choose a template."` |
| hub-msg-013 | send-result-failure-messaging | The send operation returns a result with `status: "failed", error: "Recipient rejected"`, then again with `error` absent | First: the save error is `"Recipient rejected"`; second: the save error is the fixed fallback message |
| hub-msg-014 | send-channel-fallback-to-email | Save invoked with `channel` set to `"carrier-pigeon"` and all other required fields valid | The recorded send request's channel is email |
| hub-msg-015 | send-detail-load-errors-propagate, log-fetch-errors-propagate | The template-listing operation (respectively the log operation) throws an unauthorized error | Resolving the `["send"]` path (respectively `["log"]`) throws that same unauthorized error unchanged |
| hub-msg-016 | log-list-item-mapping, log-page-request-shape | Resolving the `["log"]` level with two log entries, one `email`/`"sent"` and one `sms`/`"failed"` | The level's id is `"messaging-log:{ecosystemID}"`; items' labels are both recipients; the second item's icon identifier is `"message"`; the empty-state message is `"No messages sent yet."`; the fake records a request for `page: 1, pageSize: 100` |
| hub-msg-017 | log-entry-detail-fields, log-entry-lookup | Resolving the log entry detail for an entry with `errorMessage` set, and again for one without | With error: field keys include `"error"`; without: field keys omit it; neither includes `sentBy`, `origin`, `templateId`, or `providerId` |
| hub-msg-018 | log-entry-lookup | Resolving the `["log", "nope"]` path, and the `["nope"]` path | Both return no content |

## Edge Cases

- **Blank required fields**: `"channel"` and `"userId"` blank MUST be rejected by the shared
  form validator (`"Customer ID is required"`) before the save action's own body ever runs (MUST).
- **Blank conditionally-required fields**: `"subject"` (email freeform), `"body"` (any freeform),
  and `"recipient"` (SMS) are not field-level required, so a blank value MUST be caught by the save
  action's own checks instead, in the order recipient (SMS only) → subject (email freeform only) →
  body (MUST).
- **Blank or whitespace-only `templateVars`**: MUST parse to an empty key-value object rather than
  throwing, given a trim-and-blank check (MUST).
- **Template with no placeholders**: MUST be sendable with `templateVars` empty, since the
  placeholder-validation loop has nothing to iterate (MUST).
- **Boundary: exactly `logPageSize` (100) log entries**: the log level MUST render all 100 without
  requesting a second page; entries beyond 100 are not shown (see **log-pagination**) (MUST).
- **Malformed `templateVars` JSON**: parsing fails with a validation error ("Invalid JSON: ...")
  for text that is not valid JSON at all (not just not-an-object), and that error MUST propagate
  through the save action unchanged, since parsing the template variables does not catch it (MUST).
- **Concurrent access**: this logic holds no mutable stored state, so no synchronization primitive
  is needed within one instance; nothing here coordinates two independent form instances (for
  example two open Send forms) submitting against the same ecosystem concurrently — each send is
  validated and dispatched independently, and both would be recorded as separate log entries with
  no deduplication (this is an absent feature, not a race this recipe documents any ordering rule
  for; MUST NOT be assumed to be serialized).
- **Error states**: the template-listing, log, and send operations' failures MUST propagate
  unchanged (wrapped into the common error type) to the caller; the status operation's failures
  MUST instead degrade to the absent-status status line / a per-channel "Couldn't check..." banner
  rather than blocking the rail or the Send form (MUST, per `rail-status-swallowed-at-top-level` /
  `send-detail-status-swallowed`).
- **Offline or unreachable backend**: an offline or transport error thrown by the template-listing,
  log, or send operations MUST propagate unchanged; a status-operation offline failure is swallowed
  instead, so a user can still open and fill out the Send form while offline, only to have the send
  itself throw when actually attempted (MUST).
- **Cancellation**: every data-source call has no explicit cancellation handling in this logic
  beyond what the underlying asynchronous runtime provides by default; a surrounding cancellation
  is expected to propagate as a thrown error through the same path any other error takes, so it is
  wrapped into the common error type (or, for the status operation, swallowed) exactly like any
  other failure (MUST — this is a guarantee the runtime provides with no extra code, not a gap).
- **Unrecognized send-result status**: any value other than the literal string `"sent"` (including
  an unrecognized one such as `"queued"`) MUST be treated as a failure and reported via the save
  error, never as success (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (initializer parameter) | data source reference | none (required) | Backs the status/template-listing/log/send operations. |
| `logPageSize` | integer (static) | `100` | `pageSize` passed to every log-operation call; `page` is always `1`. |
| `freeformOption` | select option (static) | `value: "", title: "Freeform message"` | The "no template selected" option in the Content select. |
| `sendFailedMessage` | string (static) | `"Could not send — check the recipient and provider config."` | Fallback save-error text when a failed send's `error` field is blank. |
| channel-type values | string-backed enumeration | fallback `email` on an unparsable form value | The two channels (`email`, `sms`) a message can be sent on. |

## Deep Linking

Not applicable: this logic registers no URL scheme, universal link, or platform
activity-continuation record; navigation is entirely through path arrays supplied by the
presentation layer that hosts this topic.

## Localization

This logic contains no localization mechanism (no localized-string API, no string-catalog file,
no localization lookup) — every user-facing string below is a hardcoded English literal, stated
here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Provider status unavailable` | The status-line text's fallback for an absent status |
| — | `{Email/SMS} ({Postmark/Twilio})` | The channel type's `providerLabel`, built from its hardcoded titles and provider names |
| — | `{providerLabel} is not connected — sends on this channel will fail. Connect a {providerName} integration on this product's Integrations tab.` | The banner text's not-connected message |
| — | `Couldn't check whether {providerLabel} is connected — sends on this channel may fail.` | The banner text's unknown-status message |
| — | `Send email or SMS to this product's users and review what went out.` | This topic's rail-entry description |
| — | `A recipient phone number is required for SMS.` | SMS recipient-required validation |
| — | `Choose a template.` | Unknown-template-id validation |
| — | `Template needs a value for "{name}".` | Missing-placeholder validation |
| — | `Enter a subject.` | Freeform-email subject-required validation |
| — | `Enter a message body.` | Freeform body-required validation |
| — | `Template variables must be a JSON object of strings.` | The template-variables parse-shape validation |
| — | `Could not send — check the recipient and provider config.` | The fixed send-failure fallback message |
| — | `No messages sent yet.` | The log level's empty-state message |
| — | `Freeform message` | The freeform option's title |

(This is a representative sample, not the full set of literals — every one follows the same
pattern: a plain string with no key, no catalog entry, and no pluralization rule beyond ad hoc
string interpolation.)

## Accessibility Options

Not applicable: this is a data-source contract and rail-navigation controller with no UI of its
own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: this logic reads no feature-flag key and contains no conditional feature-gating
logic.

## Analytics

Not applicable: this logic contains no analytics/event-emission call.

## Privacy

- **Data collected**: this component itself collects nothing new — it reads and forwards
  recipient contact information (an email address or phone number, via the send request's
  `recipient` field or the log entry's `recipient` field the log already contains) and message
  content (`subject`, `body`, `templateVars`) that the caller supplies or the backend has already
  recorded.
- **Storage**: this logic writes none of this to disk or to platform-managed credential/preference
  storage; the topic logic holds no mutable stored state at all, so nothing it handles outlives
  the current form's/detail's state.
- **Transmission**: the send operation transmits the assembled send request (recipient,
  subject/body or template selection and variables) to the injected data source; the log operation
  receives already-sent message content, including recipient and body, back from it. Actual
  network transport is the injected data source's concern, out of scope of this recipe.
- **Retention**: not controlled by this logic — the backend behind the data source owns how long a
  log entry (recipient, subject, body) persists; this logic only reads and displays whatever the
  backend currently returns.

## Logging

Not applicable: this logic contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to these two files directly — `MessagingTopic` returns
  `HTDVLevel`/`HTDVDetail`/`FormSpec` values consumed by the shared `FormViewController`/HTDV
  presentation layer; a SwiftUI-based presenter would consume the same values unchanged, since
  `MessagingTopic.swift` imports no SwiftUI and performs no rendering itself.
- **AppKit / UIKit**: this is the source. `MessagingModels.swift` and `MessagingTopic.swift` live
  in the `Hub` module shared between the `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS`
  targets (both declared in `project.yml`, one source set). Neither file imports `AppKit` or
  `UIKit` directly — `MessagingModels.swift` is plain `Foundation`, and `MessagingTopic.swift` adds
  only `AgenticToolkitHTDV`, with the platform-specific `NSViewController`/`UIViewController` split
  handled entirely inside `FormViewController`, one layer below where these types operate.
  Concurrency: `MessagingTopic` is declared `@MainActor final class`, so `child(for:path:rail:)`
  and every private helper it calls run only on the main actor; `MessagingDataSource` is declared
  `AnyObject, Sendable` so a conforming instance can be injected into and called from that
  `@MainActor`-isolated type while performing its own network work off the main actor. Because the
  send form's save closure captures only `Sendable` value types (or a `Sendable` protocol
  reference) and mutates no property of `MessagingTopic` itself, `FormAction.perform`'s plain
  `@Sendable` (non-`@MainActor`) execution context needs no explicit `MainActor.run` hop to run it
  safely — unlike a topic that mutates its own `@MainActor`-isolated state from inside a save
  action. `MessagingTopic` holds no mutable stored property beyond its immutable `dataSource`
  reference, so no lock, queue, or other synchronization primitive is needed within a single
  instance; and the placeholder scan, the template-variables parser, and the fixed send-failure
  message are all declared `nonisolated` because each is called from a context that is not
  guaranteed to be the main actor — the placeholder scan from `MessagingTemplate.placeholders` (a
  plain, non-isolated struct), and the other two from the save closure's `@Sendable`,
  non-`@MainActor` context. Cancellation: every data-source call is a plain `try await` with no
  explicit cancellation handling in either file; Swift's structured concurrency propagates a
  surrounding task's cancellation as a thrown `CancellationError` through the same path any other
  error takes. Deep linking registers no `NSUserActivity`; navigation is entirely through
  `HTDVItem`/`HTDVChild` path arrays. Neither file writes to `UserDefaults` or the Keychain, and
  neither contains an `os_log`, `Logger`, or `print` call; localization uses none of
  `String(localized:)`, a `.strings`/`.xcstrings` catalog, or `NSLocalizedString`.
- **Compose**: a Kotlin port would model `MessagingStatus`/`MessagingTemplate`/`MessagingLogEntry`/
  `MessagingLogPage`/`MessagingSend`/`MessagingSendResult` as immutable `data class`es and
  `MessagingChannel` as a Kotlin `enum class` exposing the same `title`/`providerName`/
  `providerLabel`/`systemImage` accessors, `MessagingTopic` as a class exposing a `suspend fun
  child(...)` returning a sealed `HtdvChild`, and the placeholder regex as a plain `Regex` shared
  between the template model and the topic (mirroring the cross-file call the Swift source makes);
  no view model needs its own coroutine-confined mutable state, since the Swift type holds none
  either.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  plain `MessagingChannel` union/lookup table for the per-channel copy, and `async` functions
  returning `Promise<HtdvChild>` for `child(...)`; the "validate one missing placeholder at a time"
  behavior and the "swallow `status()`, propagate everything else" asymmetry both need to be
  reproduced deliberately, since neither falls out of the language the way `MessagingTopic`'s
  statelessness does.
- **WinUI 3**: a .NET port would model `MessagingStatus`, `MessagingTemplate`, `MessagingLogEntry`,
  `MessagingLogPage`, `MessagingSend`, and `MessagingSendResult` as `record`s (free structural
  equality, mirroring the Swift `Hashable` conformances) and `MessagingChannel` as an `enum` with a
  small extension class or switch-based helper exposing the same `Title`/`ProviderName`/
  `ProviderLabel`/`SystemImage`-equivalent values. `IMessagingDataSource` would expose
  `Task<MessagingStatus> GetStatusAsync(string ecosystemId)`,
  `Task<MessagingSendResult> SendAsync(string ecosystemId, MessagingSend message)`, etc., backed by
  `HttpClient` + `System.Text.Json`. `MessagingTopic`'s equivalent would be a stateless view-model
  class with `async Task<HtdvChild> ChildAsync(...)`, needing no `Dispatcher`/`SynchronizationContext`
  confinement at all — unlike a Hub feature that holds per-instance mutable state on its
  `@MainActor` — and the placeholder regex would be a static, compiled `System.Text.RegularExpressions.Regex`
  shared by the template model and the topic, mirroring the source's one-regex-two-call-sites
  design; the log level's fixed `page: 1` request would translate directly, with the same
  unresolved question of what happens past the first `PageSize` (100) items.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Messaging/` |

## Design Decisions

**Decision**: `status(ecosystemID:)` failures are swallowed to `nil` with `try?` at both the
top-level rail (`rail-status-swallowed-at-top-level`) and inside the Send detail
(`send-detail-status-swallowed`), while `templates()`, `log(...)`, and `send(...)` failures are all
passed through `HubError.wrap(_:)` and rethrown.
**Rationale**: provider connectivity status is an auxiliary signal, not required to render the
rail or the compose form — degrading it to `"Provider status unavailable"` or a per-channel
"Couldn't check whether..." banner keeps both pages usable, whereas `templates`, `log`, and `send`
are the operations the user actually asked for and must surface a real failure rather than a
misleadingly quiet form.
**Approved**: pending

**Decision**: `send-template-placeholder-validation` reports one missing template variable per
save attempt (the loop throws on the first `HubText.nonBlank(vars[name]) == nil`) rather than
collecting every missing variable into one message.
**Rationale**: not documented beyond the surrounding doc comment explaining why the scan itself
covers the subject (see `template-placeholder-scan`); the practical effect is that a template with
several missing variables needs several round trips through the form to fully diagnose.
**Approved**: pending

**Decision**: `MessagingTemplate.placeholders` (defined in `MessagingModels.swift`) calls
`MessagingTopic.placeholders(in:)` (defined in `MessagingTopic.swift`) rather than each file
carrying its own copy of the regex.
**Rationale**: per the source's own comment, `placeholders(in:)` is declared `nonisolated`
specifically so this "plain, non-isolated struct" can call it synchronously; sharing the one scan
keeps the model and the send form from ever disagreeing on placeholder syntax, at the cost of a
model type depending on its topic/controller type rather than the more usual direction.
**Applies to**: Swift/Apple — the `nonisolated` mechanism that makes the synchronous cross-file
call safe is Swift-specific; a port on another platform can share the same scan with a plain
function call and no isolation annotation.
**Approved**: pending

**Decision**: the log level always requests `page: 1` with `pageSize: MessagingTopic.logPageSize`
and never reads `MessagingLogPage.total` or requests a later page.
**Rationale**: not documented in the source; the effect is a most-recent-100 log view (see
**log-pagination**).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | partial | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | failed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` is `partial`: `MessagingDataSource` cleanly isolates every network call
behind a protocol `MessagingTopic` depends on but never implements, but `MessagingModels.swift`'s
`MessagingTemplate.placeholders` reaches back into `MessagingTopic.placeholders(in:)` — a model
type calling into its own controller type, the inverse of the usual dependency direction, even
though the source's own comment shows this was a deliberate choice to share one regex rather than
duplicate it. `unit-test-coverage` passes: `MessagingTopicTests.swift` exercises every operation
with a fake data source, including the subject-only-placeholder regression, both provider-status
banners, every send validation path, and the log list/detail/not-found paths. `explicit-error-
handling` passes: every throwing path other than `status(...)` routes through `HubError.wrap(_:)`
or a specific validation throw; the one place an error is swallowed (`status(...)`, via `try?`) is
a documented, signaled degradation (a fallback banner), not a silent loss. `no-hardcoded-strings`
fails outright — see Localization; there is no localization mechanism anywhere in either file.
`error-recovery` fails: neither file retries, backs off, or queues a failed call — every
`MessagingDataSource` invocation other than `status(...)` is a single `try await`/`try` that
throws straight through to the caller on any failure. `idempotent-operations` fails: nothing in
`send-invokes-data-source` attaches an idempotency key or otherwise guards against the same
`MessagingSend` being submitted twice by a retried or double-triggered save. `data-integrity` is
`partial`: the send path validates its own shape thoroughly before submitting (required fields,
placeholder coverage, JSON shape), but see **log-pagination** — `total` is
decoded from every log page and never checked, so a log with more entries than `logPageSize` gives
no signal that its display is incomplete.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/messaging/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
