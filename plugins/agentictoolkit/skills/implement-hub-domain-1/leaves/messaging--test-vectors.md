<!-- leaf: implement-hub-domain-1/messaging--test-vectors · source: hub-domain-messaging.md -->

# Hub Domain Messaging

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
