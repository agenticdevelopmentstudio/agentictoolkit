---
id: 1ea53189-24d5-4ba3-9d83-507ed2d44cfb
title: Project Key
domain: agentictoolkit://cookbook/status-web/lib/project-key
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Stable platform|projectName identity key for deploy projects, plus first-seen
  de-duplication of per-environment entries to one per project
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/lib/auto-configure
- agentictoolkit://cookbook/status-web/hooks/use-deploy-projects
references: []
approved-by: ''
approved-date: ''
---

# Project Key

## Overview

`project-key.ts` is the single source of truth for how the status web app
identifies a deploy project. It exports two pure functions:

- `projectKeyOf(p)` builds the identity key `${platform}|${projectName}` from
  the raw (un-canonicalized) platform string and the project name.
- `uniqueByProject(entries)` collapses a list of deploy-project entries that
  share a `(platform, projectName)` pair down to the first-seen entry.

The source comment explains why it exists: the auto-configure review modal
builds its ignore `Set` from these keys and the provider tests entries against
the same `Set`, so both must produce byte-identical keys ("a separator/field
drift would otherwise silently make every ignore a no-op"). De-duplication
exists because Railway enumerates one deploy-project entry per environment
(production/staging/testing), while the "Set Platform Project" picker and the
project-level ignore review treat a project as a single unit.

Callers in the source tree: `AutoConfigureProvider.tsx` (builds the ignore list
and the review project list), `AutoConfigureReview.tsx` (ignore checkbox
state), `configure/PlatformProjects.tsx` (bulk ignore request) and
`configure/ProjectBrowser.tsx` (project picker list).

## Behavioral Requirements

### projectKeyOf

- **key-input-shape**: `projectKeyOf` MUST accept any value that has a string `platform` field and a string `projectName` field; other fields on the value MUST be ignored.
- **key-format**: `projectKeyOf` MUST return the string formed by the `platform` value, then a single `|` character, then the `projectName` value, with no other characters added.
- **key-raw-platform**: `projectKeyOf` MUST use the `platform` value exactly as given, without canonicalizing case or spelling, so the key matches the raw platform carried in `DeployProject` and persisted as an ignored-project row.
- **key-no-trimming**: `projectKeyOf` MUST NOT trim, lowercase, escape or otherwise transform either field.
- **key-determinism**: `projectKeyOf` MUST return the same string for two inputs whose `platform` and `projectName` values are equal.
- **key-single-source**: Every place that builds or tests a project identity key (the review modal's ignore set and the provider's ignore filter) MUST derive the key through `projectKeyOf` rather than formatting it independently.

### uniqueByProject

- **unique-generic-element**: `uniqueByProject` MUST accept an array of any element type that has string `platform` and `projectName` fields, and MUST return an array of that same element type.
- **unique-first-seen-wins**: When two or more entries produce the same `projectKeyOf` key, `uniqueByProject` MUST keep only the entry that appears first in the input array.
- **unique-order-preserved**: `uniqueByProject` MUST return the kept entries in the same relative order they had in the input array.
- **unique-identity-preserved**: `uniqueByProject` MUST return the original entry objects, not copies or projections.
- **unique-new-array**: `uniqueByProject` MUST return a new array and MUST NOT mutate the input array.
- **unique-key-equality**: `uniqueByProject` MUST treat two entries as the same project if and only if their `projectKeyOf` keys are equal; other fields (environment, domain) MUST NOT affect grouping.
- **unique-production-representative**: `uniqueByProject` MUST NOT reorder entries to choose a representative; the kept entry carries the production domain only because the backend orders a project's environments production-first, which is the backend's contract, not this module's.

### Runtime and side effects

- **pure-functions**: Both functions MUST be synchronous and MUST have no side effects: no I/O, no network, no persistence, no logging and no shared state across calls.
- **no-errors-raised**: Both functions MUST NOT throw for well-typed input, and neither defines an error return.
- **per-call-state**: `uniqueByProject` MUST scope its seen-key set to a single call, so repeated calls are independent.

## Appearance

Not applicable — this is a pure key-building and de-duplication utility, not a visual component.

## States

Not applicable — this is a pure key-building and de-duplication utility, not a visual component.

## Accessibility

Not applicable — this is a pure key-building and de-duplication utility, not a visual component.

## Conformance Test Vectors

No test file exercises `project-key.ts`; these vectors are derived from the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| project-key-001 | key-format | `projectKeyOf({ platform: "railway", projectName: "api" })` | `"railway\|api"` |
| project-key-002 | key-raw-platform, key-no-trimming | `projectKeyOf({ platform: "Railway", projectName: " api " })` | `"Railway\| api "` (case and spaces preserved) |
| project-key-003 | key-input-shape | `projectKeyOf({ platform: "vercel", projectName: "web", domain: "x.app", env: "prod" })` | `"vercel\|web"` |
| project-key-004 | key-format | `projectKeyOf({ platform: "", projectName: "" })` | `"\|"` |
| project-key-005 | unique-first-seen-wins, unique-identity-preserved | `[A={railway,api,env:"production"}, B={railway,api,env:"staging"}, C={railway,api,env:"testing"}]` | `[A]` (same object as A) |
| project-key-006 | unique-order-preserved, unique-key-equality | `[X={vercel,web}, Y={railway,api}, Z={vercel,web}, W={railway,db}]` | `[X, Y, W]` |
| project-key-007 | unique-new-array | Input array `[X]`, call `uniqueByProject` | Result `!==` input; input still has length 1 and identical contents |
| project-key-008 | key-raw-platform, unique-key-equality | `[{platform:"railway",projectName:"api"}, {platform:"Railway",projectName:"api"}]` | Both entries kept (keys differ by case) |
| project-key-009 | unique-generic-element | `uniqueByProject([])` | `[]` |
| project-key-010 | per-call-state | Call `uniqueByProject([X])` twice | Each call returns `[X]` |
| project-key-011 | key-determinism | Two calls with `{platform:"fly",projectName:"svc"}` | Both return `"fly\|svc"` |
| project-key-012 | pure-functions, no-errors-raised | Any well-typed input to either function | Returns a value without throwing; no network, storage or console activity observed |
| project-key-013 | key-single-source | Review modal checks project P (adds `projectKeyOf(P)` to the ignore set); provider filters pending entries by `ignoreKeys.has(projectKeyOf(p))` | Every per-environment entry of P matches the filter |
| project-key-014 | unique-production-representative | `[S={railway,api,env:"staging"}, P={railway,api,env:"production"}]` | `[S]` (no reordering toward production) |

## Edge Cases

- **Empty input array**: `uniqueByProject([])` MUST return an empty array.
- **Empty field values**: `projectKeyOf` MUST produce `"|"` for empty `platform` and `projectName`; two such entries MUST collapse to one in `uniqueByProject`.
- **Separator inside a field**: The key is a plain concatenation with no escaping, so `{platform:"a|b", projectName:"c"}` and `{platform:"a", projectName:"b|c"}` MUST both produce `"a|b|c"` and MUST collapse together. Collision requires a platform identifier containing `|`; platforms come from the backend's fixed platform set, so this is a documented limitation rather than an expected input.
- **Case-variant platforms**: Entries whose platform differs only in case (for example `Railway` vs `railway`) MUST be treated as distinct projects, because the raw platform is keyed deliberately.
- **Single entry**: `uniqueByProject([X])` MUST return `[X]`.
- **All duplicates**: An input where every entry shares one key MUST reduce to a one-element array holding the first entry.
- **Backend order not production-first**: If the input lists a non-production environment first, the kept entry MUST be that non-production entry; the module performs no correction.
- **Malformed input at runtime**: The functions rely on the TypeScript signature for shape. An entry whose `platform` or `projectName` is `undefined` at runtime MUST be stringified by template-literal rules (for example `"undefined|api"`); no runtime validation or exception occurs.
- **Concurrent access**: Not applicable — both functions are synchronous and run on the single JavaScript thread, and `uniqueByProject` allocates its seen-set per call, so calls cannot interleave.
- **Error states and offline**: Not applicable — the module performs no I/O and has no dependencies that can fail or disconnect.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `p` (to `projectKeyOf`) | `{ platform: string; projectName: string }` | required | The project whose identity key is built |
| `entries` (to `uniqueByProject`) | `T[]` where `T extends { platform: string; projectName: string }` | required | Deploy-project entries to collapse to one per project |

The module reads no environment variables, settings keys or injected dependencies. The key separator `|` is a hard-coded constant inside `projectKeyOf`.

## Deep Linking

Not applicable: `project-key.ts` exports only pure functions and registers no route or URL.

## Localization

Not applicable: `project-key.ts` produces no user-facing strings; the `|` key is an internal identifier.

## Accessibility Options

Not applicable: `project-key.ts` renders nothing and so responds to no display option.

## Feature Flags

Not applicable: `project-key.ts` reads no flag and is always active wherever it is imported.

## Analytics

Not applicable: `project-key.ts` emits no events.

## Privacy

Not applicable: `project-key.ts` stores and transmits nothing; it only concatenates platform and project names already held by the caller.

## Logging

Not applicable: `project-key.ts` contains no logging calls.

## Platform Notes

- **SwiftUI**: Port as free functions or a small `enum ProjectKey` namespace in a shared Swift module. `projectKeyOf` becomes `"\(p.platform)|\(p.projectName)"` over a protocol such as `protocol ProjectKeyed { var platform: String { get }; var projectName: String { get } }`. `uniqueByProject` becomes a generic `func uniqueByProject<T: ProjectKeyed>(_ entries: [T]) -> [T]` using a local `Set<String>` and `filter` with `insert(_:).inserted`. Swift arrays are value types, so the "same object" guarantee applies only when `T` is a class; for structs, equal copies are returned. Both functions are pure and can be `nonisolated`.
- **Compose**: Kotlin top-level functions: `fun projectKeyOf(p: ProjectKeyed) = "${p.platform}|${p.projectName}"` and `fun <T : ProjectKeyed> uniqueByProject(entries: List<T>): List<T> = entries.distinctBy(::projectKeyOf)`. `distinctBy` keeps the first occurrence and preserves order, matching the source exactly, and returns a new list.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/project-key.ts` holds both functions; the structural type `{ platform: string; projectName: string }` lets `DeployProject` and `ReviewProject` share them. `uniqueByProject` uses `Array.prototype.filter` with a closure over a `Set<string>`, relying on `filter` visiting elements in index order for first-seen semantics.
- **AppKit / UIKit**: Same as the SwiftUI note; the functions have no UI dependency and belong in a framework shared by both app targets. With `NSObject` subclasses, keep the string key rather than overriding `isEqual`, so identity stays byte-identical to what the server persists.
- **WinUI 3**: Put both in a static C# class in a shared .NET class library (no Windows App SDK dependency). `ProjectKeyOf` is `$"{p.Platform}|{p.ProjectName}"` over an `IProjectKeyed` interface with `string Platform` and `string ProjectName`. `UniqueByProject<T>(IEnumerable<T> entries) where T : IProjectKeyed` can be `entries.DistinctBy(ProjectKeyOf).ToList()` (.NET 6+); LINQ `DistinctBy` keeps the first element per key and preserves order. Use the default ordinal `StringComparer` for the key set; do not use `StringComparer.OrdinalIgnoreCase`, because the source treats case-variant platforms as distinct. When the result feeds an `ObservableCollection<T>` bound to a `ListView`, build the de-duplicated list first and then populate the collection, so the view never shows per-environment duplicates. C# strings are never `undefined`, so a null `Platform` would format as an empty string, not the text `undefined`; guard with `ArgumentNullException.ThrowIfNull` if that distinction matters.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/project-key.ts` |

## Design Decisions

**Decision**: The key uses the raw platform string, not the canonical platform.
**Rationale**: The source comment states the raw platform is "the same value carried in DeployProject and persisted as an ignored-project row", so keys built on the client match persisted rows byte for byte. `PlatformProjects.tsx` canonicalizes the platform only when it builds the request body, after de-duplication by raw key.
**Approved**: pending

**Decision**: One module owns key formatting instead of each caller writing the template literal.
**Rationale**: The source comment warns that "a separator/field drift would otherwise silently make every ignore a no-op" between the review modal and the provider.
**Approved**: pending

**Decision**: De-duplication keeps the first-seen entry and does not pick production explicitly.
**Rationale**: The source relies on the backend ordering a project's environments production-first, so the first entry already carries the production representative domain; this keeps the helper generic and free of environment knowledge.
**Approved**: pending

**Decision**: The separator is a bare `|` with no escaping.
**Rationale**: Platform identifiers are a fixed backend set that does not contain `|`, so plain concatenation is unambiguous in practice; the collision case is recorded under Edge Cases.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

**Separation of concerns.** The module owns only project identity and de-duplication. It knows nothing about environments, domains, React state or the network; the provider, review modal, picker and bulk-ignore surfaces import it instead of formatting keys themselves.

**Unit test coverage.** No test file in `status-web` exercises `projectKeyOf` or `uniqueByProject`, so first-seen ordering and key format are unverified by tests.

**Explicit error handling.** Both functions are total over their typed inputs and have no failure path to handle; nothing is caught or swallowed.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `project-key.ts` |
