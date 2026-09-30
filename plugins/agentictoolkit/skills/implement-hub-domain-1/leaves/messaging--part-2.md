<!-- leaf: implement-hub-domain-1/messaging--part-2 · source: hub-domain-messaging.md -->

# Hub Domain Messaging — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/messaging--part-2#<slug>`):

- `provider-status` MUST
- `template-listing` MUST
- `message-log-listing` MUST
- `message-send` MUST
- `messaging-channel-identity` MUST
- `template-placeholder-scan` MUST
- `log-entry-shape` MUST
- `log-page-shape` MUST
- `send-request-shape` MUST
- `send-result-shape` MUST
- `status-line-text` MUST
- `banner-text-connected` MUST
- `banner-text-not-connected` MUST
- `banner-text-unknown` MUST
- `placeholder-extraction` MUST
- `rail-top-level` MUST
- `rail-status-swallowed-at-top-level` MUST
- `rail-send-route` MUST
- `rail-log-route` MUST
- `rail-unknown-route-empty` MUST
- `send-detail-load-errors-propagate` MUST
- `send-detail-status-swallowed` MUST
- `send-form-provider-banners` MUST
- `send-form-default-values` MUST
- `send-form-field-order` MUST
- `send-form-required-tiers` MUST
- `send-freeform-subject-required-for-email` MUST
- `send-freeform-body-required` MUST
- `send-freeform-subject-suppressed-for-sms` MUST
- `send-sms-recipient-required` MUST
- `send-template-must-exist` MUST
- `send-template-placeholder-validation` MUST
- `send-template-vars-parsing` MUST
- `send-channel-fallback-to-email` MUST
- `send-invokes-data-source` MUST
- `send-result-failure-messaging` MUST
- `freeform-option-identity` MUST
- `send-form-has-no-delete-action` MUST

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
