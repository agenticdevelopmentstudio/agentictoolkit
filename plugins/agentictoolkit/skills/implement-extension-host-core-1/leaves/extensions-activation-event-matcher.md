<!-- leaf: implement-extension-host-core-1/extensions-activation-event-matcher · source: extension-host-core-extensions-activation-event-matcher.md -->

# ActivationEventMatcher

## Overview

`ActivationEventMatcher` is `AgenticToolkitCore`'s parser and query engine for
a VS Code extension manifest's `activationEvents` array. Per its own doc
comment, it exists so a host does not "re-parse the same five prefixes at
every call site." Together with its supporting types it is the whole
activation-matching contract: `ActivationEvent` parses one manifest entry
into a typed `Kind`; `ActivationTrigger` names a thing that just happened in
the host (startup finished, a document opened, a command invoked, a webview
panel restored, a contributed view shown, or a workspace scan completed);
`WorkspaceScan` is one directory walk's paths, decomposed once for reuse
across every extension checked against it; the file-local `GlobPattern` is a
backtracking matcher for `workspaceContains:` globs; and
`ActivationEventMatcher` itself, built once per installed extension from its
`ExtensionManifest`, answers `matches(_:)` for any `ActivationTrigger` and
also implements VS Code 1.74's "implicit activation from
`contributes.commands`" rule. `ExtensionHostInstaller.swift` is the sole
production caller today: it builds one matcher per `ExtensionHostInstallation`
at construction (`self.activationMatcher = ActivationEventMatcher(manifest:
loadedExtension.manifest)`) and queries it repeatedly as startup, document-
open, command-invocation, view-shown and workspace-scan triggers occur.

