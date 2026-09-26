// @agentic-toolkit/adh-admin — the admin console's panes and rail, extracted from
// admin.agenticdeveloperhub so a second host (the hub's Admin workspace, at the top-level /admin)
// can mount the same twelve sections without depending on that site's app/ tree.

// The topic list and the URL-segment guard. Also published on their own as `./topics`, which is
// what a caller that needs only the names should import — this barrel carries every pane.
export { ADMIN_TOPICS, isAdminTopicId } from "./adminTopics";
export type { AdminTopic, AdminTopicId } from "./adminTopics";
export { ADMIN_PANES } from "./adminPanes";

// The query scope every pane reads through — the toolkit's client with the admin freshness pinned.
// Also published on its own as `./query`, for a host layout that wraps panes it does not import.
export { AdminQueryProvider, ADMIN_STALE_TIME } from "./AdminQueryProvider";

// The self-contained mount (rail + panes + query scope) for a host that wants the whole console
// under one base path (the hub). The admin site keeps its own AdminShell
// (HierarchicalDetailView-based) rather than this component — see AdminFeature's docstring for
// why the two hosts genuinely want different shells.
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
