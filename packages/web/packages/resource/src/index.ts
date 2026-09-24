// @agentic-toolkit/resource — the generic resource-browsing UI.
//
// A ResourceExplorer<T> orchestrates a selectable-resource feature (a resource
// list ▸ its topics ▸ each topic's pane) as one hierarchical topic/detail. It runs
// in two modes: standalone (renders its own HierarchicalTopicDetail — what feature
// sites use) or, inside a rail HOST (the hub's one-rail workspace shell), it
// PUBLISHES its levels/guards into the host's one merged stack. The host seam is
// the rail-host contract here; the record-affordance seam lets a host inject a
// per-record control (e.g. an api-explorer button) that standalone sites omit.

// The resource orchestrator + its config types.
export { ResourceExplorer } from "./resource-explorer";
export type { ResourceTopic, TopicLeaf, ResourceRailConfig } from "./resource-explorer";
// Re-exported (it is declared with the stack, in @agenticdevelopertoolkit/ui) because it is part of
// TopicLeaf's OWN signature: a consumer implementing a leaf here shouldn't have to reach into
// another package to name the argument the stack hands it.
export type { TopicSelectOptions } from "@agenticdevelopertoolkit/ui/blocks";

// The host-or-standalone boundary every feature ENTRY wraps its published content in:
// pass-through under an existing rail host (the hub shell), a self-hosted rail + exit
// guards on a bare feature site. ResourceExplorer routes through it internally; the
// publisher-only feature entries (research/dashboards/knowledgebases/personas) wrap
// explicitly — without it their rails/guards silently no-op standalone.
//
// StandaloneRailHost is exported ALONGSIDE it, not instead of it, for the one case the
// boundary gets wrong: a MODAL. A dialog is rendered inside the page, so the boundary finds
// the shell's host above it and becomes a pass-through — and the dialog's levels are then
// published into the page's rail, where they appear behind the dialog and outlive it. A
// dialog owns its own stack, unconditionally, and this is the component that gives it one.
// Everywhere else — every feature ENTRY — the boundary is still the right and only answer:
// an unconditional wrap inside the hub shell shadows the workspace registry (see its doc).
export { RailHostBoundary, StandaloneRailHost } from "./standalone-rail-host";

// The "All" card/list landing, the "New …" dialog, and the single-record settings pane.
export { ResourceLanding } from "./resource-landing";
export { CreateResourceDialog } from "./create-resource-dialog";
export { RecordSettingsPane } from "./record-settings-pane";

// The rail-host contract + the publisher hooks a feature uses to feed a host's stack.
export {
  RailHostContext,
  useRailHost,
  StackLevels,
  useStackLevel,
  useStackPop,
  useReportMissing,
  useReportBusy,
  useDetailTitle,
  useRailExitGuard,
  ToolbarPortal,
  useToolbarPortal,
} from "./rail-host";
export type { RailHostRegistry, RegisteredLevels, PaneExitGuard } from "./rail-host";

// The HOME BAR: the strip between the workspace bar and the breadcrumb bar. `HomeBarHost` is
// mounted by the two components that draw the workspace bar (the toolkit's SiteHomeShell and the
// hub's WorkspaceShellInner); every feature with a page-level control publishes into it with
// `HomeBarPortal`, and `HomeBar` is the shared left/right layout so the fleet's placement rule —
// filters left, primary action right — is written once. `HomeBarTaken` is how a publisher that
// hosts OTHER features marks its subtree, so a nested publisher stands down instead of sharing the
// page's one strip with it.
export { HomeBarContext, HomeBarHost, HomeBarPortal, HomeBar, HomeBarTaken } from "./home-bar";
export type { HomeBarRegistry } from "./home-bar";

// One cached item, wired to the stack's missing-item report. The query layer itself
// (`useResourceItemQuery`) lives in `@agentic-toolkit/data`; this is the composition that talks to
// the rail host.
export { useResourceItem, type ResourceItem } from "./use-resource-item";

// The HOST side of that contract. Only a rail host calls these — the hub's WorkspaceChromeProvider
// is the one outside this package — and they exist so its copy and StandaloneRailHost's cannot
// drift, alert copy included.
export { useHostPopStack, useHostMissingAlert, useHostBusyReports, useHostDetailTitle } from "./host-stack";
export type { HostMissingAlert, HostBusyReports, HostDetailTitle } from "./host-stack";

// The record-affordance seam: a host-injected per-record renderer (null standalone).
export { RecordAffordanceContext, useRecordAffordance } from "./record-affordance";
export type { RecordAffordanceProps, RecordAffordanceRenderer } from "./record-affordance";

// A grouping rail level whose members render as the deeper content of the ONE
// merged stack (navigation groups and tabbed editors alike).
export { StackGroupDetail } from "./group-topic-detail";
export type { GroupTopicItem } from "./group-topic-detail";

// URL push helpers for a feature mounted at an explicit basePath (the port of
// the hub's useFeatureRoute with the base made a parameter).
export { useBasePathRoute } from "./use-base-path-route";

// The "?" help affordance the button bars below use. Exported because a HOST
// renders the same affordance in its own chrome (the hub's workspace header,
// its settings panes) and must get the identical popover, not a second copy of
// it — a byte-identical fork of this file lived in the hub until it did.
export { HelpPopover } from "./HelpPopover";

// The master/detail substrate: the two-pane layout + its parts, the leaf editor, the
// list-as-rail-level bridge, and the editing state machine.
export {
  MasterDetailLayout,
  FeatureTitle,
  ButtonBar,
  DetailSection,
  DetailFooter,
} from "./master-detail/MasterDetailLayout";
export type { MasterDetailItem, MasterDetailActions } from "./master-detail/MasterDetailLayout";
export { SaveCancelButtons } from "./master-detail/SaveCancelButtons";
export { MasterDetailLeaf } from "./master-detail/MasterDetailLeaf";
export { useMasterDetailLevel } from "./master-detail/useMasterDetailLevel";
export { useMasterDetailForm } from "./master-detail/useMasterDetailForm";
export type { MasterDetailForm, MasterDetailFormConfig } from "./master-detail/useMasterDetailForm";
// The stored-value exemption every `validate` above shares, so the validators that grandfather a
// value differ only in which checks they skip, never in what counts as "untouched".
export { unchangedFromStored } from "./master-detail/unchangedFromStored";

// Single-record editing: the Cancel/Save bar a config pane wears, and the registry that
// carries "this pane has unsaved edits" to the exits a pane cannot guard for itself. Both
// were hub-local until a feature package needed them; the hub keeps its old import paths
// through shims.
export { EditActionBar } from "./edit-action-bar";
export {
  SettingsDirtyProvider,
  useSettingsDirty,
  useReportSettingsDirty,
} from "./settings-dirty";
// The draft half of the same job: what a settings pane's local copy has to do to survive a
// background refetch, and what a PARTIAL save has to diff against. Hand-rolled once per pane
// until four copies had produced three distinct bugs.
export { useSettingsDraft } from "./use-settings-draft";
export type { SettingsDraft } from "./use-settings-draft";

// The shared "gate didn't open" surfaces for a workspace-scoped feature (see workspace-gate).
export { WorkspaceResolutionError, WorkspaceNotManageable, ComingSoon } from "./workspace-gate";
