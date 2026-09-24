---
id: b976c0d2-084c-4a47-928a-14e33983077f
title: Hub Domain Messaging
domain: agentictoolkit://recipes/hub-domain-messaging
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The client-side contract for the Hub''s Messaging feature: MessagingDataSource''s
  status/templates/log/send operations, MessagingModels'' wire types (MessagingChannel,
  MessagingTemplate, MessagingLogEntry/MessagingLogPage, MessagingSend/MessagingSendResult),
  and MessagingTopic''s rail navigation, provider-status banners, and placeholder-gated
  send form, cited to their Swift sources and tests.'
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
- agentictoolkit://recipes/htdv-engine
references:
- packages/apple/AgenticToolkit/Hub/Features/Messaging/MessagingModels.swift (apple)
- packages/apple/AgenticToolkit/Hub/Features/Messaging/MessagingTopic.swift (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/MessagingTopicTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# Hub Domain Messaging

## Overview

Two Swift files under `packages/apple/AgenticToolkit/Hub/Features/Messaging/` form the
client-side contract for the Hub's "Messaging" product topic: `MessagingModels.swift` holds
the `Codable`/`Sendable` wire types (`MessagingChannel`, `MessagingStatus`, `MessagingTemplate`,
`MessagingLogEntry`, `MessagingLogPage`, `MessagingSend`, `MessagingSendResult`) plus the
`MessagingDataSource` protocol every network call is delegated to; and `MessagingTopic`
(`MessagingTopic.swift`) is the `@MainActor` `EcosystemTopicProvider` that resolves the rail
path into a "Send a message" compose form and a "Message log" list/detail pair, using the
injected data source for provider-connectivity status, template listing, log paging, and the
send call itself. Every thrown error from `templates()`, `log(...)`, and `send(...)` is
normalized to `HubError` before it reaches a caller (`HubError.wrap`); a `status(...)` failure is
the one exception, deliberately swallowed to a degraded-but-usable banner rather than propagated.

## Behavioral Requirements

**Data source contract (`MessagingDataSource`)**

- **provider-status**: `status(ecosystemID:)` MUST return, asynchronously, the `MessagingStatus`
  (an `email`/`sms` connectivity pair) for the given ecosystem, or throw.
- **template-listing**: `templates()` MUST return, asynchronously, the full `[MessagingTemplate]`
  available for composing a message, or throw.
- **message-log-listing**: `log(ecosystemID:page:pageSize:)` MUST return, asynchronously, a
  `MessagingLogPage` (the requested `page`/`pageSize` plus `items` and `total`) for the given
  ecosystem, or throw.
- **message-send**: `send(ecosystemID:_:)` MUST submit the given `MessagingSend` and return,
  asynchronously, a `MessagingSendResult`, or throw.

**Data shapes**

- **messaging-channel-identity**: `MessagingChannel` MUST expose exactly two cases, `email` and
  `sms`, with fixed `title` ("Email"/"SMS"), `providerName` ("Postmark"/"Twilio"), `providerLabel`
  (`"\(title) (\(providerName))"`), and `systemImage` ("envelope"/"message") values for each case.
- **template-placeholder-scan**: `MessagingTemplate.placeholders` MUST return the `{{name}}`
  placeholder names found across `subject`, `htmlBody`, `textBody`, and `smsBody` (treated as `""`
  when `nil`) joined in that order, trimmed, de-duplicated, in first-seen order — per the type's
  own doc comment, the `subject` counts because a template whose only placeholder sits in its
  subject would otherwise report none and skip the send form's required-variable gate entirely.
- **log-entry-shape**: `MessagingLogEntry` MUST expose `id`, `customerId`, `ecosystemId`,
  `channel`, `recipient`, `body`, and `status` as required fields, and `subject`, `templateId`,
  `providerId`, `errorMessage`, `sentBy`, `origin`, and `createdAt` as independently optional
  fields.
- **log-page-shape**: `MessagingLogPage` MUST expose `items` (the page's `[MessagingLogEntry]`),
  `total`, `page`, and `pageSize`.
- **send-request-shape**: `MessagingSend` MUST expose a required `userId` and `channel`, with
  `subject`, `body`, `templateId`, `templateVars`, and `recipient` each independently optional.
- **send-result-shape**: `MessagingSendResult` MUST expose a required `status` string plus
  independently optional `providerId` and `error` fields.

**Copy helpers (`MessagingTopic` statics)**

- **status-line-text**: `statusLine(_:)` MUST return `"Provider status unavailable"` for a `nil`
  status, and otherwise MUST join, with `" · "`, one `"\(channel.title): connected"` or
  `"\(channel.title): not connected"` segment per `MessagingChannel.allCases` in that case order.
- **banner-text-connected**: `bannerText(for:status:)` MUST return `nil` when the given channel's
  status is connected.
- **banner-text-not-connected**: `bannerText(for:status:)` MUST return `"\(channel.providerLabel)
  is not connected — sends on this channel will fail. Connect a \(channel.providerName)
  integration on this product's Integrations tab."` when the given channel's status is not
  connected.
- **banner-text-unknown**: `bannerText(for:status:)` MUST return `"Couldn't check whether
  \(channel.providerLabel) is connected — sends on this channel may fail."` when `status` is
  `nil`.
- **placeholder-extraction**: `placeholders(in:)` MUST scan the given text with the pattern
  matching two braces, a captured run of non-brace characters, then two braces again, MUST trim
  each captured name, MUST skip an empty trimmed name, and MUST return the surviving names
  de-duplicated in first-seen order.

**Navigation (`MessagingTopic.child`)**

- **rail-top-level**: `child(for:path:rail:)` MUST return `.level(...)` with two items — `"send"`
  ("Send a message", `leadsTo: .detail`) and `"log"` ("Message log", `leadsTo: .list`) — when
  `RailPath.id(at: 0, in: path)` is `nil`, with the `"send"` item's `sublabel` set from
  `statusLine(_:)`.
- **rail-status-swallowed-at-top-level**: the top-level branch MUST fetch `dataSource.status(...)`
  with `try?`, so a `status(...)` failure MUST NOT prevent the level from rendering — it MUST
  instead produce `statusLine(nil)` ("Provider status unavailable") as the `"send"` item's
  `sublabel`.
- **rail-send-route**: a path whose first segment is `"send"` MUST resolve to
  `.detail(sendDetail(for:))`.
- **rail-log-route**: a path whose first segment is `"log"` MUST resolve to `logChild(for:path:)`
  called with the remaining path segments.
- **rail-unknown-route-empty**: a path whose first segment is neither `"send"` nor `"log"` MUST
  resolve to `.empty`.

**Send form (`MessagingTopic.sendDetail` / `sendSpec`)**

- **send-detail-load-errors-propagate**: `sendDetail(for:)` MUST fetch `dataSource.templates()`
  with a plain `try`, and a failure MUST be passed through `HubError.wrap(_:)` and rethrown —
  never swallowed.
- **send-detail-status-swallowed**: `sendDetail(for:)` MUST also fetch `dataSource.status(...)`
  with `try?`, the same graceful-degradation rule as `rail-status-swallowed-at-top-level`.
- **send-form-provider-banners**: for every channel in `MessagingChannel.allCases` whose
  `bannerText(for:status:)` is non-`nil`, `sendDetail(for:)` MUST add one read-only field, keyed
  `"\(channel.rawValue)Status"` and labeled `channel.providerLabel`, whose value is that banner
  text, collected into a `FormSection` titled `"Provider status"` inserted at the front of the
  form's sections — and MUST NOT insert that section when no banner applies.
- **send-form-default-values**: the send form's initial values MUST set `"channel"` to
  `MessagingChannel.email.rawValue` and `"templateId"` to `""`.
- **send-form-field-order**: `sendSpec(for:templates:)` MUST declare, in order, an unlabeled
  section with a required `"channel"` select (options from `MessagingChannel.allCases`), a
  required `"userId"` text field (label "Customer ID", placeholder "customer id"), and an optional
  `"recipient"` text field (label "Recipient override"), followed by a section titled "Content"
  with an optional `"templateId"` select (label "Content", options `[freeformOption] +` one
  `FormSelectOption` per template), an optional `"subject"` text field (label "Subject", placeholder
  "Email only"), an optional `"body"` text-area field (label "Message body", `minLines: 3`), and an
  optional `"templateVars"` JSON field (label "Template variables").
- **send-form-required-tiers**: only `"channel"` and `"userId"` MUST be marked `isRequired` at the
  field level (rejected by the shared form validator before the save action runs); `"recipient"`,
  `"subject"`, `"body"`, and `"templateId"` MUST NOT be field-level required — their conditional
  requirements are enforced inside the save action instead.
- **send-freeform-subject-required-for-email**: when no template is selected and `channel ==
  .email`, the save action MUST throw `HubError.validation("Enter a subject.")` when the trimmed
  `"subject"` value is blank.
- **send-freeform-body-required**: when no template is selected, the save action MUST throw
  `HubError.validation("Enter a message body.")` when the trimmed `"body"` value is blank,
  regardless of channel.
- **send-freeform-subject-suppressed-for-sms**: when no template is selected and `channel == .sms`,
  the save action MUST set `MessagingSend.subject` to `nil` even when a `"subject"` value was
  entered.
- **send-sms-recipient-required**: when `channel == .sms`, the save action MUST throw
  `HubError.validation("A recipient phone number is required for SMS.")` when the trimmed
  `"recipient"` value is blank, checked before any other field is validated.
- **send-template-must-exist**: when `"templateId"` is non-blank, the save action MUST throw
  `HubError.validation("Choose a template.")` when no template in the list passed to
  `sendSpec(for:templates:)` has that `id`.
- **send-template-placeholder-validation**: when a template is selected, the save action MUST
  parse `"templateVars"` and MUST throw `HubError.validation("Template needs a value for
  \"{name}\".")` for the first placeholder (in `MessagingTemplate.placeholders` order) whose
  trimmed value is blank or absent, checking one placeholder at a time rather than collecting every
  missing one in a single failure.
- **send-template-vars-parsing**: `templateVars(from:)` MUST return `[:]` when the trimmed text is
  blank, MUST parse a non-blank text as JSON via `JSONValue.parse(_:)`, and MUST throw
  `HubError.validation("Template variables must be a JSON object of strings.")` when the parsed
  value is not a JSON object whose every value is a string.
- **send-channel-fallback-to-email**: the save action MUST resolve `"channel"` via
  `MessagingChannel(rawValue:)` and MUST fall back to `.email` when the submitted value does not
  match `"email"` or `"sms"`.
- **send-invokes-data-source**: on successful validation, the save action MUST call
  `dataSource.send(ecosystemID:_:)` with the assembled `MessagingSend`, and any thrown error MUST
  be passed through `HubError.wrap(_:)` and rethrown.
- **send-result-failure-messaging**: when the returned `MessagingSendResult.status != "sent"`, the
  save action MUST throw `HubError.validation(...)` with the trimmed `error` message when
  non-blank, or `MessagingTopic.sendFailedMessage` ("Could not send — check the recipient and
  provider config.") otherwise.
- **freeform-option-identity**: `MessagingTopic.freeformOption` MUST be the `FormSelectOption`
  with `value: ""` and `title: "Freeform message"`, and MUST be the first option in the
  `"templateId"` select.
- **send-form-has-no-delete-action**: `sendSpec(for:templates:)` MUST NOT set
  `FormActions.delete`.

**Message log (`MessagingTopic.logChild`)**

- **log-fetch-errors-propagate**: `logChild(for:path:)` MUST fetch `dataSource.log(ecosystemID:
  page: 1, pageSize: MessagingTopic.logPageSize)` with a plain `try`, and a failure MUST be passed
  through `HubError.wrap(_:)` and rethrown.
- **log-list-item-mapping**: when no entry id follows in `path`, `logChild(for:path:)` MUST return
  `.level(...)` mapping each `MessagingLogPage.items` entry to an item with `label = recipient`,
  `sublabel = "\(channel.title) · \(status) · \(HubDates.display(createdAt))"`, `systemImage =
  channel.systemImage`, and `leadsTo: .detail`, with `emptyMessage: "No messages sent yet."`.
- **log-page-request-shape**: every call this component makes to `log(ecosystemID:page:pageSize:)`
  MUST request `page: 1` and `pageSize: MessagingTopic.logPageSize` (100).
- **log-pagination**: `logChild` always requests `page: 1` and never reads `MessagingLogPage.total` or requests `page: 2` or later, although the decoded wire shape (`total`, `page`, `pageSize`) carries what a paged view needs. The log shows at most the newest `MessagingTopic.logPageSize` (100) sent messages, with no indication that older entries exist.
- **log-entry-lookup**: when an entry id follows in `path`, `logChild(for:path:)` MUST return
  `.empty` when no entry in the fetched page has that `id`, and otherwise MUST return
  `.detail(...)` for the matching `MessagingLogEntry`.
- **log-entry-detail-fields**: the entry detail MUST present, in order, read-only `"channel"`
  (`channel.title`), `"recipient"` (monospaced), `"subject"` (the trimmed subject or `"—"`), and
  `"status"` fields, then an `"error"` field only when `errorMessage` is non-blank, then `"body"`
  and `"sent"` (`HubDates.display(createdAt)`) — and MUST NOT present `sentBy`, `origin`,
  `templateId`, or `providerId` even though `MessagingLogEntry` carries them.
- **log-entry-detail-identity**: the entry detail's `id` MUST be `"messaging-log-entry:{entry.id}"`
  and its `title` MUST be the trimmed `subject` or `"Message"` when blank.
- **log-entry-detail-has-no-actions**: the log entry detail's `FormSpec` MUST NOT set
  `FormActions.save` or `FormActions.delete` — it is read-only.

**Concurrency and isolation**

- **main-actor-isolation**: `MessagingTopic` MUST be declared `@MainActor final class`, so its
  `child(for:path:rail:)` and every private helper it calls run only on the main actor.
- **sendable-data-source-protocol**: `MessagingDataSource` MUST be declared `AnyObject, Sendable`,
  so a conforming instance can be injected into and called from the `@MainActor`-isolated
  `MessagingTopic` while performing its own network work off the main actor.
- **send-action-needs-no-main-actor-hop**: because `sendSpec(for:templates:)`'s save closure
  captures only `dataSource`, `templates`, and `ecosystem` (all `Sendable` value types or a
  `Sendable` protocol reference) and mutates no property of `MessagingTopic` itself,
  `FormAction.perform`'s plain `@Sendable` (non-`@MainActor`) execution context needs no explicit
  `MainActor.run` hop to run it safely — unlike a topic that mutates its own `@MainActor`-isolated
  state from inside a save action.
- **stateless-topic-instance**: `MessagingTopic` MUST hold no mutable stored property beyond its
  immutable `dataSource` reference, so no lock, queue, or other synchronization primitive is
  needed within a single instance.
- **nonisolated-pure-statics**: `placeholders(in:)`, `templateVars(from:)`, and `sendFailedMessage`
  MUST be declared `nonisolated` because each is called from a context that is not guaranteed to
  be the main actor — `placeholders(in:)` from `MessagingTemplate.placeholders` (a plain,
  non-isolated struct) and `templateVars(from:)`/`sendFailedMessage` from `sendSpec`'s
  `@Sendable`, non-`@MainActor` save closure.

## Appearance

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## States

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## Accessibility

Not applicable — this is the client-side Messaging data-source contract and rail-navigation logic, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-msg-001 | placeholder-extraction | `MessagingTopic.placeholders(in: "Hi {{name}}, {{ code }} and {{name}}")` | `["name", "code"]` — trimmed, de-duplicated, first-seen order |
| hub-msg-002 | template-placeholder-scan | `MessagingTemplate.fixture(subject: "Welcome, {{name}}!", textBody: "Plain", smsBody: nil).placeholders` | `["name"]` — counted even though the only placeholder is in `subject` |
| hub-msg-003 | status-line-text | `MessagingTopic.statusLine(MessagingStatus(email: true, sms: false))` and `statusLine(nil)` | `"Email: connected · SMS: not connected"` and `"Provider status unavailable"` |
| hub-msg-004 | banner-text-connected, banner-text-not-connected, banner-text-unknown | `bannerText(for: .email, status: MessagingStatus(email:true, sms:false))`, `bannerText(for: .sms, status: same)`, `bannerText(for: .email, status: nil)` | `nil`; a string ending `"...Integrations tab."`; `"Couldn't check whether Email (Postmark) is connected — sends on this channel may fail."` |
| hub-msg-005 | rail-top-level, rail-status-swallowed-at-top-level | `rail.level([])` against a fake data source whose `status(...)` throws `.offline` | Returns without throwing; `items[0].sublabel == "Provider status unavailable"` |
| hub-msg-006 | send-form-provider-banners, send-form-field-order | `rail.form(["send"])` with status `email: true, sms: false` | `form.state.spec.fields.map(\.key) == ["smsStatus", "channel", "userId", "recipient", "templateId", "subject", "body", "templateVars"]` |
| hub-msg-007 | send-form-required-tiers | Save invoked with every field blank | `form.state.errors["userId"] == "Customer ID is required"`; `data.sends.isEmpty == true` (the save action never runs) |
| hub-msg-008 | send-freeform-subject-required-for-email, send-freeform-body-required | Save with `userId` set, `channel` left at its email default, `subject` then `body` supplied one at a time | First failure: `saveError == "Enter a subject."`; after `subject` is set, second failure: `saveError == "Enter a message body."` |
| hub-msg-009 | send-sms-recipient-required, send-freeform-subject-suppressed-for-sms | Save with `channel: "sms"`, `userId` and `body` set, `recipient` blank then supplied | First failure: `saveError == "A recipient phone number is required for SMS."`; after `recipient` is set, the send succeeds with `MessagingSend.subject == nil` |
| hub-msg-010 | send-template-placeholder-validation | Save with a template requiring `{{name}}` and `{{code}}`, `templateVars` omitted, then supplied one variable at a time | First failure: `"Template needs a value for \"name\"."`; second failure (after `name` supplied): `"Template needs a value for \"code\"."`; third attempt (both supplied) succeeds |
| hub-msg-011 | send-template-vars-parsing | `templateVars` set to `["a"]` (a JSON array) with a template selected | `saveError == "Template variables must be a JSON object of strings."` |
| hub-msg-012 | send-template-must-exist | Save with `templateId` set to an id absent from the templates passed to `sendSpec` | `saveError == "Choose a template."` |
| hub-msg-013 | send-result-failure-messaging | `dataSource.send` returns `MessagingSendResult(status: "failed", error: "Recipient rejected")`, then again with `error: nil` | First: `saveError == "Recipient rejected"`; second: `saveError == MessagingTopic.sendFailedMessage` |
| hub-msg-014 | send-channel-fallback-to-email | Save invoked with `values["channel"] = .string("carrier-pigeon")` and all other required fields valid | `data.sends.last?.channel == .email` |
| hub-msg-015 | send-detail-load-errors-propagate, log-fetch-errors-propagate | `dataSource.templates()` (respectively `.log(...)`) throws `HubError.unauthorized` | `rail.child(["send"])` (respectively `["log"]`) throws `HubError.unauthorized` unchanged |
| hub-msg-016 | log-list-item-mapping, log-page-request-shape | `rail.level(["log"])` with two log entries, one `email`/`"sent"` and one `sms`/`"failed"` | `level.id == "messaging-log:{ecosystemID}"`; items' `label`s are both recipients; second item's `systemImage == "message"`; `emptyMessage == "No messages sent yet."`; the fake records a request for `page: 1, pageSize: 100` |
| hub-msg-017 | log-entry-detail-fields, log-entry-lookup | `rail.form(["log", entryID])` for an entry with `errorMessage` set, and again for one without | With error: field keys include `"error"`; without: field keys omit it; neither includes `sentBy`, `origin`, `templateId`, or `providerId` |
| hub-msg-018 | log-entry-lookup | `rail.child(["log", "nope"])` and `rail.child(["nope"])` | Both return `.empty` |

## Edge Cases

- **Blank required fields**: `"channel"` and `"userId"` blank MUST be rejected by the shared
  form validator (`"Customer ID is required"`) before the save action's own body ever runs (MUST).
- **Blank conditionally-required fields**: `"subject"` (email freeform), `"body"` (any freeform),
  and `"recipient"` (SMS) are not field-level required, so a blank value MUST be caught by the save
  action's own checks instead, in the order recipient (SMS only) → subject (email freeform only) →
  body (MUST).
- **Blank or whitespace-only `templateVars`**: MUST parse to an empty `[String: String]` rather
  than throwing, per `HubText.nonBlank`'s trim-and-check (MUST).
- **Template with no placeholders**: MUST be sendable with `templateVars` empty, since the
  placeholder-validation loop has nothing to iterate (MUST).
- **Boundary: exactly `logPageSize` (100) log entries**: the log level MUST render all 100 without
  requesting a second page; entries beyond 100 are not shown (see **log-pagination**) (MUST).
- **Malformed `templateVars` JSON**: `JSONValue.parse(_:)` throws `HubError.validation("Invalid
  JSON: ...")` for text that is not valid JSON at all (not just not-an-object), and that error MUST
  propagate through the save action unchanged, since `templateVars(from:)` does not catch it (MUST).
- **Concurrent access**: `MessagingTopic` holds no mutable stored state, so no synchronization
  primitive is needed within one instance; nothing in these two files coordinates two independent
  `FormState` instances (for example two open Send forms) submitting against the same ecosystem
  concurrently — each send is validated and dispatched independently, and both would be recorded as
  separate log entries with no deduplication (this is an absent feature, not a race the source
  documents any ordering rule for; MUST NOT be assumed to be serialized).
- **Error states**: `templates()`, `log(...)`, and `send(...)` failures MUST propagate unchanged
  through `HubError.wrap(_:)` to the caller; `status(...)` failures MUST instead degrade to
  `statusLine(nil)` / a per-channel "Couldn't check..." banner rather than blocking the rail or the
  Send form (MUST, per `rail-status-swallowed-at-top-level` / `send-detail-status-swallowed`).
- **Offline or unreachable backend**: `HubError.offline`/`.transport(...)` thrown by
  `templates()`, `log(...)`, or `send(...)` MUST propagate unchanged; a `status(...)` offline
  failure is swallowed instead, so a user can still open and fill out the Send form while offline,
  only to have the send itself throw when actually attempted (MUST).
- **Cancellation**: every `MessagingDataSource` call is a plain `try await` with no explicit
  cancellation handling in either file; Swift's structured concurrency propagates a surrounding
  task's cancellation as a thrown `CancellationError` through the same path any other error takes,
  so it passes through `HubError.wrap(_:)` (or, for `status(...)`, is swallowed) exactly like any
  other failure (MUST — this is what the language guarantees with no extra code, not a gap).
- **Unrecognized `MessagingSendResult.status`**: any value other than the literal string `"sent"`
  (including an unrecognized one such as `"queued"`) MUST be treated as a failure and reported via
  `saveError`, never as success (MUST).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (`MessagingTopic.init`) | `any MessagingDataSource` | none (required) | Backs `status`/`templates`/`log`/`send`. |
| `MessagingTopic.logPageSize` | `Int` (static) | `100` | `pageSize` passed to every `dataSource.log(...)` call; `page` is always `1`. |
| `MessagingTopic.freeformOption` | `FormSelectOption` (static) | `value: "", title: "Freeform message"` | The "no template selected" option in the Content select. |
| `MessagingTopic.sendFailedMessage` | `String` (static) | `"Could not send — check the recipient and provider config."` | Fallback save-error text when a failed send's `error` field is blank. |
| `MessagingChannel` cases | `String` enum | fallback `.email` on an unparsable form value | The two channels (`email`, `sms`) a message can be sent on. |

## Deep Linking

Not applicable: neither `MessagingModels.swift` nor `MessagingTopic.swift` registers a URL
scheme, universal link, or `NSUserActivity`; navigation is entirely through `HTDVItem`/`HTDVChild`
path arrays supplied by the presentation layer that hosts this topic.

## Localization

The source contains no localization mechanism (no `String(localized:)`, no `.strings`/`.xcstrings`
catalog, no `NSLocalizedString`) — every user-facing string below is a hardcoded English literal,
stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Provider status unavailable` | `statusLine`'s fallback for a `nil` status |
| — | `{Email/SMS} ({Postmark/Twilio})` | `MessagingChannel.providerLabel`, built from the hardcoded titles and provider names in `MessagingModels.swift` |
| — | `{providerLabel} is not connected — sends on this channel will fail. Connect a {providerName} integration on this product's Integrations tab.` | `bannerText`'s not-connected message |
| — | `Couldn't check whether {providerLabel} is connected — sends on this channel may fail.` | `bannerText`'s unknown-status message |
| — | `Send email or SMS to this product's users and review what went out.` | `MessagingTopic.entry`'s description |
| — | `A recipient phone number is required for SMS.` | SMS recipient-required validation |
| — | `Choose a template.` | Unknown-template-id validation |
| — | `Template needs a value for "{name}".` | Missing-placeholder validation |
| — | `Enter a subject.` | Freeform-email subject-required validation |
| — | `Enter a message body.` | Freeform body-required validation |
| — | `Template variables must be a JSON object of strings.` | `templateVars(from:)` parse-shape validation |
| — | `Could not send — check the recipient and provider config.` | `MessagingTopic.sendFailedMessage` |
| — | `No messages sent yet.` | Log level's `emptyMessage` |
| — | `Freeform message` | `MessagingTopic.freeformOption`'s title |

(This is a representative sample, not the full set of literals across the two files — every one
follows the same pattern: a plain `String` with no key, no catalog entry, and no pluralization
rule beyond ad hoc string interpolation.)

## Accessibility Options

Not applicable: this is a data-source contract and rail-navigation controller with no UI of its
own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: neither `MessagingModels.swift` nor `MessagingTopic.swift` reads a feature-flag
key or contains conditional feature-gating logic.

## Analytics

Not applicable: neither file contains an analytics/event-emission call.

## Privacy

- **Data collected**: this component itself collects nothing new — it reads and forwards
  recipient contact information (an email address or phone number, via `MessagingSend.recipient`
  or the `MessagingLogEntry.recipient` the log already contains) and message content (`subject`,
  `body`, `templateVars`) that the caller supplies or the backend has already recorded.
- **Storage**: neither file writes any of this to disk, `UserDefaults`, or the Keychain;
  `MessagingTopic` holds no mutable stored state at all, so nothing it handles outlives the current
  form's/detail's `FormState`.
- **Transmission**: `send(ecosystemID:_:)` transmits the assembled `MessagingSend` (recipient,
  subject/body or template selection and variables) to the injected data source; `log(...)`
  receives already-sent message content, including recipient and body, back from it. Actual
  network transport is the injected `MessagingDataSource`'s concern, out of scope of these two
  files.
- **Retention**: not controlled by either file — the backend behind `MessagingDataSource` owns how
  long a `MessagingLogEntry` (recipient, subject, body) persists; these files only read and display
  whatever the backend currently returns.

## Logging

Not applicable: neither file contains an `os_log`, `Logger`, `print`, or other logging call.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
