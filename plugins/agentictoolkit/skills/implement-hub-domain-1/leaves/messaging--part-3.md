<!-- leaf: implement-hub-domain-1/messaging--part-3 · source: hub-domain-messaging.md -->

# Hub Domain Messaging — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/messaging--part-3#<slug>`):

- `log-fetch-errors-propagate` MUST
- `log-list-item-mapping` MUST
- `log-page-request-shape` MUST
- `log-entry-lookup` MUST
- `log-entry-detail-fields` MUST
- `log-entry-detail-identity` MUST
- `log-entry-detail-has-no-actions` MUST
- `main-actor-isolation` MUST
- `sendable-data-source-protocol` MUST
- `stateless-topic-instance` MUST
- `nonisolated-pure-statics` MUST

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
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (`MessagingTopic.init`) | `any MessagingDataSource` | none (required) | Backs `status`/`templates`/`log`/`send`. |
| `MessagingTopic.logPageSize` | `Int` (static) | `100` | `pageSize` passed to every `dataSource.log(...)` call; `page` is always `1`. |
| `MessagingTopic.freeformOption` | `FormSelectOption` (static) | `value: "", title: "Freeform message"` | The "no template selected" option in the Content select. |
| `MessagingTopic.sendFailedMessage` | `String` (static) | `"Could not send — check the recipient and provider config."` | Fallback save-error text when a failed send's `error` field is blank. |
| `MessagingChannel` cases | `String` enum | fallback `.email` on an unparsable form value | The two channels (`email`, `sms`) a message can be sent on. |

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

