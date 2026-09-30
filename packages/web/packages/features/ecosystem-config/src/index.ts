// @agentic-toolkit/ecosystem-config — the panes that configure an ECOSYSTEM.
//
// The package is named for the ECOSYSTEM, not for any one owner: the hub mounts these panes for a
// product's ecosystem and for a workspace's default ecosystem, and the organizations site mounts
// them for an org's. Naming it after any of those three would have made the other two look like
// exceptions.
//
// Every export below is one pane. There is no grouping component: the hub, the products feature
// and the organizations feature each arrange the rows they want on their own rail, so a
// `ConfigurationGroup` here would be a fourth arrangement with no host.
//
// A host holding a WORKSPACE rather than an ecosystem id wraps its pane in `EcosystemConfigGate`,
// which resolves the workspace's default ecosystem and explains itself when it can't.
export { EcosystemConfigGate } from "./EcosystemConfigGate";

export { BillingPane } from "./BillingPane";
export { ClientAuthSettingsPane, ECOSYSTEM_CLIENT_AUTH_KEY } from "./ClientAuthSettingsPane";
export {
  ApplicationClientAuthSection,
  useApplicationClientAuth,
  type ApplicationClientAuthState,
} from "./ApplicationClientAuthSection";
export { ClientAuthPolicyFields, LoginRegistrationFields } from "./ClientAuthFields";
export { FeatureFlagsPane, FlagDialog } from "./FeatureFlagsPane";
export { ServerBagsPane, BagDialog } from "./ServerBagsPane";
export { StorageTokensPanel } from "./StorageTokensPanel";

// No help-text export. The sentences these panes show live in adh's site-config content package —
// the product's VOCABULARY tier, which a portable package may not import (scripts/check_boundaries.py).
// The host passes its own lookup in as `ConfigurationGroup`'s `helpFor`, and each pane already
// takes its blurb as a `help` prop.
