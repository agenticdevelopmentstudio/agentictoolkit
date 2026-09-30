<!-- leaf: implement-general-view-2/mcp-chips-bar-view--edge-cases · source: mcp-chips-bar-view.md -->

# MCPChipsBarView

**Rules** (cite as `implement-general-view-2/mcp-chips-bar-view--edge-cases#<slug>`):

- `null-empty-input-registry-activeserverids-non-optional` MUST — Null/empty input (MUST): registry and activeServerIds are non-optional, non-failable-typed initializer parameters, so …
- `boundary-values-registry-exactly-one-client` MUST — Boundary values (MUST): A registry with exactly one client is handled by the same sort/label logic as any other count …
- `error-states-registry-clients-sink-closure` MUST — Error states (MUST): registry.$clients' sink closure has no failure case — @Published's publisher never completes with …
- `outlive-their-server-activeserverids-only-intersected-set` MUST — Stale active ids outlive their server (MUST): activeServerIds is only intersected with Set(availableServerIds) when …
- `opened-available-servers-opening-popover-while-availableserverids` MUST — Picker opened with no available servers (MUST): Opening the popover while availableServerIds == [] shows only the …
- `toggle-setter-idempotent-row-toggle-binding-binding` MUST — Row toggle setter is not idempotent (MUST): Each row's Toggle binding is Binding(get: { viewModel.isActive(id) }, set: …

## Edge Cases

- Null/empty input (MUST): `registry` and `activeServerIds` are
  non-optional, non-failable-typed initializer parameters, so Swift's type
  system rules out `nil` for either. An empty `activeServerIds.wrappedValue`
  at construction (`{}`) is handled identically to any other set — no
  special-case branch exists for it. An empty registry (`clients == [:]`)
  drives `computes-no-servers-label` and the picker's empty-state message.
- Boundary values (MUST): A registry with exactly one client is handled by
  the same sort/label logic as any other count (`"MCP: 1 of 1"` when that
  one server is active). No maximum server count is enforced anywhere in
  source.
- Concurrent access: Not applicable — both `MCPChipsBarView` and
  `MCPChipsBarViewModel` are declared `@MainActor`, so Swift's concurrency
  checker confines every read and write of `availableServerIds`,
  `serverNames`, and `activeServerIds` to the main actor; source provides no
  path for two threads to mutate this component's state simultaneously.
- Error states (MUST): `registry.$clients`' `sink` closure has no failure
  case — `@Published`'s publisher never completes with an error — so no
  error-handling branch exists or is needed in this file. No other
  operation in this file (sorting, dictionary construction, set membership)
  can throw.
- Offline/disconnected: Not applicable — this file never opens a network
  connection itself; it only reads `registry.$clients`' already-resolved
  client list and each client's cached `name`. Whether a given server's
  underlying connection is up, down, or reconnecting is `MCPServerRegistry`'s
  and `MCPClient`'s concern, entirely outside this file, and is not
  reflected in the bar's appearance.
- Stale active ids outlive their server (MUST): `activeServerIds` is only
  intersected with `Set(availableServerIds)` when computing the button's
  displayed count (`computes-count-active-label`); the underlying
  `activeServerIds` set — and the external binding it is written back to —
  keeps any id that the registry has since stopped reporting. If that same
  id's server later reappears in `registry.$clients`, it is immediately
  reported active again with no re-confirmation step, since
  `toggle(_:)`/`propagates-toggle-to-binding` is the only path that ever
  removes an id from the set (see the "Stale active ids" Design Decision).
- Picker opened with no available servers (MUST): Opening the popover while
  `availableServerIds == []` shows only the empty-state message; the
  `showingPicker` toggle and popover presentation are unaffected by whether
  any servers exist.
- Row toggle setter is not idempotent (MUST): Each row's `Toggle` binding is
  `Binding(get: { viewModel.isActive(id) }, set: { _ in viewModel.toggle(id)
  })` — the setter ignores the new boolean value entirely and unconditionally
  calls `toggle(id)`, per **row-toggle-calls-view-model-toggle**. Setting a
  row to the value it already holds still flips membership, rather than
  leaving it unchanged. SwiftUI's own `Toggle` only invokes a boolean
  binding's setter when the user's interaction actually changes the
  displayed value, so this does not manifest through normal use, but nothing
  in the setter itself guards against being invoked with a value equal to
  the current state.
