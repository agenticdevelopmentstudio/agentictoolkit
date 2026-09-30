<!-- leaf: implement-extension-host-core-1/extensions-contribution-point--test-vectors · source: extension-host-core-extensions-contribution-point.md -->

# Contribution Point

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contribution-point-001 | identifiers-in-application-order, notes-in-application-order-unfiltered, payload-lookup-by-identifier | `record(1, notes: [note("a","a.one")], for: "a")`, then `record(2, notes: [note("b","b.one")], for: "b")`, then `record(3, notes: [], for: "c")` (traced to `ContributionRegistrationsTests.applicationOrderIsReported`) | `identifiers == ["a", "b", "c"]`; `payload(for: "b") == 2`; `notes.map(\.viewID) == ["a.one", "b.one"]` |
| contribution-point-002 | payload-lookup-by-identifier, remove-safe-on-unrecorded-identifier | `record(1, notes: [note("a","a.one")], for: "a")`, then `payload(for: "absent")`, then `remove("absent")` (traced to `ContributionRegistrationsTests.anUnknownIdentifierIsInert`) | `payload(for: "absent") == nil`; after `remove("absent")`, `identifiers == ["a"]` and `notes.count == 1` |
| contribution-point-003 | record-replaces-existing-entry, record-moves-identifier-to-end | `record(1, notes: [note("a","a.one")], for: "a")`, `record(2, notes: [note("b","b.one")], for: "b")`, then `record(10, notes: [note("a","a.two")], for: "a")` (traced to `ContributionRegistrationsTests.recordingTwiceReplaces`) | `identifiers == ["b", "a"]`; `payload(for: "a") == 10`; `notes.map(\.viewID) == ["b.one", "a.two"]` |
| contribution-point-004 | remove-clears-payload-and-its-notes | `record(1, notes: [note("a","a.one"), note("a","a.two")], for: "a")`, `record(2, notes: [note("b","b.one")], for: "b")`, then `remove("a")` (traced to `ContributionRegistrationsTests.removalIsPerExtension`) | `identifiers == ["b"]`; `payload(for: "a") == nil`; `notes.map(\.viewID) == ["b.one"]` |
| contribution-point-005 | filtered-identifiers-preserve-order | `record(index, notes: [], for: identifier)` for `("a","b","c","d")` at indices `(0,1,2,3)`, then `identifiers(where: { $0.isMultiple(of: 2) })` (traced to `ContributionRegistrationsTests.filteringKeepsOrder`) | Returns `["a", "c"]` |
