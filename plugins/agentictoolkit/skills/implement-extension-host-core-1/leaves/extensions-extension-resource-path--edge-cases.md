<!-- leaf: implement-extension-host-core-1/extensions-extension-resource-path--edge-cases · source: extension-host-core-extensions-extension-resource-path.md -->

# ExtensionResourcePath

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-resource-path--edge-cases#<slug>`):

- `null-empty-declared-path-the-directory-itself` MUST — a declared value of "." resolves, before the containment check, to the directory itself; containment-strictness then …
- `boundary-exactly-at-the-root-versus-one-hop-beyond-it` MUST — a declared path that climbs exactly to root (for example "../base.json" from a themes/ folder one level below root) …
- `symlink-escape-with-no-literal-in-the-declared-string` MUST — a declared path containing no .. at all can still escape if a symlink planted inside the extension's own directory …
- `concurrent-access` MUST — ExtensionResourcePath, ExtensionResourcePathError, and InstalledContentLocation hold no mutable stored state — every …

## Edge Cases

- **Null/empty declared path — the directory itself**: a `declared` value of
  `"."` resolves, before the containment check, to the directory itself;
  `containment-strictness` then refuses it because the directory is not
  strictly below itself, so `resolve` throws `escapesExtensionDirectory`
  rather than handing a caller the directory to open as if it were a file.
  This is the exact case the source's own comment on `url(_:isContainedIn:)`
  names. MUST.
- **Boundary — exactly at the root versus one hop beyond it**: a declared
  path that climbs exactly to `root` (for example `"../base.json"` from a
  `themes/` folder one level below `root`) resolves and succeeds; the same
  path climbing one directory further (`"../../base.json"`) throws
  `escapesExtensionDirectory`. The boundary is the root directory itself,
  inclusive on the "still inside" side only in the sense that any path
  strictly below `root` succeeds. MUST.
- **Symlink escape with no literal `..` in the declared string**: a
  declared path containing no `..` at all can still escape if a symlink
  planted inside the extension's own directory points outside it; symlink
  resolution on the candidate resolves that symlink to its real target
  before the containment check runs, so the escape is caught even though
  nothing about the declared string itself was suspicious. MUST.
- **Concurrent access**: `ExtensionResourcePath`, `ExtensionResourcePathError`,
  and `InstalledContentLocation` hold no mutable stored state — every entry
  point is a pure `static` function over its arguments — so calling any of
  them concurrently, from any thread or actor, against the same or
  different directories, requires no synchronization. MUST.
- **Error states**: the only defined failure is
  `ExtensionResourcePathError.escapesExtensionDirectory`, thrown once,
  synchronously, by `resolve`. `applicationSupport` communicates its one
  "nothing to name" case by returning `nil`, never by throwing; a caller
  that ignores a `nil` result (no production caller does today) silently
  proceeds with one fewer search path rather than crashing. Stated as fact,
  not a marker — the source defines no other error condition.
- **Offline / disconnected state**: not applicable. Every operation reads
  only the local file system's symlink structure; there is no networking
  and therefore no connectivity state to lose mid-operation.
- **Cancellation and timeout**: `resolve`, `canonicalDirectory`, and
  `canonicalChild` define no timeout and no cancellation, because every
  call is synchronous local file-system metadata access with no `async`
  entry point. A slow or unresponsive mount underneath the directory being
  resolved blocks the caller for as long as symlink resolution takes, with
  no escape hatch defined in this file. Stated as fact, per the absent-
  feature rule — not a marker, since nothing in the purpose of a
  synchronous path resolver calls for one.
- **Unvalidated caller inputs beyond `appName`**: `homeDotDirectory(named:in:)`
  takes `name` at face value; the source's own doc comment states the
  dotless convention exists so that "these are hidden folders" is a
  property of this function rather than of each caller's string literal,
  but the function does not verify `name` omits a leading dot or a path
  separator — every caller today (`AIPluginManager.init`, and the test
  suite) already passes a plain identifier such as `"agenticplugins"`, so
  this is a fact about the function's contract rather than an observed
  failure.
