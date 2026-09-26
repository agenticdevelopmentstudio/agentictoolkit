// @agentic-toolkit/adh-admin — the admin console's panes and rail, extracted from
// admin.agenticdeveloperhub so a second host (the hub, at /<workspace>/admin) can mount the same
// twelve sections without depending on that site's app/ tree.

// The topic list, the pane lookup it drives, and the URL-segment guard — the admin site's own
// AdminShell imports ADMIN_TOPICS from here instead of defining it locally.
export { ADMIN_TOPICS, ADMIN_PANES, isAdminTopicId } from "./adminTopics";
export type { AdminTopic, AdminTopicId } from "./adminTopics";

// The rail-hosted mount for a host already inside its own topic/detail stack (the hub). The
// admin site keeps its own AdminShell (HierarchicalDetailView-based) rather than this component —
// see AdminFeature's docstring for why the two hosts genuinely want different shells.
export { AdminFeature } from "./AdminFeature";

// Every pane, standalone — the admin site's twelve app/(admin)/<topic>/page.tsx mounts import
// their own pane directly rather than going through ADMIN_PANES, since a page.tsx's default
// export must be that one component, named, not a map lookup.
export { AuditPane } from "./panes/AuditPane";
export { AuthenticationPane } from "./panes/AuthenticationPane";
export { FeatureFlagsPane, FlagDialog } from "./panes/FeatureFlagsPane";
export { FeedbackPane, FeedbackDialog } from "./panes/FeedbackPane";
export { InvitationsPane } from "./panes/InvitationsPane";
export { LlmProvidersPane } from "./panes/LlmProvidersPane";
export { MessagingPane } from "./panes/MessagingPane";
export { ReservedIdentifiersPane } from "./panes/ReservedIdentifiersPane";
export { ServerBagsPane, BagDialog } from "./panes/ServerBagsPane";
export { SyncPane } from "./panes/SyncPane";
export { UsagePane, TierDialog } from "./panes/UsagePane";
export { UsersPane } from "./panes/UsersPane";
