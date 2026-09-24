"use client";

import type { ReactNode } from "react";
import {
  User,
  CreditCard,
  Gauge,
  Globe,
  Palette,
  Share2,
  MapPin,
  Mail,
  Key,
  Bell,
  Shield,
  Bot,
  Archive,
  Keyboard,
} from "lucide-react";
import {
  AccountPanel,
  ArchivedPanel,
  ContactInfoPanel,
  NotificationsWorkspace,
  ProfilePanel,
  SecurityWorkspace,
  SettingsLayout,
  SubscriptionPanel,
  type Topic,
} from "@agentic-toolkit/account";
import { UsagePanel, SocialLinksPanel, AddressesPanel } from "@agentic-toolkit/profile";
import { TokensPanel } from "@agentic-toolkit/authentication";
import { AssistantsPanel } from "@agentic-toolkit/personas";
import { FeatureTitle, SettingsDirtyProvider } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";

// Relative, and deliberately NOT the "@agentic-toolkit/adh/site" package path the topics
// import below uses — the two rules point opposite ways here, so record which applies.
// `@agentic-toolkit/adh/site` is absent from tsup's `external` list (only its
// `site/hubWorkspacePath` leaf is there, tsup.config.ts:272), on purpose: the barrel holds no
// module state (see site/index.ts's own header — "owes tsup no `external` pairing"), so two
// copies cannot disagree about anything, and the package path would only turn a tree-shaken
// inline into a runtime import of the whole barrel. Measured on the built output: esbuild
// drops `defineSite` and keeps 5,737 B of slug data, inside the 19,916 B
// UserSettingsOverlay chunk — which is LAZY, so none of it reaches a page that never opens
// settings. Making it external would cost more, not less. The rule that bans a relative
// import is about client-directive taint and module identity; neither is in play here.
import { reservedWorkspaceSlugs } from "../site";
import { siteUrl } from "@agentic-toolkit/adh-registry";
import { AppearancePanel } from "./AppearancePanel";
// Relative, like AppearancePanel above and for the same reason: this panel is part of
// THIS entry and holds no module state of its own. The store it writes through to does,
// and that one it imports by package path — see its own header.
import { HubPreferencesPanel } from "./HubPreferencesPanel";
// Package path, not "./topics": this is the same specifier a Server Component outside this
// package must use to reach these exports without going through the "use client"-tainted
// settings/index barrel — using it here too keeps one documented route, in and out of the
// package. See topics.ts's and settings/index.ts's own header comments.
import {
  SETTINGS_TOPICS,
  resolveSettingsTopic,
  type SettingsTopicId,
} from "@agentic-toolkit/adh/settings/topics";

// The four tables below are keyed by `SettingsTopicId`, not by `string`, and the split
// between TOTAL and PARTIAL is the contract:
//   • ICONS and PANELS are `Record<SettingsTopicId, …>` — every section must have both.
//     Keyed by `string` (as they were), adding a 14th topic to topics.ts compiled clean
//     and shipped a rail row with no icon that rendered an EMPTY details pane.
//   • HELP and API_PATHS are `Partial` — an absent entry is a real answer there (no help
//     line, no backing endpoint), so requiring
//     them would force placeholder junk.
const ICONS: Record<SettingsTopicId, ReactNode> = {
  account: <User size={16} aria-hidden />,
  security: <Shield size={16} aria-hidden />,
  subscription: <CreditCard size={16} aria-hidden />,
  usage: <Gauge size={16} aria-hidden />,
  profile: <Globe size={16} aria-hidden />,
  appearance: <Palette size={16} aria-hidden />,
  social: <Share2 size={16} aria-hidden />,
  addresses: <MapPin size={16} aria-hidden />,
  contacts: <Mail size={16} aria-hidden />,
  notifications: <Bell size={16} aria-hidden />,
  tokens: <Key size={16} aria-hidden />,
  assistants: <Bot size={16} aria-hidden />,
  archived: <Archive size={16} aria-hidden />,
  preferences: <Keyboard size={16} aria-hidden />,
};

const HELP: Partial<Record<SettingsTopicId, string>> = {
  account: "Your sign-in email and password.",
  security: "Two-factor authentication, passkeys and recovery codes.",
  notifications: "What the hub tells you about, and on which channel.",
  subscription: "Your plan and billing.",
  usage: "This period’s calls, data, tokens and spend, per principal.",
  profile: "Your public display name and profile URL.",
  appearance: "Theme, motion, contrast, text size, and spacing.",
  social: "Links to your public profiles on other platforms.",
  addresses: "Physical addresses shown on your card.",
  contacts: "Emails and phone numbers shown on your card.",
  tokens: "Create and revoke personal API tokens.",
  assistants: "Control, per tool, what each assistant may do on your behalf.",
  archived: "Organizations you've archived. Restore one while its handle is still free.",
  preferences: "How the hub itself behaves on this browser, including its keyboard shortcut.",
};

// ProfilePanel takes the host's reserved slug words as a prop (see its own doc comment).
// `reservedWorkspaceSlugs()` is the family's ONE list — see site/reservedSlugs.ts — not a
// copy local to this surface: hub's own /settings route reads the identical function, and
// a settings modal that shipped a narrower or different list would let a slug through here
// that is unreachable on some other site in the family.
const PANELS: Record<SettingsTopicId, ReactNode> = {
  account: <AccountPanel />,
  security: <SecurityWorkspace />,
  subscription: <SubscriptionPanel />,
  usage: <UsagePanel />,
  profile: (
    <ProfilePanel
      reservedSlugs={reservedWorkspaceSlugs()}
      profileUrlFor={(slug) =>
        siteUrl("hub", `/${encodeURIComponent(slug)}`, window.location.hostname)
      }
    />
  ),
  appearance: <AppearancePanel />,
  social: <SocialLinksPanel />,
  addresses: <AddressesPanel />,
  contacts: <ContactInfoPanel />,
  notifications: <NotificationsWorkspace />,
  tokens: <TokensPanel />,
  assistants: <AssistantsPanel />,
  archived: <ArchivedPanel />,
  preferences: <HubPreferencesPanel />,
};

// Backend endpoint each settings section maps to — drives the FeatureTitle "API"
// button. Self endpoints (/auth/me) and collections take no path params. Sections
// with no backing endpoint (appearance = local theme, preferences = this browser only,
// subscription = placeholder) are omitted, so no button shows.
//
// EVERY section gets its title and API button from here. Security and Notifications used to
// draw their own (a SectionHeader plus a RecordApiButton inside the panel, relocated whole from
// their old feature routes) and skip this one — which put their API link in a different place,
// their content centred, and made them read as pages from another site. One title, one place.
const API_PATHS: Partial<Record<SettingsTopicId, string>> = {
  account: "/auth/me",
  security: "/account/mfa",
  notifications: "/notifications/preferences",
  usage: "/usage/summary",
  profile: "/auth/me",
  social: "/content/social-links",
  addresses: "/content/addresses",
  contacts: "/account/contacts",
  tokens: "/auth/tokens",
  assistants: "/access/personas/user-actable",
  archived: "/workspaces/archived",
};

/** The settings sections (Account, Subscription, Profile) as master-detail
 *  topics — each leads with a gold title and carries its own panel + button bar.
 *  Shared by hub's /settings route and the User Settings overlay every site mounts. */
export function buildSettingsTopics(): Topic[] {
  return SETTINGS_TOPICS.map((t) => {
    const apiPath = API_PATHS[t.id];
    return {
      id: t.id,
      label: t.label,
      icon: ICONS[t.id],
      // Inert in the overlay: SettingsLayout's nav rows are <button>s, and controlled
      // mode (onNavigate, which UserSettingsOverlay always supplies) returns before
      // router.push ever runs — see SettingsLayout.tsx. Live only on hub's /settings
      // route, which renders this same list uncontrolled. Do not "fix" it to match the
      // overlay's actual URL; there isn't one.
      href: `/settings/${t.id}`,
      content: (
        <div className="flex min-h-0 min-w-0 flex-1 flex-col">
          <FeatureTitle
            title={t.label}
            help={HELP[t.id]}
            trailing={
              apiPath ? (
                <RecordApiButton path={apiPath} pathValues={{}} title={`${t.label} API`} />
              ) : undefined
            }
          />
          {PANELS[t.id]}
        </div>
      ),
    };
  });
}

/**
 * The User Settings tab, rendered as a routed page — used by hub's own /settings, and
 * kept available here for any other host that wants a standalone route rather than the
 * overlay. Builds its own SettingsDirtyProvider so a dirty panel is caught even under no
 * workspace chrome; the overlay (UserSettingsOverlay.tsx) wraps its own instance around
 * this same buildSettingsTopics() list instead of rendering this component, so the dirty
 * registry and the dialog frame are scoped to one mount.
 */
export function SettingsTab({ activeTopic }: { activeTopic?: string }) {
  return (
    <SettingsDirtyProvider>
      <SettingsLayout
        topics={buildSettingsTopics()}
        activeId={resolveSettingsTopic(activeTopic)}
      />
    </SettingsDirtyProvider>
  );
}
