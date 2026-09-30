<!-- leaf: implement-extension-host-core-1/extensions-contribution-point--edge-cases · source: extension-host-core-extensions-contribution-point.md -->

# Contribution Point

**Rules** (cite as `implement-extension-host-core-1/extensions-contribution-point--edge-cases#<slug>`):

- `empty-notes-array-on-record` MUST — record(_:notes:for:) MUST accept an empty notes array (contribution-point-001's third call, for identifier "c"), …
- `a-manifest-with-no-contributes-key` MUST — apply(_:from:at:)'s contributions parameter MUST be Contributions.empty in this case, never omitted …
- `withdraw-immediately-followed-by-re-apply-of-the-same-identifier` MUST — on a full rescan, ExtensionRegistry withdraws every currently loaded extension from every point before reapplying any …
- `error-states-a-conformer-s-apply-throws-partway-through-applying-an-extension` MUST — ContributionPoint.apply(_:from:at:)'s doc comment states only that it MAY throw; it does not state whether a conformer …

## Edge Cases

- **Empty `notes` array on `record`**: `record(_:notes:for:)` MUST accept an empty `notes` array (`contribution-point-001`'s third call, for identifier `"c"`), recording a payload with zero notes.
- **A manifest with no `contributes` key**: `apply(_:from:at:)`'s `contributions` parameter MUST be `Contributions.empty` in this case, never omitted (apply-contributions-never-absent); a conformer MUST treat this identically to a manifest whose `contributes` key is present but names nothing for this point's `contributionKey`.
- **Concurrent access**: `ContributionPoint` and `ContributionRegistrations` are single-threaded in effect: every conformer is `@MainActor`-isolated (main-actor-isolation), and `ContributionRegistrations` is not `Sendable` (registrations-not-sendable), so the compiler prevents a second, concurrently-running task from holding or mutating the same instance; all mutation is serialized onto the main actor.
- **Withdraw immediately followed by re-apply of the same identifier**: on a full rescan, `ExtensionRegistry` withdraws every currently loaded extension from every point before reapplying any of them (reload-withdraws-before-reapplying), so a conformer MUST be able to withdraw an identifier it is about to immediately reapply without leaving stale state behind; `ContributionRegistrations.record`'s replace-not-add behavior (record-replaces-existing-entry) is what makes this safe for the shared bookkeeping type.
- **Error states — a conformer's `apply` throws partway through applying an extension**: `ContributionPoint.apply(_:from:at:)`'s doc comment states only that it MAY throw; it does not state whether a conformer MUST leave its own state unchanged when it throws (an atomic apply) or MAY leave a partial application in place. `ExtensionRegistry.applyContributions(_:from:at:)` catches the thrown error, logs it, and records an `ExtensionLoadFailure`, but calls no compensating `withdraw(extensionIdentifier:)` on the point that threw, so a conformer that mutated its own state before throwing leaves that partial state in place with no automatic cleanup. The contract does not require `apply` to be atomic, so a port MUST NOT assume a failed `apply` left the point unchanged.
- **Offline or disconnected state**: Not applicable — `ContributionPoint.swift` performs no network access of its own; any conformer that reads network state is a separate file's concern, outside this contract.
- **A missing file or an unreachable server**: Not applicable at this layer for the same reason — this file defines the contract only; a conformer that reads files (for example theme files) handles that failure itself, and this file imposes no requirement on how.
- **Duplicate `contributionKey` across two registered points**: not validated anywhere in this file or in `ExtensionRegistry.register(_:)`; per contribution-key, `contributionKey` is used only for diagnostics, so a collision would only make a log line ambiguous — it would not misroute a contribution, since each point receives the full `Contributions` value directly rather than a `contributionKey`-keyed lookup.
