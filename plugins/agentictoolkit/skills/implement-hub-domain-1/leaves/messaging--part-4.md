<!-- leaf: implement-hub-domain-1/messaging--part-4 · source: hub-domain-messaging.md -->

# Hub Domain Messaging — continued (part 4)

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
