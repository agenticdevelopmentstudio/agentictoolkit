<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat · source: ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat.md -->

# DaemonAIChat

## Overview

`DaemonAIChat.swift` (`packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift`) defines `DaemonAIChat`, a non-instantiable namespace whose single entry point, `complete(systemPrompt:userPrompt:maxTokens:cliModel:timeout:settings:runtime:cliRunner:secretStore:inferenceGuard:)`, is a headless host's reusable "ask the model one question" path — used by any daemon feature that needs a one-shot completion (session summaries, AI oversight, and similar) so every caller drives the exact same runtime rather than duplicating it.

`complete` chooses between two paths using the config-UUID-keyed registry the app syncs over `AIProviderConfigSync` and reads back through `DaemonProviderResolver`:

- **Plugin path** (a configuration is selected): loads that configuration's `.aiplugin` bundle, asks it to *describe* the request as an `AIRequestSpec`, and drives it through `PluginTransport` — the same runtime the host's interactive chat backend uses. The model comes from the configuration's own stored value, falling back to the plugin descriptor's default.
- **CLI default** (no configuration selected): a `claude -p` subprocess via `ClaudeCLI` — a zero-config path that needs no API key, so daemon features work before any provider has been configured.

When the plugin path's configuration points at a loopback model server (e.g. a local Ollama instance), `complete` additionally consults an injectable `LocalInferenceGuard` at two points — before the plugin loads (verdicting the configuration's *stored* model) and again inside the plugin path (verdicting the *effective* model, once the descriptor's default is known) — to refuse or defer a local model load that would exceed a RAM budget, and serializes allowed local completions process-wide so two host features cannot trigger two model loads at once. Remote providers and the CLI path bypass the guard entirely; passing `inferenceGuard: nil` opts out unconditionally.

Every collaborator `complete` touches — `runtime` (plugin load + run), `cliRunner` (the CLI subprocess), `settings` (the provider-registry reader), and `secretStore` (Keychain-backed secret lookup) — is an injectable parameter with a production default, so the two dispatch paths, the guard's two checkpoints, and the template-scoped secret-resolution logic can all be exercised hermetically in `DaemonAIChatTests.swift` and `DaemonAIChatGuardTests.swift` without a real bundle, network call, subprocess, or Keychain entry.

