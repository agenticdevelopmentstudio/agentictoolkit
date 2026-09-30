<!-- leaf: implement-status-web-src-lib-1/project-key · source: status-web-src-lib-project-key.md -->

**Rules** (cite as `implement-status-web-src-lib-1/project-key#<slug>`):

- `key-input-shape` MUST
- `key-format` MUST
- `key-raw-platform` MUST
- `key-no-trimming` MUST
- `key-determinism` MUST
- `key-single-source` MUST
- `unique-generic-element` MUST
- `unique-first-seen-wins` MUST
- `unique-order-preserved` MUST
- `unique-identity-preserved` MUST
- `unique-new-array` MUST
- `unique-key-equality` MUST
- `unique-production-representative` MUST
- `pure-functions` MUST
- `no-errors-raised` MUST
- `per-call-state` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `p` (to `projectKeyOf`) | `{ platform: string; projectName: string }` | required | The project whose identity key is built |
| `entries` (to `uniqueByProject`) | `T[]` where `T extends { platform: string; projectName: string }` | required | Deploy-project entries to collapse to one per project |

The module reads no environment variables, settings keys or injected dependencies. The key separator `|` is a hard-coded constant inside `projectKeyOf`.

## Platform Notes

- **SwiftUI**: Port as free functions or a small `enum ProjectKey` namespace in a shared Swift module. `projectKeyOf` becomes `"\(p.platform)|\(p.projectName)"` over a protocol such as `protocol ProjectKeyed { var platform: String { get }; var projectName: String { get } }`. `uniqueByProject` becomes a generic `func uniqueByProject<T: ProjectKeyed>(_ entries: [T]) -> [T]` using a local `Set<String>` and `filter` with `insert(_:).inserted`. Swift arrays are value types, so the "same object" guarantee applies only when `T` is a class; for structs, equal copies are returned. Both functions are pure and can be `nonisolated`.
- **Compose**: Kotlin top-level functions: `fun projectKeyOf(p: ProjectKeyed) = "${p.platform}|${p.projectName}"` and `fun <T : ProjectKeyed> uniqueByProject(entries: List<T>): List<T> = entries.distinctBy(::projectKeyOf)`. `distinctBy` keeps the first occurrence and preserves order, matching the source exactly, and returns a new list.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/project-key.ts` holds both functions; the structural type `{ platform: string; projectName: string }` lets `DeployProject` and `ReviewProject` share them. `uniqueByProject` uses `Array.prototype.filter` with a closure over a `Set<string>`, relying on `filter` visiting elements in index order for first-seen semantics.
- **AppKit / UIKit**: Same as the SwiftUI note; the functions have no UI dependency and belong in a framework shared by both app targets. With `NSObject` subclasses, keep the string key rather than overriding `isEqual`, so identity stays byte-identical to what the server persists.
- **WinUI 3**: Put both in a static C# class in a shared .NET class library (no Windows App SDK dependency). `ProjectKeyOf` is `$"{p.Platform}|{p.ProjectName}"` over an `IProjectKeyed` interface with `string Platform` and `string ProjectName`. `UniqueByProject<T>(IEnumerable<T> entries) where T : IProjectKeyed` can be `entries.DistinctBy(ProjectKeyOf).ToList()` (.NET 6+); LINQ `DistinctBy` keeps the first element per key and preserves order. Use the default ordinal `StringComparer` for the key set; do not use `StringComparer.OrdinalIgnoreCase`, because the source treats case-variant platforms as distinct. When the result feeds an `ObservableCollection<T>` bound to a `ListView`, build the de-duplicated list first and then populate the collection, so the view never shows per-environment duplicates. C# strings are never `undefined`, so a null `Platform` would format as an empty string, not the text `undefined`; guard with `ArgumentNullException.ThrowIfNull` if that distinction matters.

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
