<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--part-2 · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins) — continued (part 2)

**Rules** (cite as `implement-ai-plugin-2/runtime-features-ai-plugins--part-2#<slug>`):

- `config-store-key-delegation` MUST
- `config-store-secret-routing` MUST
- `config-store-model-default` MUST
- `config-store-values-overlay` MUST
- `config-store-seed` MUST
- `config-store-clear` MUST
- `defaults-guarded-once` MUST
- `defaults-only-when-empty` MUST
- `defaults-template-lookup` MUST
- `defaults-seeded-configuration` MUST
- `defaults-leaves-unselected` MUST
- `migration-plan-is-pure` MUST
- `migration-template-selection` MUST
- `migration-inclusion-rule` MUST
- `migration-name-dedup` MUST
- `migration-field-write-rule` MUST
- `migration-model-write-rule` MUST
- `migration-selected-id` MUST
- `migration-run-once` MUST
- `migration-apply` MUST
- `migration-legacy-values-untouched` MUST
- `migration-legacy-secret-retained` MUST
- `resolver-shape` MUST
- `resolver-descriptor-lookup` MUST
- `resolver-fails-closed-on-template` MUST
- `resolver-values` MUST

### AIProviderConfigStore

- **config-store-key-delegation**: `AIProviderConfigStore.fieldKey(config:field:)`
  and `modelKey(config:)` MUST delegate to `AIProviderConfigKeys`, producing
  `"aiplugin.config.<uuid>.field.<key>"` and
  `"aiplugin.config.<uuid>.model"` respectively.
- **config-store-secret-routing**: `fieldSetting(config:field:)` MUST
  construct its `UserSetting<String>` with `isSecure: field.isSecret`.
- **config-store-model-default**: `selectedModel(config:template:)` MUST
  return the stored model value when non-empty, else
  `template.resolvedDefaultModel`.
- **config-store-values-overlay**: `configValues(for:template:fields:)` MUST
  start from `template.defaultValues`, then for each field overlay the
  stored value into the result UNDER TWO CONDITIONS: the field `isSecret`
  (always overlaid, even when the stored value is empty), or the stored
  value is non-empty. A field that is not secret and whose stored value is
  empty MUST NOT overwrite a template default for that key. The result MUST
  always include a `"model"` entry from `selectedModel(config:template:)`.
- **config-store-seed**: `seed(config:template:fields:)` MUST, for each
  field that has an entry in `template.defaultValues`, write that default
  into the field's stored setting; a field with no corresponding template
  default MUST be left at its setting's own default (`""`). It MUST also set
  the model setting to `template.resolvedDefaultModel`.
- **config-store-clear**: `clearStoredValues(config:fields:)` MUST reset
  every given field's stored value to `""` and the configuration's model
  setting to `""`; because a secret field's `UserSetting` has
  `isSecure: true`, writing `""` MUST remove that value from the Keychain.
  `clearStoredValues` MUST accept no `template` parameter, so it remains
  callable even when the configuration's template no longer resolves (a
  removed plugin or a renamed template).

### AIProviderDefaults

- **defaults-guarded-once**: `seedIfNeeded(pluginManager:)` MUST return
  immediately without side effects once `UserSettings.aiDefaultConfigSeeded`
  is `true`; otherwise it MUST set `aiDefaultConfigSeeded` to `true` before
  returning, regardless of whether seeding actually produced a configuration.
- **defaults-only-when-empty**: `seedIfNeeded` MUST NOT write to
  `UserSettings.aiProviderConfigurations` when that list is already
  non-empty — an existing user- or migration-created list MUST be left
  untouched.
- **defaults-template-lookup**: `seedIfNeeded` MUST look up a template whose
  `id == "claude-local"` (`AIProviderDefaults.defaultTemplateId`) among
  `pluginManager.availableTemplates`; when no such template is advertised, it
  MUST leave `aiProviderConfigurations` empty.
- **defaults-seeded-configuration**: When the `claude-local` template is
  found and the list is empty, `seedIfNeeded` MUST build one
  `AIProviderConfiguration` named after the template's `displayName`, seed
  its stored field values and model via `AIProviderConfigStore.seed`, and set
  `aiProviderConfigurations.value` to the single-element array containing it.
- **defaults-leaves-unselected**: `seedIfNeeded` MUST NOT set
  `UserSettings.selectedAIProviderConfigurationId` — the seeded configuration
  is deliberately left unselected so behavior matches the daemon's
  zero-config "Default (Claude CLI)" path exactly.

### AIProviderMigration

- **migration-plan-is-pure**: `AIProviderMigration.plan(descriptors:legacySelected:oldValues:)`
  MUST be a pure function of its arguments — it MUST perform no I/O and MUST
  NOT read or write any `UserSetting`.
- **migration-template-selection**: For each descriptor, `plan` MUST select
  the template whose `id` matches `legacyTemplateId[descriptor.identifier]`
  when that lookup succeeds and the descriptor advertises a template with
  that id, else the first entry of `descriptor.resolvedTemplates`.
- **migration-inclusion-rule**: `plan` MUST include a descriptor in the
  output only if at least one of the following holds: (a) some secret field
  has a non-empty legacy value (`hasSecret`), (b) the descriptor's identifier
  equals `legacySelected` and `legacySelected` is non-empty (`isSelected`),
  or (c) some non-secret field's legacy value is non-empty and differs from
  that field's template default (`hasCustomField`). A descriptor matching
  none of these MUST be skipped entirely — no configuration, field write, or
  model write MUST be produced for it.
- **migration-name-dedup**: `plan` MUST name each produced configuration via
  `AIProviderConfiguration.uniqueName(descriptor.displayName, avoiding:)`,
  avoiding the names already assigned to configurations earlier in the same
  plan.
- **migration-field-write-rule**: For an included descriptor, `plan` MUST
  emit a `FieldWrite` for a field only when
  `values[field.key] ?? template.defaultValues[field.key] ?? ""` is
  non-empty; a field that resolves to empty after that fallback MUST NOT
  produce a `FieldWrite`.
- **migration-model-write-rule**: For an included descriptor, `plan` MUST
  emit exactly one model write per configuration, using
  `values["model"]` when present and non-empty, else
  `template.resolvedDefaultModel`.
- **migration-selected-id**: `plan.selectedId` MUST be set to the newly
  created configuration's `id.uuidString` for the (at most one) descriptor
  where `isSelected` is true, and MUST remain `""` otherwise.
- **migration-run-once**: `runIfNeeded(pluginManager:)` MUST return
  immediately, performing no writes, once `UserSettings.aiProvidersMigrated`
  is `true`.
- **migration-apply**: When migration has not yet run, `runIfNeeded` MUST
  build a plan from `pluginManager.descriptors`,
  `PluginConfigStore.selectedPluginSetting().currentValue`, and
  `PluginConfigStore.configValues(for:)`, then apply every `fieldWrites`
  entry (via a fresh `UserSetting<String>` keyed by
  `AIProviderConfigStore.fieldKey` with `isSecure: write.isSecret`) and every
  `modelWrites` entry (via `AIProviderConfigStore.modelKey`), then set
  `UserSettings.aiProviderConfigurations` to `plan.configurations` (even when
  that array is empty), then set
  `UserSettings.selectedAIProviderConfigurationId` to `plan.selectedId` ONLY
  when `plan.selectedId` is non-empty (an empty `plan.selectedId` MUST leave
  the existing selection setting untouched), and finally set
  `UserSettings.aiProvidersMigrated` to `true`.
- **migration-legacy-values-untouched**: `runIfNeeded` MUST NOT delete,
  clear, or overwrite any legacy `PluginConfigStore`-keyed setting
  (`"aiplugin.<identifier>.field.<key>"`, `"aiplugin.<identifier>.model"`, or
  `"aiplugin.selectedPlugin"`) as part of migrating it — it only reads them.
- **migration-legacy-secret-retained**: after `AIProviderMigration.runIfNeeded`
  copies a legacy secret (`"aiplugin.<identifier>.field.<key>"`, written with
  `isSecure: true`) into the new per-configuration key, the legacy Keychain
  entry MUST remain in place; no code path removes it.

### AIProviderResolver

- **resolver-shape**: `AIProviderResolver.resolve(_:manager:)` MUST return an
  optional `Resolved` value carrying `pluginIdentifier`, `model`, `values`,
  and `fields`.
- **resolver-descriptor-lookup**: `resolve` MUST return `nil` when
  `manager.descriptor(for: config.pluginIdentifier)` returns `nil` (the
  plugin is no longer installed/discovered).
- **resolver-fails-closed-on-template**: `resolve` MUST return `nil` when the
  resolved descriptor's `resolvedTemplates` contains no template whose `id`
  equals `config.templateId`. `resolve` MUST NOT fall back to
  `resolvedTemplates.first` in this case — doing so would silently bind the
  configuration's stored credentials and model to an unrelated provider
  template.
- **resolver-values**: When both lookups succeed, `resolve` MUST return
  `values` from `AIProviderConfigStore.configValues(for:template:fields:)`
  and `model` from `AIProviderConfigStore.selectedModel(config:template:)`,
  using `fields = descriptor.fields(for: template)`.

