<!-- leaf: implement-file-system/model-file-system--part-2 · source: file-system-model-file-system.md -->

# File Browser FileSystem Model — continued (part 2)

**Rules** (cite as `implement-file-system/model-file-system--part-2#<slug>`):

- `config-value-type` MUST
- `config-package-extensions-default` MUST
- `config-package-display-names-default` MUST
- `config-custom-mappings-key-default` MUST
- `config-default-static-instance` MUST
- `node-identity-by-path` MUST
- `node-display-name` MUST
- `node-directory-flag-trusted` MUST
- `node-package-detection` MUST
- `node-attribute-read-tolerant` MUST
- `node-file-size-directories-nil` MUST
- `node-children-shape-file-or-package` MUST
- `node-children-shape-unopened-directory` MUST
- `node-children-shape-eager-directory` MUST
- `node-children-loaded-flag-eager` MUST
- `node-load-children-if-needed-guard` MUST
- `node-load-children-if-needed-flag-before-read` MUST
- `node-load-children-if-needed-background-queue` MUST
- `node-load-children-if-needed-empty-collapse` MUST
- `node-load-children-if-needed-main-actor-publish` MUST
- `node-load-children-if-needed-mainactor-declaration` MUST
- `node-should-ignore-glob-match` MUST
- `node-load-children-ds-store-exclusion` MUST
- `node-load-children-hidden-files-included` MUST
- `node-load-children-read-failure-empty` MUST
- `node-load-children-directory-detection-fallback` MUST
- `node-load-children-recursion-depth` MUST
- `node-load-children-sort-order` MUST
- `node-merge-identity-preservation` MUST
- `node-merge-addition` MUST
- `node-merge-deletion` MUST
- `node-merge-order-follows-fresh` MUST
- `node-equality-by-id-only` MUST
- `node-hash-by-id-only` MUST
- `node-git-status-external` MUST
- `node-icon-package` MUST
- `node-icon-directory-special-names` MUST
- `node-icon-directory-dotfile-default` MUST
- `node-icon-file-custom-mapping-priority` MUST
- `node-icon-file-builtin-fallback` MUST

## Behavioral Requirements

- **config-value-type**: `FileTreeConfig` MUST be declared as a `Sendable`
  `struct`, and all three of its stored properties (`packageExtensions`,
  `packageDisplayNames`, `customMappingsDefaultsKey`) MUST be declared `let`,
  so a `FileTreeConfig` value MUST NOT be mutated after construction — a
  caller that needs different values MUST construct a new `FileTreeConfig`.
- **config-package-extensions-default**: `FileTreeConfig.init`'s
  `packageExtensions` parameter MUST default to an empty `Set<String>` when
  the caller supplies none.
- **config-package-display-names-default**: `FileTreeConfig.init`'s
  `packageDisplayNames` parameter MUST default to an empty
  `[String: String]` when the caller supplies none.
- **config-custom-mappings-key-default**: `FileTreeConfig.init`'s
  `customMappingsDefaultsKey` parameter MUST default to the literal
  `"AgenticFileBrowser.customMappings"` when the caller supplies none.
- **config-default-static-instance**: `FileTreeConfig.default` MUST be a
  `static let` equal to `FileTreeConfig()` constructed with all three
  defaults above.
- **node-identity-by-path**: `FileTreeNode.id` MUST be set to `url.path`,
  the node's full filesystem path — never a generated UUID or any other
  derived value.
- **node-display-name**: `FileTreeNode.name` MUST be set to
  `url.lastPathComponent`.
- **node-directory-flag-trusted**: `FileTreeNode.init` MUST accept the
  `isDirectory` flag exactly as the caller supplies it and MUST NOT verify
  it against the file system at construction time; a caller-supplied
  `isDirectory` value that disagrees with what is actually on disk is not
  detected or corrected.
- **node-package-detection**: `FileTreeNode.isPackage` MUST be `true` if and
  only if `packageExtensions` contains `url.pathExtension` (a case-sensitive
  set membership test), regardless of the node's `isDirectory` value.
- **node-attribute-read-tolerant**: `FileTreeNode.init` MUST read `fileSize`
  and `modificationDate` via `try? FileManager.default.attributesOfItem(atPath:)`,
  and MUST set both to `nil` — raising no error and logging nothing — when
  that call throws (for example a permission-denied or already-deleted
  file) or when the corresponding attribute key is absent or not typed as
  expected.
- **node-file-size-directories-nil**: `FileTreeNode.fileSize` MUST always be
  `nil` for a node whose `isDirectory` is `true`, independent of whether
  directory size attributes could be read.
- **node-children-shape-file-or-package**: `FileTreeNode.children` MUST be
  `nil` for any node whose `isDirectory` is `false` or whose `isPackage` is
  `true`.
- **node-children-shape-unopened-directory**: `FileTreeNode.init` MUST set
  `children` to an empty array — not `nil` — for a directory node (not a
  package) constructed with `loadChildren: false`, so that an unopened,
  expandable directory is distinguishable from a leaf.
- **node-children-shape-eager-directory**: `FileTreeNode.init` MUST set
  `children` directly to the result of
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` for a
  directory node (not a package) constructed with `loadChildren: true`,
  including leaving `children` as an empty array — not `nil` — when that
  directory turns out to have no visible entries; this diverges from
  `loadChildrenIfNeeded()`'s empty-to-`nil` conversion (see
  `node-load-children-if-needed-empty-collapse`).
- **node-children-loaded-flag-eager**: `FileTreeNode.childrenLoaded` MUST be
  `true` immediately when `init` is called with `loadChildren: true`, and
  MUST remain `false` when `init` is called with `loadChildren: false`.
- **node-load-children-if-needed-guard**: `loadChildrenIfNeeded()` MUST
  return immediately, performing no file-system access, when `isDirectory`
  is `false`, when `isPackage` is `true`, or when `childrenLoaded` is
  already `true`.
- **node-load-children-if-needed-flag-before-read**:
  `loadChildrenIfNeeded()` MUST set `childrenLoaded = true` before
  dispatching its background read, not after the read completes, so that
  two calls to `loadChildrenIfNeeded()` on the same node in quick
  succession MUST result in at most one background read of that directory.
- **node-load-children-if-needed-background-queue**:
  `loadChildrenIfNeeded()` MUST perform its directory read via
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` on
  `DispatchQueue.global(qos: .userInitiated)`, never on the calling thread.
- **node-load-children-if-needed-empty-collapse**: `loadChildrenIfNeeded()`
  MUST assign the freshly-read result to `children` as `nil` when the read
  returns an empty array, and as the array itself otherwise — it MUST NOT
  leave `children` as a non-nil empty array.
- **node-load-children-if-needed-main-actor-publish**:
  `loadChildrenIfNeeded()` MUST publish the updated `children` value back
  via `DispatchQueue.main.async`, and MUST silently skip that assignment
  (through `self?.children = ...`) if the node has been deallocated before
  the background read completes.
- **node-load-children-if-needed-mainactor-declaration**:
  `loadChildrenIfNeeded()` MUST be declared `@MainActor`, so every call to
  it MUST originate on Swift's main actor.
- **node-should-ignore-glob-match**: `FileTreeNode.shouldIgnore(_:patterns:)`
  MUST return `true` if and only if the filename matches at least one
  pattern in `patterns` via POSIX `fnmatch` called with flags `0`, and MUST
  return `false` when `patterns` is empty.
- **node-load-children-ds-store-exclusion**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  unconditionally exclude any entry named exactly `.DS_Store`, independent
  of `ignorePatterns`.
- **node-load-children-hidden-files-included**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  call `contentsOfDirectory` with no `options` (not `.skipsHiddenFiles`), so
  dotfiles other than `.DS_Store` (for example `.claude`, `.git`,
  `.gitignore`) MUST be included unless a caller-supplied `ignorePatterns`
  entry matches them.
- **node-load-children-read-failure-empty**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  return an empty array, raising or logging no error, when
  `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
  throws.
- **node-load-children-directory-detection-fallback**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  treat a child whose `.isDirectoryKey` resource value cannot be read as a
  file (`isDirectory: false`), never as a directory.
- **node-load-children-recursion-depth**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  construct every child with `loadChildren: false`, so one call MUST read
  exactly one directory level and MUST NOT recurse into subdirectories.
- **node-load-children-sort-order**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  sort its result with every directory node before every file node, and
  MUST sort nodes of the same kind by `name` using
  `localizedCaseInsensitiveCompare` in ascending order.
- **node-merge-identity-preservation**: `merge(children:)` MUST, for every
  node in the `fresh` array whose `id` also appears among the node's
  current `children`, keep the pre-existing `FileTreeNode` instance (by
  reference) in the result rather than the corresponding instance from
  `fresh`.
- **node-merge-addition**: `merge(children:)` MUST include, as the `fresh`
  instance itself, any node in `fresh` whose `id` does not appear in the
  current `children`.
- **node-merge-deletion**: `merge(children:)` MUST drop from the result any
  existing child whose `id` does not appear in `fresh`.
- **node-merge-order-follows-fresh**: `merge(children:)` MUST order its
  result according to `fresh`'s order, not the previous `children`'s order.
- **node-equality-by-id-only**: `FileTreeNode.==` MUST compare only `id`
  (the URL path); it MUST NOT consider `children`, `gitStatus`, `fileSize`,
  `modificationDate`, or any other stored property.
- **node-hash-by-id-only**: `FileTreeNode.hash(into:)` MUST combine only
  `id` into the hasher.
- **node-git-status-external**: `FileTreeNode.gitStatus` MUST be a public,
  settable, `@Published` property that none of `FileTreeConfig.swift`,
  `FileTreeNode.swift`, `FileSystemWatcher.swift`, or
  `DirectoryWatchCoordinator.swift` itself ever assigns; it exists purely as
  a hook a caller outside these four files sets.
- **node-icon-package**: `systemImageName` MUST return `"shippingbox.fill"`
  whenever `isPackage` is `true`, regardless of `isDirectory`.
- **node-icon-directory-special-names**: `systemImageName` MUST return
  `"brain"` for a directory named exactly `.claude`, `"arrow.triangle.branch"`
  for one named exactly `.git`, `"folder.fill.badge.gearshape"` for one named
  `Sources`, `Source`, or `src`, and `"folder.fill.badge.questionmark"` for
  one named `Tests`, `test`, or `tests`.
- **node-icon-directory-dotfile-default**: `systemImageName` MUST return
  `"folder.badge.gearshape"` for any other directory whose name starts with
  `"."`, and `"folder.fill"` for every remaining directory.
- **node-icon-file-custom-mapping-priority**: `systemImageName` for a file
  MUST consult `CustomFileTypeMappings.mapping(for:)`, keyed on the
  lowercased path extension, before any other icon source, and MUST use
  that mapping's `iconName` when one is found for a non-empty extension.
- **node-icon-file-builtin-fallback**: `systemImageName` for a file with no
  custom mapping MUST use `FileTypeIcons.builtInIcon(for:)`, keyed on the
  lowercased path extension, and MUST fall back to the literal `"doc"` when
  that also returns `nil`.
