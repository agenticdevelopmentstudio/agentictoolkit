<!-- leaf: implement-ai-plugin-2/runtime-core-ai · source: ai-plugin-runtime-core-ai.md -->

# Core AI Runtime

## Overview

The Core AI Runtime is the non-UI logic root for talking to AI chat backends and
discovering what models they offer. It has eight parts:

- `AIProvider` — the `Sendable` enum identifying the five supported backends
  (`claudeCLI`, `anthropic`, `openai`, `google`, `custom`) and their display
  metadata (name, default models, recommended model, API-key placeholder,
  default base URL).
- `AIRequestConfig` / `AIRequestBuilder` — turns a provider selection and a
  message list into a provider-shaped `URLRequest`, and parses a provider's
  JSON reply or error body back into plain text.
- `ArtificialAnalysisStore` — fetches and caches per-model intelligence/coding
  index rankings from the Artificial Analysis leaderboard API, and holds the
  API key that gates it.
- `ClaudeCLI` — runs the local `claude -p` binary as a subprocess so a caller
  can get a model reply without an API key, reusing the user's existing
  Claude Code login.
- `ModelCatalogStore` — fetches and merges prose model descriptions from
  OpenRouter, models.dev, and the adh provider-template catalog, then matches
  a bare or namespaced model id against them.
- `OllamaModelMetadata` (`LocalModelMetadataStore`) — asks a local Ollama
  server's native `/api/show` route what a pulled model can do and how big it
  is.
- `OllamaModelPageStore` — scrapes a model's `ollama.com` page for its author
  blurb and live popularity stats, the only place that prose exists for
  community fine-tunes.
- `OpenAIModelCatalog` — lists the models an OpenAI-compatible `/models`
  endpoint actually serves.

All eight types are Foundation-only: no SwiftUI, AppKit, or UIKit import
appears anywhere in this component, and none of them render anything.

