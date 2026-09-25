// src/index.ts
export { BitbagStage } from './BitbagStage'
export type { BitbagStageProps } from './BitbagStage'
export { BitbagDock } from './BitbagDock'
export type { BitbagDockProps } from './BitbagDock'
export { BitbagMini } from './BitbagMini'
export type { BitbagMiniProps } from './BitbagMini'
export { BitbagChat } from './BitbagChat'
export type { BitbagChatProps, BitbagVariant } from './BitbagChat'
export { BitbagInfo } from './BitbagInfo'
export { Bitbag, EXPRESSIONS } from './avatar'
export type { BitbagExpression, BitbagHandle } from './avatar'
export { BitbagBackend } from './backend'
export type { BitbagBackendOptions } from './backend'
export { DEFAULT_THEME, TERMINAL_THEME } from './voice'
// The theme vocabulary of the `theme` prop above, re-exported from its owner.
// A consumer that stores a user's dock theme has to validate it against the SAME
// allowlist bitbag types the prop with — and `@agenticdevelopertoolkit/themes`
// lives in a DIFFERENT submodule, which packages here (e.g. @agentic-toolkit/adh)
// deliberately don't reach into. bitbag already declares it as a peerDependency
// because it renders that vocabulary, so it is the honest place to publish it.
// Do NOT substitute `@agenticdevelopertoolkit/themes`: the two id sets are disjoint
// (`old-school-terminal` — TERMINAL_THEME above — exists only here), so swapping
// them would break the prop's type contract.
export { themeIds, type ThemeKey } from '@agenticdevelopertoolkit/themes'
