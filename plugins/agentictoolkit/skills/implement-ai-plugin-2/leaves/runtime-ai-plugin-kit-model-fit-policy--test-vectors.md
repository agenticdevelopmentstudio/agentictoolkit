<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-fit-policy--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-model-fit-policy.md -->

# ModelFitPolicy

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| model-fit-policy-001 | tier-classification, tier-threshold-defaults | `tier(diskBytes: 12_500_000_000, physicalRAM: 64_000_000_000)` — thresholds omitted (`ModelFitPolicyTests.swift`, `tierBoundaries`). | `.ok` — est. 15.0 GB ≈ 23% of RAM, under the default 25% warn threshold. |
| model-fit-policy-002 | tier-classification | `tier(diskBytes: 14_000_000_000, physicalRAM: 64_000_000_000)` (`tierBoundaries`). | `.warn` — est. 16.8 GB ≈ 26% of RAM, at or above 25% and below 50%. |
| model-fit-policy-003 | tier-classification | `tier(diskBytes: 27_000_000_000, physicalRAM: 64_000_000_000)` (`tierBoundaries`). | `.block` — est. 32.4 GB ≈ 51% of RAM, at or above the default 50% block threshold. |
| model-fit-policy-004 | tier-unknown-size, tier-zero-ram | `tier(diskBytes: nil, physicalRAM: 64_000_000_000)` and `tier(diskBytes: 1, physicalRAM: 0)` (`unknownSizeHasNoTier`). | Both return `nil`. |
| model-fit-policy-005 | verdict-block-reason-format, footprint-description-format, verdict-required-thresholds | `verdict(model: "qwen3-coder-next:latest", diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000, warnPct: 25, blockPct: 50, pressure: .normal)` (`verdictBlocksOverBudgetModel`). | `.block(reason:)` containing `"qwen3-coder-next:latest"`, `"~61.2 GB (~96% of RAM)"`, and `"50% of 64.0 GB"`. |
| model-fit-policy-006 | footprint-description-format, gb-string-format, ram-pct-computation | `footprintDescription(estimatedBytes: 24_000_000_000, physicalRAM: 64_000_000_000)` (`footprintDescriptionSharedCore`). | Returns exactly `"~24.0 GB (~38% of RAM)"`. |
| model-fit-policy-007 | fit-info-ok-text | `fitInfo(diskBytes: 8_900_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "8.9 GB (~17% of RAM)", tier: .ok)`. |
| model-fit-policy-008 | fit-info-warn-text | `fitInfo(diskBytes: 20_000_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "20.0 GB ⚠ large: ~38% of RAM", tier: .warn)`. |
| model-fit-policy-009 | fit-info-block-text | `fitInfo(diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `FitInfo(text: "51.0 GB — won't run: exceeds memory budget", tier: .block)`. |
| model-fit-policy-010 | fit-info-unknown | `fitInfo(diskBytes: nil, physicalRAM: 64_000_000_000)` (`fitInfoStructured`). | `nil`. |
| model-fit-policy-011 | pressure-verdict-elevated, verdict-pressure-precedence | `verdict(model: "llama3.1:8b", diskBytes: diskBytes, physicalRAM: 64_000_000_000, warnPct: 25, blockPct: 50, pressure: .warning)` for `diskBytes` in `[4_900_000_000, nil]` (`verdictDefersUnderPressure`). | `.deferred(reason:)` containing `"memory pressure is warning"` in both cases, even with a known small size or an unknown size. |
| model-fit-policy-012 | verdict-allow-non-block-tier, pressure-verdict-normal | `verdict` with `pressure: .normal` for `diskBytes` 4.9 GB (`.ok`), 20 GB (`.warn`), and `nil` (unknown) at 64 GB RAM (`verdictAllowsOkWarnAndUnknownSize`). | `.allow` in all three cases. |
| model-fit-policy-013 | picker-label-known | `pickerLabel(model: "deepseek-coder-v2:16b", diskBytes: 8_900_000_000, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"deepseek-coder-v2:16b — 8.9 GB (~17% of RAM)"`. |
| model-fit-policy-014 | picker-label-known | `pickerLabel(model: "huge", diskBytes: 51_000_000_000, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"huge — 51.0 GB — won't run: exceeds memory budget"`. |
| model-fit-policy-015 | picker-label-unknown | `pickerLabel(model: "mystery", diskBytes: nil, physicalRAM: 64_000_000_000)` (`pickerLabels`). | Returns exactly `"mystery"`. |
| model-fit-policy-016 | estimated-bytes, resident-overhead-multiplier | `estimatedBytes(diskBytes: 51_000_000_000)`. | Returns `61_200_000_000` (`51_000_000_000 * 1.2`). |
| model-fit-policy-017 | ram-pct-zero-ram | `ramPct(1_000_000_000, of: 0)`. | Returns `0`. |
| model-fit-policy-018 | default-thresholds, threshold-setting-keys | Read `ModelFitPolicy.defaultWarnPct`, `defaultBlockPct`, `warnPctKey`, `blockPctKey` directly. | `25`, `50`, `"ai_guard_warn_pct"`, `"ai_guard_block_pct"` respectively. |
| model-fit-policy-019 | memory-pressure-cases, tier-cases, verdict-cases, fit-info-shape | Construct `MemoryPressureLevel.warning`, `ModelFitPolicy.Tier.warn`, `ModelFitPolicy.Verdict.block(reason: "x")`, and `ModelFitPolicy.FitInfo(text: "t", tier: .ok)` and compare each for equality with itself. | Each equals itself under `==` (all four types conform to `Equatable`); each also compiles when passed across a `Task { ... }` boundary (all four conform to `Sendable`). |
| model-fit-policy-020 | namespace-isolation | Call `ModelFitPolicy.tier(...)` synchronously from a `@MainActor` context and, separately, from inside a non-`AIPluginKit` `actor`'s method, with no `await`. | Both call sites compile and run without an `await`, because `ModelFitPolicy` carries no isolation of its own. |
