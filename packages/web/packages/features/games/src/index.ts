"use client";

// The client barrel. Every component here is a Client Component by construction —
// preserve-directives puts this file's directive on the whole chunk. There is no
// games-owned URL grammar any more (§1 of the product-gaming-modes design): the host site
// parses with `@agentic-toolkit/ecosystems/parse`'s `parseEcosystemsPath` directly, so this
// package has no `./parse` subpath to keep separate from this bundle.

export { GameEnginePane } from "./GameEnginePane";
export {
  GameOperationalFields,
  GameEngineFields,
  GAME_STATUSES,
  GAME_CHARACTER_NAMES,
  GAME_EVENT_LOGS,
  DEFAULT_EVENT_RETENTION_DAYS,
  gameBlank,
  gameToInput,
  gameValidate,
  gameDiffers,
  gameNormalize,
} from "./GameDetail";
export { GameContentPane } from "./GameContentPane";
export { GameConnectionsPane } from "./GameConnectionsPane";
export { GameEffectsPane } from "./GameEffectsPane";
export { GameSettingsPane, GameSettingsTopicPane } from "./GameSettingsPane";
export { GameNotEnabledPane } from "./GameNotEnabledPane";
export {
  useGameForEcosystem,
  type GameForEcosystem,
  GAME_FOR_ECOSYSTEM_CACHE_KEY,
  REALM_CONFIG_CACHE_KEY,
  // Exported so a pane that needs the RAW row (mode-independent) reads through the identical
  // loader rather than a near-copy of it.
  loadGameRow,
} from "./useGameForEcosystem";
export { GameChildPane, type GameChildPaneConfig } from "./GameChildPane";
export { InlineChildList, type InlineChildListConfig } from "./InlineChildList";
export { DefinitionChildren } from "./DefinitionChildren";
export {
  DefinitionFields,
  DEFINITION_STATUSES,
  definitionBlank,
  definitionToInput,
  definitionNormalize,
  definitionDiffers,
  definitionValidate,
  definitionLabel,
} from "./DefinitionDetail";
export {
  EffectFields,
  EFFECT_TRIGGERS,
  EFFECT_OPERATIONS,
  effectBlank,
  effectToInput,
  effectNormalize,
  effectDiffers,
  effectValidate,
  effectLabel,
} from "./EffectDetail";
export {
  MappingFields,
  mappingBlank,
  mappingToInput,
  mappingNormalize,
  mappingDiffers,
  mappingValidate,
  mappingLabel,
} from "./MappingDetail";
export { SlotsEditor } from "./SlotsEditor";
export {
  readSlots,
  writeSlots,
  validateSlots,
  type FormSlot,
  type SlotInputMode,
  type SlotsDoc,
  type SlotsRead,
} from "./slots";
export {
  INT4_MAX,
  INT4_MIN,
  intFieldOr,
  intText,
  optionalIntField,
  optionalIntText,
  optionalWholeNumberProblem,
  wholeNumberProblem,
} from "./fields";
export { IntegerInput, OptionalIntegerInput } from "./IntegerInput";
export { inlineUrlSelection } from "./inlineSelection";
export { sortByGroup } from "./group";
export { GAME_TOPICS } from "./topics";
export { GamesFeature, type GamesFeatureProps } from "./GamesFeature";
