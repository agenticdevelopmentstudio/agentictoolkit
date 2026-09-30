import type { ComponentType, ReactNode } from "react";

import { AuditPane } from "./panes/AuditPane";
import { AuthenticationPane } from "./panes/AuthenticationPane";
import { FeatureFlagsPane } from "./panes/FeatureFlagsPane";
import { FeedbackPane } from "./panes/FeedbackPane";
import { InvitationsPane } from "./panes/InvitationsPane";
import { LlmProvidersPane } from "./panes/LlmProvidersPane";
import { MessagingPane } from "./panes/MessagingPane";
import { ReservedIdentifiersPane } from "./panes/ReservedIdentifiersPane";
import { ServerBagsPane } from "./panes/ServerBagsPane";
import { SyncPane } from "./panes/SyncPane";
import { UsagePane } from "./panes/UsagePane";
import { UsersPane } from "./panes/UsersPane";

import type { AdminTopicId } from "./adminTopics";

// Apart from adminTopics.ts so the topic list stays cheap to import: the admin site's shell (and
// any rail or route that only needs the names, icons and the id guard) reads `./topics`, and a
// module that ALSO held this map would pull all twelve panes — react-query, the editors, the
// dialogs — into every chunk that wanted a label.

/** Every topic's detail pane, keyed by {@link AdminTopicId}. Both hosts (the admin site's own
 *  `AdminShell` and this package's `AdminFeature`) render off this same map, so a pane added
 *  here appears in both places by construction rather than by two call sites agreeing. */
export const ADMIN_PANES: Record<AdminTopicId, ComponentType<{ help?: ReactNode }>> = {
  users: UsersPane,
  invitations: InvitationsPane,
  "feature-flags": FeatureFlagsPane,
  "server-bags": ServerBagsPane,
  sync: SyncPane,
  audit: AuditPane,
  messaging: MessagingPane,
  feedback: FeedbackPane,
  authentication: AuthenticationPane,
  "llm-providers": LlmProvidersPane,
  usage: UsagePane,
  "reserved-identifiers": ReservedIdentifiersPane,
};
