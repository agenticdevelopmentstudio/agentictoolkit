<!-- leaf: implement-language/services-lsp--part-2 · source: language-services-lsp.md -->

# Language Services LSP — continued (part 2)

**Rules** (cite as `implement-language/services-lsp--part-2#<slug>`):

- `user-config-replaces-not-merges-builtin` MUST
- `unrelated-builtin-survives` MUST
- `builtin-sourcekit-lsp-fixed-identity` MUST
- `root-marker-walk-innermost-first` MUST
- `marker-order-does-not-affect-root` MUST
- `unmatched-marker-resolves-nil` MUST
- `session-rooted-at-marker-not-workspace` MUST
- `reconcile-diffs-desired-vs-current` MUST
- `secret-change-triggers-replacement` MUST
- `disabling-tears-down-session` MUST
- `command-change-replaces-session` MUST
- `observe-state-refuses-second-observer` MUST
- `retired-session-late-transition-cannot-overwrite` MUST
- `shutdown-is-terminal` MUST
- `shutdown-waits-for-retired-teardowns` MUST
- `settings-write-during-shutdown-starts-nothing` MUST
- `session-states-never-outruns-configurations` MUST

### Registry and Configuration Reconciliation

- **user-config-replaces-not-merges-builtin**: `effectiveConfigurations(builtIn:user:)`
  MUST replace a built-in configuration for a language id entirely with the
  user's configuration for that id, never merge fields between them
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.userConfigurationReplacesTheBuiltIn`).
- **unrelated-builtin-survives**: a user configuration for one language id
  MUST leave the built-in configuration for every other language id
  untouched
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.unrelatedUserConfigurationLeavesTheBuiltInAlone`).
- **builtin-sourcekit-lsp-fixed-identity**: `builtInConfigurations` MUST
  ship a fixed-UUID (`1CE31A0E-0000-4000-A000-5357494654FF`) SourceKit-LSP
  configuration claiming `swift`, `objective-c`, `objective-cpp`, `c`, and
  `cpp`, with command `/usr/bin/sourcekit-lsp` and root markers
  `Package.swift`, `*.xcodeproj`, `*.xcworkspace`, `.git` (`LanguageServerRegistry.swift`).
- **root-marker-walk-innermost-first**: `workspaceRoot(startingAt:markers:fileManager:)`
  MUST walk upward from the starting path and stop at the nearest ancestor
  directory containing any marker, including glob-suffix markers like
  `*.xcodeproj`
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerWalkFindsTheNearestMarker`, `.rootMarkerWalkSupportsGlobSuffixes`).
- **marker-order-does-not-affect-root**: the order markers are listed in
  MUST NOT change which directory `workspaceRoot` resolves to
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerOrderDoesNotChangeTheRoot`).
- **unmatched-marker-resolves-nil**: when no ancestor directory contains any
  marker, `workspaceRoot` MUST resolve to `nil` rather than loop
  indefinitely
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.rootMarkerWalkReturnsNilWhenNothingMatches`).
- **session-rooted-at-marker-not-workspace**: `reconcile` MUST root a
  session's working directory at the resolved marker directory, not at the
  outer workspace root
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.reconcileResolvesTheRootFromMarkers`).
- **reconcile-diffs-desired-vs-current**: `reconcile(userConfigurations:secrets:)`
  MUST diff the desired session set against the current one by
  `SessionDescriptor` equality, starting only sessions whose descriptor
  changed and retiring only those superseded
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.unrelatedSettingsChangeKeepsTheSession`).
- **secret-change-triggers-replacement**: a change to a configuration's
  secrets MUST count as a descriptor change that replaces the running
  session, so the new secret reaches the replacement session's environment
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.secretsReachTheSessionAndTriggerAReplacement`).
- **disabling-tears-down-session**: setting `isEnabled` to `false` for a
  configuration MUST tear down its running session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.disablingAConfigurationStopsItsSession`).
- **command-change-replaces-session**: changing a configuration's `command`
  MUST replace its running session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.changingACommandReplacesTheSession`).
- **observe-state-refuses-second-observer**: `observeState(of:id:)` MUST
  refuse (log `.fault`, return `false`) a second concurrent observation of
  the same session id rather than deliver a doubled stream
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aSecondObservationOfALiveSessionIsRefused`).
- **retired-session-late-transition-cannot-overwrite**: a state transition
  delivered by a session after it has been retired and replaced MUST NOT
  overwrite `sessionStates`' entry for the session that replaced it
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aRetiredSessionsLateTransitionCannotOverwriteItsReplacement`).
- **shutdown-is-terminal**: `shutdown()` MUST set `isShutDown` before its
  first suspension point and MUST stop every session concurrently
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.shutdownStopsEverySession`).
- **shutdown-waits-for-retired-teardowns**: `shutdown()` MUST wait for a
  session that `reconcile` had already begun retiring before shutdown
  started
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.shutdownWaitsForARetiredSessionsTeardown`).
- **settings-write-during-shutdown-starts-nothing**: a configuration change
  delivered while `shutdown()` is in flight MUST start no new session
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.aSettingsWriteDuringShutdownStartsNothing`).
- **session-states-never-outruns-configurations**: `sessionStates` MUST
  never hold an id whose configuration is not also present in
  `configurations`
  (`LanguageServerRegistry.swift`, `LanguageServerRegistryTests.statesAreAlwaysASubsetOfConfigurations`).

