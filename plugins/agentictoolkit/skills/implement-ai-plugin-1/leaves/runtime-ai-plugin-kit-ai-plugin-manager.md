<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-manager · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-manager.md -->

# AI Plugin Manager

## Overview

`AIPluginManager.swift` (`packages/apple/AgenticToolkit/AIPluginKit/AIPluginManager.swift`) defines `AIPluginManager`, a `@MainActor` class that discovers, describes, and loads LLM provider plugins shipped as macOS `.aiplugin` bundles. A plugin bundle's `NSPrincipalClass` conforms to `AIPluginKit.AIPlugin`. Discovery reads each bundle's `descriptor.json` — a plain JSON resource describing the plugin's identity, models, settings fields, and provider templates — without loading (`dlopen`-ing) the plugin's binary, so a settings UI can list and configure a plugin from its descriptor alone. Loading a plugin (`bundle.load()` plus instantiating the `NSPrincipalClass`) only happens on demand, the first time a caller asks for that plugin's instance, and the resulting instance is cached for the manager's lifetime. The manager owns no networking, no UI, and no secret storage — those belong to the loaded `AIPlugin`, the settings UI built from the descriptor, and `AIPluginKit`'s secret-storage types respectively.

