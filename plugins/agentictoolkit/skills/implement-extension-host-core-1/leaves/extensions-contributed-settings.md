<!-- leaf: implement-extension-host-core-1/extensions-contributed-settings · source: extension-host-core-extensions-contributed-settings.md -->

# ContributedSettings

## Overview

`ContributedSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ContributedSettings.swift`) turns one VS Code extension manifest's `contributes.configuration` block into the rows a settings panel can render, and every compromise that block forced along the way. It defines the row value types — `ContributedSettingOption`, `ContributedSettingKind` (a six-case control vocabulary: `toggle`, `text`, `choice`, `number`, `integer`, `json`), `ContributedSetting`, and `ContributedSettingsSection` — a `ContributedSettingNote` record for every schema declaration this host could not honour exactly, a `ContributedSettingsDeclaration` distinguishing "no settings declared," "settings declared but none survived classification," and "the schema itself could not be read," and the pure static namespace `ContributedSettingsBuilder`, which does the classifying.

The file is Foundation-only and holds no state of its own: nothing in it reads or writes a setting's stored value, opens a file, or touches a window. That is `ConfigurationContributionPoint`'s job (`packages/apple/AgenticToolkit/macOS/Features/Extensions/ConfigurationContributionPoint.swift`, part of the macOS-only `AgenticToolkitMacOS`/`AgenticToolkitCore` split), the AppKit half that remembers what was applied per extension via `ContributionRegistrations` (`ContributionPoint.swift`) and turns a `ContributedSettingsDeclaration` into actual views. This recipe covers `ContributedSettings.swift` alone; `ExtensionManifest`, `ContributionPoint`, and `ConfigurationContributionPoint` are collaborators consulted for grounding but are out of this recipe's scope.

