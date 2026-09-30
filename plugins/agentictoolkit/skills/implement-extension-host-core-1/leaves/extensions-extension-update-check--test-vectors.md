<!-- leaf: implement-extension-host-core-1/extensions-extension-update-check--test-vectors · source: extension-host-core-extensions-extension-update-check.md -->

# ExtensionUpdateCheck

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| extension-update-001 | no-downgrade-offered, update-value-shape | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` (universal, `engines.vscode: ^1.74.0`) | `update(for:)` returns an `ExtensionUpdate` with `identifier == "acme.widget"`, `installedVersion == "1.0.0"`, `latestVersion == "2.0.0"` (test `newerVersionIsAnUpdate`) |
| extension-update-002 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `1.0.0` | `update(for:)` returns `nil` (test `sameVersionIsNotAnUpdate`) |
| extension-update-003 | no-downgrade-offered | Installed `acme.widget` at `1.0.0`; registry answers `0.9.0` | `update(for:)` returns `nil` (test `olderPublishedVersionIsNotAnUpdate`) |
| extension-update-004 | registry-lookup-by-manifest-fields | Installed with `publisher: "my.company"` at `1.0.0`; registry stubbed at path `/my.company/widget` answering `namespace: "my.company"`, `2.0.0` | `update(for:)` returns `latestVersion == "2.0.0"`, and the request path ends with `/my.company/widget`, not a path split on the interior dot (test `lookupUsesThePublisherVerbatim`) |
| extension-update-005 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `engines.vscode: "^1.200.0"` (past the host's declared `1.138.0`) | `update(for:)` returns `nil` even though `2.0.0 > 1.0.0` (test `newerButIncompatibleIsNotOffered`) |
| extension-update-006 | installability-gate | Installed `acme.widget` at `1.0.0`; registry answers `2.0.0` with `targetPlatform: "darwin-arm64"` | `update(for:)` returns `nil` (test `newerPlatformSpecificIsNotOffered`) |
| extension-update-007 | publisher-required | Installed with `publisher: nil`, name `"widget"` | `update(for:)` throws `ExtensionUpdateError.noPublisher("widget")` (test `noPublisherThrows`) |
| extension-update-008 | versions-must-both-parse | Installed `acme.widget` at `1.0.0`; registry answers version `"nightly-build"` | `update(for:)` throws `ExtensionUpdateError.versionNotComparable(installed: "1.0.0", published: "nightly-build")` (test `incomparableVersionsThrow`) |
| extension-update-009 | per-lookup-failure-isolation, error-classification-not-published, updates-sorted-by-identifier | `check([current@1.0.0→registry 1.0.0, stale@2.0.0→registry 3.0.0, private@0.1.0→registry unstubbed/404])` | `report.updates.map(\.identifier) == ["acme.stale"]`, `report.updates.first?.latestVersion == "3.0.0"`, `report.notCheckable == [.init(identifier: "acme.private", reason: .notPublished)]` (test `oneUnknownExtensionDoesNotFailTheCheck`) |
| extension-update-010 | error-classification-default-unreachable | `check([acme.widget@1.0.0])`; registry answers status `503` | `report.updates.isEmpty`; `report.notCheckable == [.init(identifier: "acme.widget", reason: .registryUnreachable)]` (test `aFailingRegistryIsUnreachableRatherThanUnknown`) |
| extension-update-011 | error-classification-no-publisher | `check([installed(publisher: nil)])` | `report.notCheckable.map(\.reason) == [.noPublisher]` (test `aManifestWithNoPublisherSaysSo`) |
| extension-update-012 | error-classification-version-not-comparable | `check([installed(version: "nightly")])`; registry answers `2.0.0` | `report.notCheckable == [.init(identifier: "acme.widget", reason: .versionNotComparable)]` (test `anIncomparableVersionSaysSo`) |
| extension-update-013 | unavailable-sorted-by-identifier | `check([installed(name: "zebra", publisher: nil), installed(name: "alpha", publisher: nil)])` | `report.notCheckable.map(\.identifier) == ["alpha", "zebra"]` (test `theUnavailableAreSorted`) |
| extension-update-014 | updates-sorted-by-identifier, concurrent-per-extension-lookup | `check([zebra, alpha, middle])`, each installed at `1.0.0`, each registry stub answering `2.0.0` | `report.updates.map(\.identifier) == ["acme.alpha", "acme.middle", "acme.zebra"]` regardless of stub-answer arrival order (test `resultsAreSorted`) |
| extension-update-015 | empty-input-empty-report | `check([])` | `report.updates.isEmpty && report.notCheckable.isEmpty` (test `emptyInputIsEmptyReport`) |
