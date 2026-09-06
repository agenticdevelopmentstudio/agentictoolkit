'use client';

/**
 * The barrel.
 *
 * This entry hoists `'use client'`, so the wire types and the API client are NOT re-exported
 * here — they live at `@agentic-toolkit/shipr/types` and `/client`, directive-free, so a
 * server component or a route handler can use them without dragging React in. Importing
 * them from the barrel would quietly make that impossible.
 */

// The whole mount, for a host that has a fetcher and a workspace and wants the rest decided
// here. `ShiprConsole` below is the same console with those decisions left to the caller.
export { ShiprHome } from './home';
export type { ShiprHomeProps } from './home';

export { ShiprConsole } from './ShiprConsole';
export type { ShiprConsoleProps } from './ShiprConsole';


export { RepoView, useRepoDetail } from './RepoView';
export type { RepoViewProps } from './RepoView';

export { Ladder } from './ladder/Ladder';
export type { LadderProps } from './ladder/Ladder';

export { GroupDetailPane } from './GroupDetailPane';
export type { GroupDetailPaneProps } from './GroupDetailPane';

export { RepoReport } from './report/RepoReport';
export type { RepoReportProps } from './report/RepoReport';
export { useRepoReport } from './report/useRepoReport';
export type { RepoReport as RepoReportState } from './report/useRepoReport';

export { LogLines, STATE_CLASS, STREAM_CLASS } from './activity/LogLines';
export type { LogLinesProps } from './activity/LogLines';
export { useRunLog, MAX_LINES } from './activity/useRunLog';
export type { RunLog } from './activity/useRunLog';
export { useRuns, isFinished } from './activity/useRuns';
export type { Runs } from './activity/useRuns';

export { Toolbar } from './toolbar/Toolbar';
export type { ToolbarProps } from './toolbar/Toolbar';
export { toolbarState, scopeOf } from './toolbar/actions';
export type { ActionId, ButtonState, ToolbarInput, ToolbarState } from './toolbar/actions';
export {
  ConfirmDialog,
  DeployDialog,
  MoveDialog,
  NameDialog,
  TypeToConfirmDialog,
  moveDestinations,
  useSubmit,
} from './toolbar/dialogs';
export type {
  ConnectionOption,
  DeployDialogProps,
  DeployRequest,
  TypeToConfirmDialogProps,
} from './toolbar/dialogs';
export { RegisterWizard } from './toolbar/RegisterWizard';
export type { RegisterWizardProps } from './toolbar/RegisterWizard';

export { ConfigureDialog } from './configure/ConfigureDialog';
export type { ConfigureDialogProps } from './configure/ConfigureDialog';
export { OrgDefaultsDialog } from './configure/OrgDefaultsDialog';
export type { OrgDefaultsDialogProps } from './configure/OrgDefaultsDialog';

// The forge, read once and held: what shipr can see, and what that means for a name nobody
// has created yet. Exported because a host that mounts `ConfigureDialog` itself has to build
// the catalogue to hand it — `ShiprConsole` is the only caller that does so on its own.
export { useForgeCatalogue } from './forge/useForgeCatalogue';
export type { ForgeCatalogue, ForgeOrg } from './forge/useForgeCatalogue';
export { Existence, nameOf, ownerOf, verdictFor } from './forge/existence';
export type { Verdict } from './forge/existence';

// The fleet as one file, in both directions. `document`/`plan`/`apply` are pure and could
// live outside this barrel, but the dialog above them cannot ('use client' is hoisted here),
// and splitting one small feature across two entry points would be a boundary drawn by the
// bundler rather than by the subject.
export { ImportDialog } from './exchange/ImportDialog';
export type { ImportDialogProps } from './exchange/ImportDialog';
export {
  CONFIG_VERSION,
  DEFAULT_FILENAME,
  DocumentError,
  EXPORTED_BY,
  SCHEMA,
  SCHEMA_VERSION,
  buildDocument,
  displayName,
  parseDocument,
  repoName,
  repoOwner,
  serializeDocument,
  writtenBy,
} from './exchange/document';
export type {
  ExportableGroup,
  ExportableRepo,
  ExportedConfig,
  ExportedProject,
  ExportedRemote,
  ShiprDocument,
} from './exchange/document';
export { downloadDocument, readTextFile } from './exchange/files';
export { planImport, registerBodyOf } from './exchange/plan';
export type { ImportPlan, ImportPlanOptions, PlanRow, RowState } from './exchange/plan';
export { applyImport, ImportError } from './exchange/apply';
export type { ApplyOptions, ApplyResult, ImportClient } from './exchange/apply';

export { SettingsDialog } from './settings/SettingsDialog';
export type {
  RepoSettingsPatch,
  SettingsDialogProps,
  SettingsTarget,
} from './settings/SettingsDialog';
export {
  applyFlags,
  changed,
  commonFlags,
  flagsOf,
  isUnchanged,
  mixedFlags,
} from './settings/env';
export type { EnvFlags } from './settings/env';

export { useTree } from './tree/useTree';
export type { Tree } from './tree/useTree';
export { RailMenu } from './tree/RailMenu';
export type { RailMenuProps } from './tree/RailMenu';
export { buildLevels, repoLabel, shardLabel } from './tree/toLevels';
export type { LevelsOptions } from './tree/toLevels';
export {
  childGroups,
  descendantsOf,
  planLevels,
  pathToGroup,
  reposIn,
} from './tree/levels';
export type {
  Descendant,
  LevelPlan,
  NodeKind,
  NodeRef,
  PlanOptions,
  TreePath,
} from './tree/levels';

export {
  EMPTY_SELECTION,
  isChecked,
  nodeKey,
  targetsOf,
  toggleChecked,
} from './selection';
export type { Selection } from './selection';

export { watchRun, watchWorkspaceRuns } from './live';
export type {
  EndEvent,
  LineEvent,
  RunTick,
  StateEvent,
  WatchRunOptions,
  WatchWorkspaceOptions,
} from './live';

export { columnColor, whenWidth } from './ladder/columns';
