---
id: e886e448-6aa5-4359-979d-49fba713ab2a
title: Plugin Runtime
domain: agentictoolkit://cookbook/ai/plugins/plugin-runtime
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Wires plugins discovered by the plugin manager into chat sessions:
  per-configuration storage, one-time migration, first-run defaults, template
  resolution, and two parallel chat-session/chat-backend runtimes.'
platforms:
- swift
- macos
tags:
- ai-plugins
- chat-session
- configuration
- runtime
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Plugin Runtime

## Overview

This runtime layer turns a discovered plugin bundle into something a chat UI
can talk to. It has three responsibilities: (1) a plugins coordinator owns
the plugin manager for the app's lifetime and runs discovery, one-time legacy
migration, and first-run seeding, in that order, at construction; (2) a
family of configuration types (a provider configuration, its per-configuration
store, a resolver, first-run defaults, a one-time migration, and a legacy
per-plugin config store) model a user's named provider configurations,
persist their field values (secrets routed to secure storage), and resolve a
configuration back into the plugin identifier, model, and value bag a request
needs; and (3) two parallel configuration-provider-plus-chat-engine pairs
drive an actual conversation through a plugin — a deprecated chat-backend path
(a chat-backend adapter, a provider chat session, a plugin-backed
configuration provider, and a single-configuration provider) riding a
chat-backend session wrapper, and a current chat-session path (a tool-calling
chat session and an MCP tool source) that also runs a bounded tool-calling
loop. Every type in this component is confined to a single execution context,
is declared safe for concurrent use through its own explicit synchronization,
or is a plain immutable value safe to share — never left unspecified.

## Behavioral Requirements

### Plugins Coordinator

- **coordinator-identity**: Constructing a plugins coordinator MUST register
  it with the app's shared feature registry as a side effect of construction,
  and it MUST be confined to a single execution context.
- **coordinator-plugin-manager**: Creating a plugins coordinator with an app
  name and additional search paths MUST construct exactly one plugin manager
  (exposed as its public plugin-manager reference) scoped to that app name
  and those search paths.
- **coordinator-startup-order**: Constructing a plugins coordinator MUST run,
  in order: discovery on the plugin manager, then migration-if-needed, then
  default-seeding-if-needed — migration and default seeding both read the
  plugin manager's discovered descriptors and available templates, which are
  empty until discovery has run.
- **coordinator-settings-panel**: Requesting the settings panel MUST return a
  freshly constructed settings panel view built from the coordinator's plugin
  manager.

### Chat Configuration Provider (interface)

- **config-provider-shape**: A chat configuration provider MUST expose a
  selected plugin identifier (text), a selected model (text), and resolved
  configuration values (a text-keyed map of text) as read-only properties
  confined to a single execution context.
- **config-provider-resolved-values**: Resolved configuration values MUST be
  the already-resolved key/value map a plugin reads as its configuration bag,
  secrets included — the consuming chat backend MUST NOT read secure storage
  or any settings store itself.

### Chat-Backend Adapter

- **chat-backend-conformance**: The chat-backend adapter MUST conform to the
  chat-backend interface and MUST be declared safe for concurrent use through
  its own explicit synchronization rather than confinement to a single
  execution context; every access to the plugin manager or its configuration
  provider MUST happen by hopping onto that context, and every mutation of
  its subscriber list MUST happen while holding its lock.
- **chat-backend-weak-provider**: The chat-backend adapter MUST hold its
  configuration provider weakly; when it has been deallocated, readiness, the
  readiness-change stream, notifying of a readiness change, and sending
  messages MUST treat the missing provider as an empty selected plugin
  identifier, an empty selected model, and empty resolved configuration
  values.
- **chat-backend-is-ready**: Readiness MUST be true if and only if the
  configuration provider's selected plugin identifier is non-empty; an empty
  string or a missing provider MUST yield false.
- **chat-backend-ready-changes**: Subscribing to readiness changes MUST
  return an independent stream per call; each stream MUST yield the current
  readiness value once for its new subscriber (computed asynchronously right
  after subscription) and MUST yield again whenever a readiness change is
  signaled while the subscriber is still registered.
- **chat-backend-notify**: Signaling a readiness change MUST recompute
  readiness once and multicast that single value to every currently-registered
  subscriber; it MUST cost nothing beyond that (no recomputation broadcast to
  nobody) when there are no subscribers, and it is the host's responsibility
  to call it after a plugin- or credential-selection change — the adapter
  MUST NOT observe those changes on its own.
- **chat-backend-deinit-cleanup**: When the adapter is torn down, it MUST
  finish every still-registered subscriber's stream and clear its subscriber
  list, under its lock.
- **chat-backend-send-messages-text**: Sending messages (text-only form) MUST
  build one chat request context from the current configuration-provider
  snapshot and an empty tool list, run it through the plugin transport, and
  MUST forward only text-delta payloads into the returned stream of text
  chunks — tool-use and end events from the underlying stream MUST be dropped
  for this form.
- **chat-backend-send-messages-tools**: Sending messages (with tools) MUST
  map every decoded stream event 1:1 onto a chat-backend stream event (a
  text-delta event stays a text-delta event; a tool-use event carrying an id,
  name, and arguments-JSON stays a tool-use event with the same fields; an
  end event carrying a stop reason stays an end event with the same field)
  with no other transformation.
- **chat-backend-cancellation**: Cancelling either returned stream's
  consuming task MUST cancel the backing unit of work created to drive the
  request.
- **chat-backend-no-plugin**: When the configuration provider's selected
  plugin identifier is empty, or loading the resolved identifier's plugin
  fails, resolving request inputs MUST produce a result whose plugin is
  absent, and the driving logic MUST finish the stream by throwing a
  plugin-not-available error without running the plugin transport at all. The
  three distinct failure reasons the plugin manager's load operation can
  throw (not found, bundle-load failure, missing/invalid principal class) are
  collapsed into that same single plugin-not-available case here — the
  chat-backend adapter does not distinguish them.
- **chat-backend-build-request-failure**: If the resolved plugin's
  request-building operation throws, the driving logic MUST finish the
  stream by throwing that error unchanged (no wrapping), without ever running
  the plugin transport.
- **chat-backend-transport-failure**: If the plugin transport throws while
  iterating, the driving logic MUST propagate that error unchanged as the
  stream's failure.
- **chat-backend-message-mapping**: Mapping a chat-backend message to the
  plugin's message type MUST translate it field-for-field (role, content,
  tool-use id, tool name, tool-arguments JSON, tool-is-error), and mapping a
  tool definition to the plugin's tool-spec type MUST translate it
  field-for-field (name, description, parameters JSON schema) with no content
  transformation.

### Provider Chat Session

- **provider-session-graph**: Creating a provider chat session with a
  configuration and a plugin manager MUST construct, in order, a
  single-configuration provider pinned to that configuration, a chat-backend
  adapter wired to that provider, and a chat view model wrapping a
  chat-backend session built from that adapter.
- **provider-session-lifetime**: A provider chat session MUST hold a strong
  reference to its adapter; since the chat-backend adapter holds its
  configuration provider weakly, this is the only thing that keeps the
  provider object alive for as long as the session exists.

### Per-Plugin Config Store (legacy)

- **plugin-config-store-key-convention**: The per-plugin config store MUST
  be the single place that derives per-plugin setting keys: a field's key
  MUST be `"aiplugin.<identifier>.field.<key>"` and a model's key MUST be
  `"aiplugin.<identifier>.model"`.
- **plugin-config-store-secret-routing**: Building a field's persisted
  setting MUST mark it secure exactly when the field is a secret field — a
  secret field's value MUST be routed to secure storage, and a plain-text
  field's value MUST be routed to the plain store.
- **plugin-config-store-model-default**: Resolving the selected model MUST
  return the stored model value when non-empty, else the descriptor's
  resolved default model.
- **plugin-config-store-config-values**: Resolving configuration values MUST
  return every field's current stored value keyed by the field's key, plus a
  `"model"` entry from the resolved selected model.

### Provider Configuration

- **provider-configuration-identity**: A provider configuration MUST support
  value equality, MUST be serializable for persistence, and MUST have a
  stable unique identifier assigned at creation (defaulting to a freshly
  generated identifier), a mutable name, and immutable plugin-identifier and
  template-id fields.
- **provider-configuration-unique-name**: Deriving a unique name MUST return
  the base name unchanged when it is not already taken; otherwise it MUST
  return `"<base> 2"`, `"<base> 3"`, … — the first suffixed form not already
  taken.

### Provider Settings

- **provider-settings-list**: The provider-configurations list setting MUST
  persist the ordered list of provider configurations under
  `"aiplugin.configurations"`, defaulting to an empty list.
- **provider-settings-selection**: The selected-configuration-id setting
  MUST persist the selected configuration's identifier under
  `"aiplugin.selectedConfigurationId"`, defaulting to `""`; an empty value
  MUST be interpreted by every consumer in this component as "no provider
  selected," not as an invalid reference.
- **provider-settings-guards**: The migration-guard and default-seeding-guard
  settings MUST each persist an independent one-time boolean guard
  (`"aiplugin.migratedToConfigurations"` and `"aiplugin.defaultConfigSeeded"`
  respectively, both defaulting to false) so migration and default-seeding
  are tracked, and can each run at most once, independently of one another.

### Per-Configuration Store

- **config-store-key-delegation**: Deriving a field's or model's setting key
  for a configuration MUST delegate to the shared per-configuration key
  logic, producing `"aiplugin.config.<id>.field.<key>"` and
  `"aiplugin.config.<id>.model"` respectively.
- **config-store-secret-routing**: Building a field's persisted setting MUST
  mark it secure exactly when the field is a secret field.
- **config-store-model-default**: Resolving the selected model for a
  configuration and template MUST return the stored model value when
  non-empty, else the template's resolved default model.
- **config-store-values-overlay**: Resolving configuration values for a
  configuration, template, and field list MUST start from the template's
  default values, then for each field overlay the stored value into the
  result under two conditions: the field is a secret field (always overlaid,
  even when the stored value is empty), or the stored value is non-empty. A
  field that is not secret and whose stored value is empty MUST NOT overwrite
  a template default for that key. The result MUST always include a `"model"`
  entry from the resolved selected model.
- **config-store-seed**: Seeding a configuration from a template and field
  list MUST, for each field that has an entry in the template's default
  values, write that default into the field's stored setting; a field with
  no corresponding template default MUST be left at its setting's own default
  (`""`). It MUST also set the model setting to the template's resolved
  default model.
- **config-store-clear**: Clearing a configuration's stored values MUST reset
  every given field's stored value to `""` and the configuration's model
  setting to `""`; because a secret field's persisted setting is secure,
  writing `""` MUST remove that value from secure storage. Clearing stored
  values MUST accept no template argument, so it remains callable even when
  the configuration's template no longer resolves (a removed plugin or a
  renamed template).

### Default Seeding

- **defaults-guarded-once**: Seeding defaults when needed MUST return
  immediately without side effects once the default-seeded guard is true;
  otherwise it MUST set that guard to true before returning, regardless of
  whether seeding actually produced a configuration.
- **defaults-only-when-empty**: Seeding defaults when needed MUST NOT write
  to the provider-configurations list when that list is already non-empty —
  an existing user- or migration-created list MUST be left untouched.
- **defaults-template-lookup**: Seeding defaults when needed MUST look up a
  template whose id is `"claude-local"` (the default template id) among the
  plugin manager's available templates; when no such template is advertised,
  it MUST leave the provider-configurations list empty.
- **defaults-seeded-configuration**: When the `"claude-local"` template is
  found and the list is empty, seeding defaults when needed MUST build one
  provider configuration named after the template's display name, seed its
  stored field values and model via the per-configuration store's seeding
  logic, and set the provider-configurations list to the single-element list
  containing it.
- **defaults-leaves-unselected**: Seeding defaults when needed MUST NOT set
  the selected-configuration-id setting — the seeded configuration is
  deliberately left unselected so behavior matches the daemon's zero-config
  "Default (Claude CLI)" path exactly.

### Migration

- **migration-plan-is-pure**: Planning a migration from descriptors, a legacy
  selection, and prior values MUST be a pure function of its arguments — it
  MUST perform no I/O and MUST NOT read or write any persisted setting.
- **migration-template-selection**: For each descriptor, planning a
  migration MUST select the template whose id matches that descriptor's
  legacy template id when that lookup succeeds and the descriptor advertises
  a template with that id, else the first entry of the descriptor's resolved
  templates.
- **migration-inclusion-rule**: Planning a migration MUST include a
  descriptor in the output only if at least one of the following holds: (a)
  some secret field has a non-empty legacy value, (b) the descriptor's
  identifier equals the legacy selection and the legacy selection is
  non-empty, or (c) some non-secret field's legacy value is non-empty and
  differs from that field's template default. A descriptor matching none of
  these MUST be skipped entirely — no configuration, field write, or model
  write MUST be produced for it.
- **migration-name-dedup**: Planning a migration MUST name each produced
  configuration via the unique-name derivation from the descriptor's display
  name, avoiding the names already assigned to configurations earlier in the
  same plan.
- **migration-field-write-rule**: For an included descriptor, planning a
  migration MUST emit a field write for a field only when its legacy value,
  falling back to the template's default for that key, falling back to `""`,
  is non-empty; a field that resolves to empty after that fallback MUST NOT
  produce a field write.
- **migration-model-write-rule**: For an included descriptor, planning a
  migration MUST emit exactly one model write per configuration, using the
  legacy `"model"` value when present and non-empty, else the template's
  resolved default model.
- **migration-selected-id**: The plan's selected id MUST be set to the newly
  created configuration's identifier for the (at most one) descriptor that
  matched the legacy-selection condition, and MUST remain `""` otherwise.
- **migration-run-once**: Running migration when needed MUST return
  immediately, performing no writes, once the migration guard is true.
- **migration-apply**: When migration has not yet run, running migration
  when needed MUST build a plan from the plugin manager's discovered
  descriptors, the legacy selected-plugin setting's current value, and the
  legacy config store's resolved values, then apply every field write (via a
  fresh persisted setting keyed by the per-configuration key logic, secure
  exactly when the write is a secret) and every model write (via the same key
  logic), then set the provider-configurations list to the plan's
  configurations (even when that list is empty), then set the
  selected-configuration-id setting to the plan's selected id ONLY when that
  id is non-empty (an empty selected id MUST leave the existing selection
  setting untouched), and finally set the migration guard to true.
- **migration-legacy-values-untouched**: Running migration when needed MUST
  NOT delete, clear, or overwrite any legacy per-plugin-store-keyed setting
  (`"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, or
  `"aiplugin.selectedPlugin"`) as part of migrating it — it only reads them.
- **migration-legacy-secret-retained**: After migration copies a legacy
  secret (`"aiplugin.<identifier>.field.<key>"`, written as a secure setting)
  into the new per-configuration key, the legacy secure-storage entry MUST
  remain in place; no code path removes it.

### Configuration Resolver

- **resolver-shape**: Resolving a configuration against a plugin manager
  MUST return an optional result carrying a plugin identifier, model, values,
  and fields.
- **resolver-descriptor-lookup**: Resolving a configuration MUST return
  nothing when the plugin manager has no discovered descriptor for the
  configuration's plugin identifier (the plugin is no longer
  installed/discovered).
- **resolver-fails-closed-on-template**: Resolving a configuration MUST
  return nothing when the resolved descriptor's resolved templates contains
  no template whose id equals the configuration's template id. Resolving a
  configuration MUST NOT fall back to the descriptor's first template in
  this case — doing so would silently bind the configuration's stored
  credentials and model to an unrelated provider template.
- **resolver-values**: When both lookups succeed, resolving a configuration
  MUST return values from resolving configuration values for that
  configuration/template/fields and a model from resolving the selected
  model for that configuration/template, using the descriptor's fields for
  that template.

### Tool-Calling Chat Session

- **local-session-conformance**: The tool-calling chat session MUST conform
  to the chat-session interface and MUST be declared safe for concurrent use
  through its own explicit synchronization; its history and event
  subscription MUST be accessed only while holding its lock, and its busy
  flag MUST be accessed only through a separate mutex.
- **local-session-events-initial**: Subscribing to the session's events MUST
  return a stream that immediately yields a state-changed event carrying the
  ready state to its subscriber before any turn runs.
- **local-session-single-subscriber**: Subscribing to the session's events
  MUST replace any previously stored subscription with the new one on each
  call — this component supports at most one live subscriber at a time.
- **local-session-send-busy-guard**: Sending a message MUST be a silent
  no-op — emitting no event and starting no turn — when a turn is already
  active; otherwise it MUST set the busy flag and start running the turn as a
  new tracked unit of work.
- **local-session-interrupt**: Interrupting MUST cancel the live turn's unit
  of work and MUST reset the busy flag to false, allowing an immediate
  subsequent send even if the cancelled turn's own cleanup has not yet run.
- **local-session-clear**: Clearing MUST remove all entries from history and
  MUST NOT affect an in-flight turn.
- **local-session-close**: Closing MUST cancel the live turn, reset the busy
  flag, emit a state-changed event carrying the closed state, and finish the
  stored subscription, ending the event stream.
- **local-session-turn-start**: Running a turn for the user's text MUST emit
  a user-message event for that text, append it to history as a user-role
  chat message, and emit a state-changed event carrying the responding state
  before doing anything else.
- **local-session-no-plugin**: When no plugin can be resolved, running a
  turn MUST emit a turn-failed event carrying the message "No AI provider is
  configured." and marked not retryable, followed by a state-changed event
  carrying the ready state, and MUST NOT emit a response-started event or
  attempt any request. The user's already-appended history entry MUST remain
  in history.
- **local-session-tool-loop-bound**: Running a turn MUST iterate the
  build-request/stream/tool-execute cycle at most a fixed maximum number of
  times per turn (8); when the model still requests tools on the final
  permitted iteration, the loop MUST end after that iteration without
  starting a ninth, and without emitting any distinct "budget exceeded"
  signal.
- **local-session-stream-mapping**: Within one iteration, running a turn
  MUST emit a response-started event the first time a text-delta event
  arrives (once per turn) and MUST emit a response-delta event for every
  text-delta chunk; it MUST collect every tool-use event into the
  pending-tools list and emit a tool-call event marked started for it; it
  MUST ignore end events from the stream (never surfacing the provider's stop
  reason for that event).
- **local-session-cooperative-cancellation**: Running a turn MUST check for
  cancellation between stream events and break out of the inner event loop
  when cancelled, without cancelling mid-event.
- **local-session-partial-text-kept**: After an iteration's stream ends
  (normally or via the cancellation break), if the accumulated turn text is
  non-empty, running a turn MUST append it to history as an assistant message
  even when the iteration was cut short.
- **local-session-tool-turn-end**: Running a turn MUST end the iteration
  loop (without a further plugin call) once the pending-tools list is empty,
  or once no tool source is configured even if pending tools remain.
- **local-session-tool-execution**: When continuing the loop, running a turn
  MUST execute every pending tool call sequentially, in the order received:
  append a tool-use history entry, call the tool source, append a tool-result
  history entry carrying the result's is-error flag, and emit a tool-call
  event marked completed — before moving to the next pending tool.
- **local-session-turn-finish**: When the iteration loop ends, running a
  turn MUST emit a response-finished event (with no stop reason — the
  provider's own stop reason is never surfaced) if and only if a
  response-started event was emitted at least once during the turn, then
  MUST emit a state-changed event carrying the ready state.
- **local-session-error-path**: Any error thrown while building a request,
  from the event-stream factory, or propagated from the plugin transport
  MUST end the turn by emitting a turn-failed event built from that error
  and always marked retryable — regardless of the error's underlying cause —
  followed by a state-changed event carrying the ready state.
- **local-session-with-tools**: Attaching tools to a chat request context
  MUST return a copy of the context with its tools replaced by the mapped
  tool specs and every other field (messages, model, system prompt, max
  tokens, config) unchanged.

### MCP Tool Source

- **mcp-tool-source-conformance**: The MCP tool source MUST conform to the
  tool-source interface and MUST be declared safe for concurrent use through
  its own explicit synchronization; its registry reference and
  active-server-id set MUST be fixed at initialization time (a snapshot, not
  a live-observed set).
- **mcp-tool-source-namespacing**: Listing tool definitions and calling a
  tool MUST identify a tool by `"<server-name>__<tool-name>"` (separator
  `"__"`), built from the registry's tools for the active server ids.
- **mcp-tool-source-schema-encoding**: Listing tool definitions MUST build
  one tool definition per registry pair whose input schema JSON-encodes
  successfully, and MUST silently drop any pair whose schema fails to encode
  — no error is surfaced for a dropped pair.
- **mcp-tool-source-unknown-tool**: Calling a tool MUST return a result of
  "Unknown tool: <name>" marked as an error when no currently-registered
  pair's namespaced name matches the given name.
- **mcp-tool-source-dispatch**: Calling a tool MUST re-fetch the registry's
  tools for the active server ids on every call (not cached from listing
  tool definitions), find the matching pair, and invoke that pair's own
  tool-call operation.
- **mcp-tool-source-error-mapping**: Calling a tool MUST convert any error
  thrown by the underlying MCP call into a result of "Tool error: <the
  error's description>" marked as an error.
- **mcp-tool-source-content-flatten**: Calling a tool MUST join only the
  text content items of a successful call's response with a newline, and
  MUST silently drop any non-text content item.
- **mcp-tool-source-argument-validation**: NEEDS REVIEW: Not implemented in
  source. Calling a tool decodes its arguments permissively and, on a decode
  failure, silently substitutes no arguments rather than surfacing a
  validation error — a malformed tool-call payload from the model is
  forwarded to the underlying call as though no arguments were supplied,
  instead of being reported back as a tool error the model or user could act
  on.

### Chat Configuration Providers (Plugin-Backed and Single-Configuration)

- **provider-defaults-on-unresolved**: Both the plugin-backed provider and
  the single-configuration provider MUST return an empty selected plugin
  identifier, an empty selected model, and empty resolved configuration
  values whenever the underlying configuration-resolution call returns
  nothing — neither type MUST throw.
- **plugin-chat-config-provider-selection**: The plugin-backed provider's
  resolved configuration MUST derive from the selected-configuration-id
  setting: an empty string, a string that does not parse as a valid
  identifier, or an identifier with no matching entry in the
  provider-configurations list MUST each result in no resolved configuration.
- **single-configuration-provider-pinning**: The single-configuration
  provider MUST resolve against the exact provider configuration passed to
  it at construction, independent of the selected-configuration-id setting,
  on every access — an edit made elsewhere to the same configuration's
  stored fields or model MUST be visible on the next access, since
  resolution is recomputed live rather than cached.

## Appearance

Not applicable — this is the plugin runtime feature (plugin discovery,
configuration storage, and two chat-session/backend implementations), not a
visual component.

## States

Not applicable — this is the plugin runtime feature, not a visual component.
The runtime's own state machines (the chat session's ready/responding/closed
transitions driven by the tool-calling chat session and the chat-backend
session wrapper, and the chat-backend adapter's boolean readiness stream) are
specified under Behavioral Requirements above, not here.

## Accessibility

Not applicable — this is the plugin runtime feature, not a visual component;
none of the given sources render UI (the plugins coordinator uses platform UI
facilities only to construct menu/status-item contributions and hand back a
settings panel view, never drawing anything itself).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| aiplugins-001 | coordinator-startup-order | Construct a plugins coordinator with app name "Test" | Discovery on the plugin manager runs before migration-if-needed and default-seeding-if-needed, per the fixed startup order |
| aiplugins-002 | chat-backend-is-ready | The configuration provider's selected plugin identifier is "" | The adapter's readiness is false |
| aiplugins-003 | chat-backend-is-ready | The configuration provider's selected plugin identifier is "com.x.plugin" | The adapter's readiness is true |
| aiplugins-004 | chat-backend-no-plugin | The configuration provider's selected plugin identifier is ""; send messages | The returned stream throws a plugin-not-available error; zero text chunks are yielded |
| aiplugins-005 | local-session-stream-mapping, local-session-turn-finish | Send "hi" with a fake event stream yielding a text-delta "Hel", a text-delta "lo", then an end event with stop reason "end_turn" | Events include a response-started event before the first response-delta event; the concatenated delta text is "Hello"; a terminal response-finished event fires; a state-changed event carrying the ready state follows |
| aiplugins-006 | local-session-send-busy-guard | Send "first", then send "second" before the first turn completes | The second send produces no user-message/response-started pair in the event stream — it is dropped |
| aiplugins-007 | local-session-no-plugin | No plugin can be resolved, then send "hi" | Events emit a turn-failed event carrying "No AI provider is configured." and marked not retryable, then a state-changed event carrying the ready state; no response-started event |
| aiplugins-008 | config-store-seed, config-store-values-overlay | Seed a configuration from a template whose default values are `["baseURL": "https://api.groq.com/openai/v1"]` and a secret `apiKey` field, then read configuration values | `values["baseURL"] == "https://api.groq.com/openai/v1"`, `values["model"] == "m1"`, `values["apiKey"]` is empty; after setting the apiKey field's stored value to "sk-test", resolving configuration values returns `"apiKey" == "sk-test"` |
| aiplugins-009 | resolver-fails-closed-on-template | The configuration's template id is "renamed-away", a template the descriptor no longer advertises | Resolving the configuration against the plugin manager returns nothing |
| aiplugins-010 | migration-inclusion-rule | One descriptor, an empty legacy selection, prior values returning `["apiKey": ""]` | The plan's configurations list is empty; the plan's selected id is "" |
| aiplugins-011 | migration-inclusion-rule, migration-field-write-rule | A descriptor with a non-secret `baseURL` field, an empty legacy selection, prior values returning `baseURL == "http://localhost:1234"` (differs from the template default "") | The plan's configurations list has one entry; the plan's field writes contain an entry with field key "baseURL" and value "http://localhost:1234" |
| aiplugins-012 | defaults-only-when-empty | The provider-configurations list already holds one entry; seed defaults when needed | The list is unchanged (still exactly the pre-existing entry); the default-seeded guard is now true |
| aiplugins-013 | mcp-tool-source-unknown-tool | Call the tool named "fs__nonexistent" where no registered pair namespaces to that name | Returns a result of "Unknown tool: fs__nonexistent" marked as an error |
| aiplugins-014 | mcp-tool-source-namespacing | The registry returns one pair (server name "fs", tool name "read") with an encodable input schema | Listing tool definitions returns exactly one tool definition named "fs__read" |

## Edge Cases

- **Null/empty input**: An empty selected plugin identifier MUST make the
  chat-backend adapter's readiness false and MUST make loading that (empty)
  identifier's plugin fail, which the adapter maps to a plugin-not-available
  error (see chat-backend-no-plugin). An empty legacy selection MUST leave
  the plan's selected id at "" (see migration-selected-id). Empty resolved
  configuration values MUST still build a valid, empty configuration bag for
  the plugin — an empty config bag is passed to the plugin unmodified;
  validating it is the plugin's concern, not this component's.
- **Null/empty input**: The MCP tool source decoding empty or malformed tool
  arguments MUST NOT throw — the permissive decode swallows the failure and
  passes no arguments to the underlying MCP call (the open question on
  mcp-tool-source-argument-validation).
- **Boundary values**: The tool-calling chat session's iteration cap (8) is
  a hard cap. On the 8th iteration, if the model still returns tool-use
  events, the outer loop MUST still end after that iteration completes —
  there is no 9th plugin call, and no explicit signal to the UI that the cap
  was hit (see local-session-tool-loop-bound).
- **Concurrent access**: Sending a message to the tool-calling chat session
  while a turn is active MUST be dropped, not queued
  (local-session-send-busy-guard). The chat-backend adapter's subscriber list
  MUST only ever be mutated under its lock, so concurrent
  readiness-change-stream/notify calls from different execution contexts
  MUST NOT corrupt the registry (chat-backend-conformance). The
  per-configuration store, migration, default-seeding, resolver, and legacy
  per-plugin config store are all confined to a single execution context, so
  an attempt to call them from outside that context is rejected outright —
  no runtime race is possible for those types.
- **Concurrent access**: A new readiness-change subscriber's "seed" value
  (computed asynchronously right after registration) and a concurrent notify
  call MAY race; the subscriber is guaranteed at least one yield of a
  readiness value, but the relative order between the seed and a concurrent
  notify SHOULD NOT be relied upon.
- **Error states**: A failure from the plugin manager's load operation (any
  of its distinct failure reasons) MUST surface identically as a
  plugin-not-available error from the chat-backend adapter — the specific
  failure reason is not preserved (chat-backend-no-plugin). A failure from
  building a request or from the plugin transport MUST surface as a
  turn-failed event (always marked retryable) in the tool-calling chat
  session, or as the stream's thrown error unchanged in the chat-backend
  adapter — in both cases the tool-calling chat session always reports the
  failure as retryable, regardless of whether the underlying cause is
  transient (a timeout) or permanent (a misconfigured plugin). The
  chat-backend session wrapper's analogous catch block does the same.
- **Error states**: The MCP tool source MUST convert any thrown MCP error
  into a result of "Tool error: <description>" marked as an error, never
  propagating the original error type to the model
  (mcp-tool-source-error-mapping).
- **Offline/disconnected state**: None of the given sources perform network
  I/O directly — that is the plugin transport's responsibility. From this
  component's perspective, a network failure (unreachable host, timeout, a
  non-2xx response) MUST surface through the same generic error path as any
  other thrown error: the tool-calling chat session's turn-failure path and
  the chat-backend adapter's stream-failure path — neither distinguishes an
  offline/unreachable failure from any other kind of error.
- **Offline/disconnected state**: The MCP tool source re-fetches the
  registry's tools on every call; if the MCP server for a previously-listed
  tool has disconnected between listing tool definitions and calling a tool,
  the tool is simply absent from the re-fetched pairs and the call MUST
  return a result of "Unknown tool: <name>" marked as an error — identical
  to a tool that never existed.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| App name | text | — (required) | Passed when constructing the plugins coordinator / plugin manager; used to derive the per-app plugins search path under Application Support. |
| Additional search paths | list of locations | empty | Passed when constructing the plugins coordinator; extra directories the plugin manager scans for plugin bundles. |
| Plugin resolver | injected function returning an optional plugin, asynchronously | — (required) | Injected into the tool-calling chat session; resolves which plugin instance serves the next turn. |
| Context builder | injected function from message history to a chat request context, asynchronously | — (required) | Injected into the tool-calling chat session; builds the per-turn chat request context from the current history snapshot. |
| Event stream factory | injected function producing the plugin's response stream | runs the plugin transport with the given spec and plugin | Injected into the tool-calling chat session; the seam tests use to fake a plugin's response stream. |
| Tool source | optional injected tool source | none | Injected into the tool-calling chat session; when absent, the tool loop never runs even if the plugin emits tool-use events. |
| Registry | tool registry reference | — (required) | Passed to the MCP tool source; the source of active MCP servers and their tools. |
| Active server ids | set of identifiers | — (required) | Passed to the MCP tool source; a fixed snapshot of which servers' tools are exposed to the model. |
| `"aiplugin.configurations"` | list of provider configurations (settings key) | `[]` | The provider-configurations list — the ordered list of configured providers. |
| `"aiplugin.selectedConfigurationId"` | text (settings key) | `""` | The selected-configuration-id setting — empty means the daemon's zero-config Default path. |
| `"aiplugin.migratedToConfigurations"` | boolean (settings key) | `false` | The migration guard — one-time migration guard. |
| `"aiplugin.defaultConfigSeeded"` | boolean (settings key) | `false` | The default-seeded guard — one-time default-seeding guard. |
| `"aiplugin.config.<id>.field.<key>"` | text (settings key, secret-routed per field) | `""` | Per-configuration field value, via the per-configuration key logic / per-configuration store's field setting. |
| `"aiplugin.config.<id>.model"` | text (settings key) | template's resolved default model | Per-configuration selected model, via the per-configuration key logic. |
| `"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, `"aiplugin.selectedPlugin"` | text (legacy settings keys) | `""` | Read (never written) by migration via the legacy per-plugin config store; superseded by the per-configuration keys above. |

## Deep Linking

Not applicable: none of the given sources register a URL scheme, handle a
system activity/handoff mechanism, or parse an incoming URL — the plugin
runtime has no externally-addressable destinations.

## Localization

None of the given sources route their user-facing strings through a
localization mechanism; they are hardcoded English literals, listed here as
facts rather than as a marker per source fidelity:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal) | `No AI provider is configured.` | The tool-calling chat session's turn-failed message when no plugin can be resolved |
| (none — hardcoded literal) | `Unknown tool: <name>` | The MCP tool source's error text when no pair matches the namespaced tool name |
| (none — hardcoded literal) | `Tool error: <description>` | The MCP tool source's error text when the underlying MCP call throws |

## Accessibility Options

Not applicable: the plugin runtime has no UI and responds to no display
accommodation (Reduce Motion, Increase Contrast, Differentiate Without
Color) in any of the given sources.

## Feature Flags

Not applicable: none of the given sources check a feature-flag value; every
behavioral branch (migration, default-seeding, the tool loop) is
unconditional given its own stated preconditions, not gated by a flag.

## Analytics

Not applicable: none of the given sources emit an analytics event; there is
no call to any event-logging mechanism in this component.

## Privacy

- **Data collected**: Provider credentials and connection settings the user
  enters for a configuration — secret fields (e.g. an `apiKey`, a secret
  kind) and plain fields (e.g. a `baseURL`, a plain-text kind), plus the
  chosen model — are the sensitive data this component stores and resolves.
  Resolved configuration values are explicitly documented as "secrets
  included."
- **Storage**: A field's secret kind routes its persisted setting to be
  marked secure, which stores it in secure storage rather than plain
  settings; a plain-text field is persisted to the plain (non-secure)
  settings store. Setting a secret field's value to "" (clearing stored
  values) removes it from secure storage.
- **Transmission**: This component never performs network I/O itself. It
  assembles the resolved value bag into a configuration bag inside a chat
  request context and hands that to the selected plugin's request-building
  operation; the plugin (outside this component's given sources) decides
  which of those values, including any secret, become part of the outgoing
  request that the plugin transport then performs.
- **Retention**: Stored field/model values persist indefinitely (secure
  storage for secrets, plain settings for the rest) until clearing stored
  values is called for that configuration — there is no expiry, rotation, or
  time-based invalidation logic anywhere in this component; a stored value is
  valid until explicitly overwritten or cleared.

## Logging

Not applicable: none of the given sources call a logging operation at any
level. The plugins coordinator declares the capability to build a logger but
never invokes it anywhere in the given source — the capability is present,
but unused.

## Platform Notes

- **SwiftUI (source)**: This is a plain Foundation/AppKit runtime layer, not
  a SwiftUI component, and it is the direct source for every role name used
  above: the plugins coordinator is `AIPluginsCoordinator` (a `@MainActor`
  subclass of the app's own `AppFeature` base, registering with
  `AppFeatureRegistry.shared`); the chat configuration provider interface is
  `ChatConfigProvider`; the chat-backend adapter is `AIPluginChatBackend`
  (`@unchecked Sendable`, guarded by its own `NSLock`, holding its provider
  `weak`); the provider chat session is `AIProviderChatSession`; the
  plugin-backed and single-configuration providers are
  `PluginChatConfigProvider` and `SingleConfigurationChatConfigProvider`; the
  legacy per-plugin config store is `PluginConfigStore`; the provider
  configuration, its settings, and its store are `AIProviderConfiguration`
  (`Codable`, `Sendable`, `Identifiable`, `Equatable`, `Hashable`), the
  `UserSettings` properties named in Provider Settings, and
  `AIProviderConfigStore`; default seeding and migration are
  `AIProviderDefaults` and `AIProviderMigration`; the configuration resolver
  is `AIProviderResolver`; the tool-calling chat session is `LocalChatSession`
  (`@unchecked Sendable`, its history/continuation guarded by `NSLock`, its
  busy flag guarded by a `Synchronization.Mutex<Bool>`); the MCP tool source
  is `MCPChatToolSource`; and the settings panel is `AIPanelViewController`.
  `AIPluginsCoordinator.swift` imports `AppKit` to compose menu/status-item
  contributions as an `AppFeature`; the actual chat UI (outside this
  component) binds to `AIChatViewModel`'s `@Published`/`ObservableObject`
  surface fed by `ChatBackendSession` or `LocalChatSession.events()`'s
  `AsyncStream`. State that would be `@Observable`/`ObservableObject`
  elsewhere is here plain `NSLock`- or `Synchronization.Mutex`-guarded
  mutable state on `@unchecked Sendable` classes, and persistence goes
  through `UserSetting<T>` (Combine-backed, Keychain-routed when `isSecure`).
- **Compose** (Android/Kotlin): `kotlinx.coroutines.flow.Flow`/`SharedFlow`
  replaces the `AsyncStream`/`AsyncThrowingStream` event pipelines;
  `kotlinx.coroutines.sync.Mutex` replaces `NSLock`/`Synchronization.Mutex`
  for the busy-guard and subscriber registry; the Keychain-routed secret
  fields become `EncryptedSharedPreferences` or an Android
  Keystore-backed store, and the plain fields become ordinary
  `SharedPreferences`/`DataStore`; the `.aiplugin` bundle + `dlopen` +
  `NSPrincipalClass` discovery model has no direct Android analogue — a
  static `ServiceLoader`-style registry or a signed dynamic-feature module
  would replace it, since arbitrary native code loading is far more
  restricted.
- **React/Web**: Async generators or an RxJS `Observable` replace
  `AsyncStream`; because JS is single-threaded, the `NSLock`/`Mutex` guards
  collapse to a plain boolean busy flag (no actual lock needed); the
  Keychain-routed secret store becomes a server-side vault or, client-side,
  a WebCrypto-wrapped value in `IndexedDB` (never plain `localStorage` for a
  secret); dynamic `import()` of a plugin module, driven by a fetched
  `descriptor.json`-equivalent manifest, replaces `Bundle` + `dlopen`
  discovery.
- **AppKit / UIKit**: The given sources already target AppKit; a UIKit
  (iOS) port would replace `AIPluginsCoordinator`'s `AppFeature`/menu-bar
  lifecycle hooks with `UIApplicationDelegate` equivalents, and would need
  to drop the `dlopen`-based `.aiplugin` bundle loading entirely — dynamic
  loading of unsigned code is not permitted under App Store code-signing —
  in favor of statically linked or App Extension–hosted plugins. The
  Foundation-level pieces (`NSLock`, `UserDefaults`, Keychain Services)
  need no change.
- **WinUI 3**: `System.Net.Http.HttpClient` performs the HTTP half of what
  `PluginTransport` drives (the given sources hand it an `AIRequestSpec`,
  never touch `HttpClient` directly), and `System.Diagnostics.Process` /
  `ProcessStartInfo` covers the subprocess (`.command`) transport case;
  `System.Text.Json` replaces `Foundation.JSONEncoder`/`JSONDecoder` for
  `descriptor.json` decoding and for `MCPChatToolSource`'s tool-schema and
  tool-argument JSON; `Windows.Storage.ApplicationData.Current.LocalSettings`
  replaces the plain (`isSecure: false`) `UserSetting` keys, and
  `Windows.Security.Credentials.PasswordVault` replaces the Keychain for
  secret fields; `System.Threading.SemaphoreSlim` or a plain `lock` object
  replaces `NSLock`/`Synchronization.Mutex` for `LocalChatSession`'s busy
  guard and `AIPluginChatBackend`'s subscriber registry;
  `System.Threading.Channels.Channel<T>` or `IAsyncEnumerable<T>` replaces
  `AsyncStream`/`AsyncThrowingStream` for `events()` and the plugin-transport
  event streams; `ObservableCollection<T>` + `INotifyPropertyChanged`
  replaces `@Published`/`ObservableObject` for the settings-backed
  configuration list and view models; and the Managed Extensibility
  Framework (`System.ComponentModel.Composition`) or a plain
  `Assembly.LoadFrom` call is the .NET analogue of `Bundle` + `dlopen` +
  `NSPrincipalClass` discovery — read a manifest first, load the assembly
  only on first use.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/AIPlugins/` |

## Design Decisions

- **Decision**: `AIPluginChatBackend` and `LocalChatSession` are declared
  `@unchecked Sendable` rather than `actor`s or fully `@MainActor` types.
  **Rationale**: each type's own doc comment states the invariant that makes
  this safe — every mutable field is guarded by exactly one synchronization
  primitive (`NSLock` for `subscribers`/`history`/`continuation`, a
  `Synchronization.Mutex` for the busy flag), and any `@MainActor`-isolated
  dependency (`pluginManager`, `configProvider`) is read only inside a
  `MainActor.run` block — so the compiler's inability to verify isolation
  across an `async` boundary is a known limitation being worked around, not
  an unverified assumption. (Apple platform implementation.)
  **Approved**: pending.
- **Decision**: `AIProviderResolver.resolve` returns `nil` rather than
  falling back to `descriptor.resolvedTemplates.first` when the
  configuration's `templateId` no longer resolves.
  **Rationale**: falling back would silently bind the configuration's
  already-stored credentials and model to whatever template happens to be
  first — an unrelated provider, base URL, and auth mode — and push that to
  the daemon as though nothing had changed. Failing closed surfaces the
  break instead of masking it.
  **Approved**: pending.
- **Decision**: `AIProviderConfigStore.configValues` always overlays a
  secret field's stored value (even when empty) but only overlays a
  non-secret field's stored value when it is non-empty.
  **Rationale**: an empty non-secret value would otherwise silently clobber
  a meaningful template default (e.g. a `baseURL`); a secret field has no
  default to clobber, and including it even when blank is what lets a
  plugin distinguish "this template requires a key and it is blank" from
  "this template has no secret field at all."
  **Approved**: pending.
- **Decision**: `AIProviderDefaults.seedIfNeeded` seeds a default
  `claude-local` configuration but leaves it unselected.
  **Rationale**: an empty `selectedAIProviderConfigurationId` and a selected
  `claude-local` configuration both resolve to the same effective behavior
  at the daemon (its own zero-config "Default (Claude CLI)" path), so
  leaving the selection empty avoids pushing a plugin id the daemon might
  not itself resolve, at no behavioral cost.
  **Approved**: pending.
- **Decision**: `AIProviderMigration.plan` carries forward a keyless
  descriptor whose only signal is a customized non-secret field
  (`hasCustomField`), not only descriptors with a secret or the legacy
  selection.
  **Rationale**: an OpenAI-compatible-style provider pointed at a local,
  keyless endpoint has no secret to detect and may never have been the
  legacy selection, but a customized `baseURL` is still evidence the user
  configured it; treating it as unconfigured would silently drop that
  setup during migration.
  **Approved**: pending.
- **Decision**: `LocalChatSession.maxToolIterations` is fixed at `8` with no
  configuration point and no explicit UI signal when the cap is reached.
  **Rationale**: bounds the worst-case latency and cost of a runaway
  tool-calling loop; the source gives no rationale for the specific value
  `8` beyond the constant itself, and a caller cannot distinguish "the model
  stopped on its own" from "the turn hit the iteration cap" from the emitted
  events alone. (Apple platform implementation.)
  **Approved**: pending.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: separation-of-concerns passes because the component splits into three
independent responsibilities — plugin lifecycle (`AIPluginsCoordinator`),
configuration modeling and persistence (`AIProviderConfigStore`,
`AIProviderResolver`, `AIProviderDefaults`, `AIProviderMigration`,
`PluginConfigStore`), and conversation driving (the two
`ChatConfigProvider` + chat-engine pairs) — and none reaches into another's
storage. unit-test-coverage passes because the conformance vectors trace to
`LocalChatSessionTests`, `AIProviderConfigStoreTests`,
`AIProviderResolverTests`, `AIProviderMigrationTests`, and
`AIProviderDefaultsTests`, which exercise streaming, seeding, resolution,
migration, and first-run defaults without a live provider. secure-storage
passes because every `.secret` field is persisted through a
`UserSetting<String>` constructed with `isSecure: true`, so credentials land
in the Keychain and never in plain user defaults (see Privacy).
input-sanitization and explicit-error-handling are partial because
`MCPChatToolSource.callTool` decodes the model's `argumentsJSON` with `try?`
and forwards `nil` arguments on a decode failure instead of reporting a tool
error — the open question on mcp-tool-source-argument-validation — while
the other failure paths (no configured provider, unknown tool, a throwing
MCP call) surface as explicit `ChatError` or tool-error text.
no-hardcoded-strings fails because the user-facing error strings listed
under Localization are English literals with no localization mechanism.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
