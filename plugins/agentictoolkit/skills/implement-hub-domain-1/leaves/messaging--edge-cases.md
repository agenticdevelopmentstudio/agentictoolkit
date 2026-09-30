<!-- leaf: implement-hub-domain-1/messaging--edge-cases · source: hub-domain-messaging.md -->

# Hub Domain Messaging

**Rules** (cite as `implement-hub-domain-1/messaging--edge-cases#<slug>`):

- `blank-required-fields` MUST — "channel" and "userId" blank MUST be rejected by the shared form validator ("Customer ID is required") before the save …
- `blank-conditionally-required-fields` MUST — "subject" (email freeform), "body" (any freeform), and "recipient" (SMS) are not field-level required, so a blank value …
- `blank-or-whitespace-only-templatevars` MUST — MUST parse to an empty [String: String] rather than throwing, per HubText.nonBlank's trim-and-check (MUST).
- `template-with-no-placeholders` MUST — MUST be sendable with templateVars empty, since the placeholder-validation loop has nothing to iterate (MUST).
- `boundary-exactly-logpagesize-log-entries` MUST — the log level MUST render all 100 without requesting a second page; entries beyond 100 are not shown (see …
- `malformed-templatevars-json` MUST — JSONValue.parse(_:) throws HubError.validation("Invalid JSON: ...") for text that is not valid JSON at all (not just …
- `concurrent-access` MUST — MessagingTopic holds no mutable stored state, so no synchronization primitive is needed within one instance; nothing in …
- `error-states` MUST — templates(), log(...), and send(...) failures MUST propagate unchanged through HubError.wrap(_:) to the caller; …
- `offline-or-unreachable-backend` MUST — HubError.offline/.transport(...) thrown by templates(), log(...), or send(...) MUST propagate unchanged; a status(...) …
- `cancellation` MUST — every MessagingDataSource call is a plain try await with no explicit cancellation handling in either file; Swift's …
- `unrecognized-messagingsendresult-status` MUST — any value other than the literal string "sent" (including an unrecognized one such as "queued") MUST be treated as a …

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
