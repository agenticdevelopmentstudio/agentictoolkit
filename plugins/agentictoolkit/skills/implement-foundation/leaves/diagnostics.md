<!-- leaf: implement-foundation/diagnostics · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger

## Overview

Three types in `packages/apple/AgenticToolkit/Core/Diagnostics/`, part of the
`AgenticToolkitCore` framework target (per `@testable import
AgenticToolkitCore` in both test files), that make two otherwise-invisible
facts about a running build observable. `JITAvailability`
(`JITAvailability.swift`) is a value type that reads this process's own code
signature to answer whether a JavaScript engine in this process will compile
code or silently fall back to its interpreter — a degradation JavaScriptCore
never surfaces on its own. `UpstreamDivergence` (`UpstreamDivergence.swift`)
is a fixed, compiled-in catalogue of six places this app deliberately does
less than VS Code, each carrying what upstream does, what this app does
instead, why, and whether it can be observed happening at runtime.
`UpstreamDivergenceLedger` (`UpstreamDivergenceLedger.swift`, alongside the
`UpstreamDivergenceHit` value type it produces) is the process-wide,
thread-safe tally of which catalogue entries a real extension session
actually trips, published live to a Combine subscriber such as the Language
Servers settings panel. All three exist so that a narrowing recorded only in
a source comment — or a degradation with no symptom at all — becomes
something a person or a panel can actually see.

