// @agentic-toolkit/ecosystems — the Ecosystems feature.
//
// Host-composed: the entry takes the host's ecosystem-scoped topic rail config, its
// non-ecosystems feature-panel renderer, and its config-pane renderer for the topics
// this feature reuses but doesn't own (Applications / Integrations / Buckets / Access /
// Users) — see EcosystemsFeature's prop doc comments.

export { EcosystemsFeature, IN_PACKAGE_TOPICS } from "./EcosystemsFeature";
export type {
  EcosystemsFeatureProps,
  EcosystemsTopicConfig,
  RenderTopicPaneCtx,
} from "./EcosystemsFeature";

// The feature picker + the pane that owns it — how an ecosystem, which starts empty, gets
// anything in it. Exported because the HUB opens the same picker from its /home rail: the
// user's own features live on the user's ecosystem, so both surfaces add through this one
// dialog rather than each growing its own.
export { FeaturePickerDialog } from "./FeaturePickerDialog";
export type { FeaturePickerDialogProps } from "./FeaturePickerDialog";
export { EcosystemFeaturesPane } from "./EcosystemFeaturesPane";

// The URL grammar lives at the SERVER-SAFE ./parse subpath ONLY — deliberately NOT
// re-exported here: this barrel's dist is a "use client" module, so an RSC page that
// imported the parse helper from it would throw in prod (render-only client refs).
export type { EcosystemsPathSelection } from "./parse-path";
