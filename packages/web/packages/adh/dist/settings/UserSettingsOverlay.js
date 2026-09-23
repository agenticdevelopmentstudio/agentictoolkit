"use client";

"use client";

// src/settings/UserSettingsOverlay.tsx
import { useState as useState2 } from "react";
import {
  Dialog,
  DialogContent,
  DialogTitle
} from "@agenticdevelopertoolkit/ui/components/dialog";
import { UnsavedChangesAlert } from "@agenticdevelopertoolkit/ui/components/unsaved-changes-alert";
import { useMediaQuery } from "@agenticdevelopertoolkit/ui/hooks/useMediaQuery";
import { SettingsLayout as SettingsLayout2 } from "@agentic-toolkit/account";
import { SettingsDirtyProvider as SettingsDirtyProvider2, useSettingsDirty } from "@agentic-toolkit/resource";
import { ToolkitQueryProvider } from "@agentic-toolkit/data/query";

// src/settings/registry.tsx
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
  Keyboard
} from "lucide-react";
import {
  AccountPanel,
  ArchivedPanel,
  ContactInfoPanel,
  NotificationsWorkspace,
  ProfilePanel,
  SecurityWorkspace,
  SettingsLayout,
  SubscriptionPanel
} from "@agentic-toolkit/account";
import { UsagePanel, SocialLinksPanel, AddressesPanel } from "@agentic-toolkit/profile";
import { TokensPanel } from "@agentic-toolkit/authentication";
import { AssistantsPanel } from "@agentic-toolkit/personas";
import { FeatureTitle, SettingsDirtyProvider } from "@agentic-toolkit/resource";
import { RecordApiButton } from "@agentic-toolkit/api-explorer";

// src/site/reservedSlugs.ts
var FAMILY_ROUTE_SEGMENTS = [
  "auth",
  // app/auth — the SSO callback
  "home",
  // app/home — the workspace-resolving redirect
  "details",
  // app/details/[topic] — the shared concept pages
  "privacy",
  "terms",
  "tour",
  // the landing deck's second route
  // Not a directory on any site: `marketingNextConfig` rewrites `/api/*` to the backend, so
  // the segment is spoken for on all 42 without appearing in any `app/` tree.
  "api",
  // Next serves these from FILES at the root of `app/`, so they occupy the same segment as a
  // slug even though no directory names them.
  "favicon.ico",
  "icon.svg",
  "apple-icon.png",
  "opengraph-image.png",
  "robots.txt",
  "sitemap.xml",
  // The framework's own namespace.
  "_next"
];
var SITE_ROUTE_SEGMENTS = [
  // billing — app/claim, the link a purchaser follows out of Stripe's receipt. One site's route,
  // reserved on all 42 for the reason at the top of this list: the mint form's question is not
  // "is this free HERE" but "is this free ANYWHERE".
  "claim",
  // community — app/{categories,discussions,forum,people,topics}. (`admin` is below.) `forum` is
  // the board: it was this site's `/home` until `/home` became the family's workspace redirect,
  // and it is the one segment the convergence itself minted.
  "categories",
  "discussions",
  "forum",
  "people",
  "topics",
  // consultants — app/consultant/[entry], the public profile of one directory entry. The site is
  // named in the plural and the route in the singular, so the reserved word is the one the URL
  // spends, not the one on the tin.
  "consultant",
  // cookbook — the corpus IS these nine words. Each is a real directory,
  // `app/(reader)/<section>/[[...slug]]`, so `/guidelines/testing/test-pyramid` is a document's
  // own address with nothing in front of it; the route group contributes no segment. They are
  // reserved because a static segment beats `[workspace]`, not because a redirect claims them —
  // there is no `/docs` prefix any more, and the entry in RESERVED_HANDLE_WORDS below is taste,
  // not this site. `projects` is cookbook's ninth section directory as well as the hub's
  // feature-page redirect, and is listed once, under the hub. This is the cost recorded in that
  // site's `.claude/rules/site-design.md` — adding a section to the book adds a reserved slug
  // for the whole family.
  "introduction",
  "principles",
  "guidelines",
  "ingredients",
  "recipes",
  "compliance",
  "reference",
  "appendix",
  // hub — app/{features,integrations,old-landing}, app/(auth)/{join,oidc}, app/(hub)/explore.
  // (`login`, `signup`, `contact`, `settings` and `user` are below.) `old-landing` is the
  // superseded hero page, still routable and deliberately kept so, which makes it a segment
  // like any other. `features` is where the eight marketing pages moved to when the root
  // segment became `[workspace]`, and it is a real directory: `app/features/[id]/`. The
  // integrations SITE routes `integrations` too — `app/integrations/oauth-callback`, where a
  // provider's OAuth redirect lands, at a path `oauthCallbackUrl()` builds from the window's own
  // origin and so cannot vary per site. Every site that mounts that feature grows the same
  // directory; the word is listed once.
  "features",
  "integrations",
  "join",
  "oidc",
  "explore",
  "old-landing",
  // hub — the marketing feature pages. These are not directories either: they were served
  // by `app/[slug]/page.tsx`, which dispatched on the slug ahead of a user profile, and the
  // root segment is `[workspace]` now — so each is a permanent REDIRECT source in the hub's
  // `next.config.ts` (`/<id>` → `/features/<id>`), derived from the same list the route's
  // generateStaticParams reads. A redirect answers before any route does, so the segment is
  // spoken for exactly as a directory's is, and these stay here rather than moving down to
  // RESERVED_HANDLE_WORDS: they are addressable URLs, not merely words a handle may not take.
  "agentic-personas",
  "persona-data-store",
  "user-data-store",
  "status-pages",
  "rest-api",
  "mcp",
  "applications",
  "projects",
  // personaregistry — `org` and `persona`, both REDIRECT sources in that site's `next.config.ts`
  // for the same reason the hub's eight above are: a redirect source claims its segment as
  // surely as a directory does. Neither is a directory there any more. `app/persona/[slug]`
  // existed only while the family's `[workspace]` sat at that site's root; `app/org/[slug]` was
  // older and outlived that window. Personas, users and organizations all address off the ROOT
  // now (`app/[slug]`) — an org is shown the way a user is, so it needs no prefix — and the old
  // prefixes stayed behind pointing at it. (`user` is the hub's public profile prefix, listed
  // above, and is a redirect source on this site too.)
  "org",
  "persona",
  // registries — app/registry/[registry] and app/registry/[registry]/[entry]: one owner-built
  // directory, and one entry within it. Singular for the same reason `consultant` is.
  "registry",
  // research — app/{papers,search}.
  "papers",
  "search",
  // toolkit — app/demo.
  "demo"
];
var GRAMMAR_SEGMENTS = [
  // organizations, teams, projects, ecosystems — `parse-path.ts`, the "all" landing.
  "all"
  // No parser spends this one today. `games/parse-path.ts` did — `/<workspace>/new` opened the
  // create-game dialog — and it went when the games rail became a list of products and a game
  // stopped being something you create directly (2026-08-22, `product-gaming-modes`).
  //
  // It stays reserved anyway, and deliberately: reserving a word is reversible and un-reserving
  // one is not. Delete this line and the very next customer may mint a workspace called `new`,
  // at which point no future grammar in any of the twelve features can ever spend the word
  // again — the obvious word for "the create screen", held by one account, fleet-wide, forever.
  // The word is still held back — it moved to RESERVED_HANDLE_WORDS, which is the list for a
  // refusal that is NOT shadowing. Keeping it here would have made this list say something false
  // about itself: every entry above is a segment some parser really compares against, and that
  // is the only claim this list makes.
];
var RESERVED_HANDLE_WORDS = [
  "about",
  "admin",
  "assets",
  "billing",
  "blog",
  "contact",
  "dashboard",
  "docs",
  "help",
  "legal",
  "login",
  "logout",
  "me",
  "monitoring",
  // Held on the same footing as the rest of this list, not because anything routes it.
  // `games/parse-path.ts` matched `/<workspace>/new` for the create-game dialog until
  // 2026-08-22 (`product-gaming-modes`), and when that grammar went the word came here rather
  // than being un-reserved: `new` is the obvious word for "the create screen", so letting one
  // account claim it fleet-wide, permanently, to buy back a name nobody has asked for is the
  // trade this list's own docstring declines to make. If a grammar spends the segment again,
  // it belongs back in GRAMMAR_SEGMENTS — and in the backend's RESERVED_ROUTE_SLUGS, which
  // dropped it because that list admits only words a live route or grammar earns.
  "new",
  "pricing",
  "profile",
  "public",
  "register",
  "session",
  "sessions",
  "settings",
  "signin",
  "signout",
  "signup",
  "static",
  "status",
  "support",
  "user",
  "users",
  // The hub's feature vocabulary. Every one of these is a SECOND segment — `/<workspace>/teams`,
  // `/<workspace>/tokens` — so none of them shadows a slug, and that is why they sit here rather
  // than in SITE_ROUTE_SEGMENTS. The hub refused them anyway, on the grounds that a profile slug
  // reading as one of its own feature words is a URL nobody can parse at a glance, and that
  // judgement is kept. The first group mirrors `FEATURES` in the hub's `data/feature-routes.ts`;
  // the rest are rail routes listed outside it, plus ONE retired segment — `ecosystems`, which
  // Products replaced: the ecosystems site maps to the `products` segment, so no hub route
  // spends the word. It is held back so a stale link resolves predictably instead of landing on
  // whichever user claimed the handle.
  //
  // `communities` was the second retired segment and is not one any more: when the fleet came
  // home, agenticdevelopercommunities.com's own workspace became `/<workspace>/communities`, so
  // the word is a live hub route again and is reserved on the ordinary grounds beside it.
  "all-data",
  "communities",
  "dashboards",
  "ecosystems",
  "email-signup",
  "feature-flags",
  "gamification",
  "invitations",
  "knowledgebases",
  "llm-providers",
  "members",
  "messaging",
  "narratives",
  "persona-services",
  "personas",
  "products",
  "registries",
  "research",
  "server-bags",
  "signin-apps",
  "storage",
  "teams",
  "tokens"
];
function reservedWorkspaceSlugs() {
  const all = [
    ...FAMILY_ROUTE_SEGMENTS,
    ...SITE_ROUTE_SEGMENTS,
    ...GRAMMAR_SEGMENTS,
    ...RESERVED_HANDLE_WORDS
  ];
  return new Set(all.map((s) => s.toLowerCase()));
}

// src/site/index.ts
import { isHubWorkspacePath, hubWorkspaceSlug } from "@agentic-toolkit/adh/site/hubWorkspacePath";

// src/settings/registry.tsx
import { siteUrl } from "@agentic-toolkit/adh-registry";

// src/settings/AppearancePanel.tsx
import dynamic from "next/dynamic";
import "react";
import "@agenticdevelopertoolkit/themes";
import { useAppearanceSettings } from "@agentic-toolkit/adh/auth";
import {
  ToggleGroup,
  ToggleGroupItem
} from "@agenticdevelopertoolkit/ui/components/toggle-group";
import { Checkbox } from "@agenticdevelopertoolkit/ui/components/checkbox";
import { Label } from "@agenticdevelopertoolkit/ui/components/label";
import { SettingRow } from "@agentic-toolkit/account";
import { jsx, jsxs } from "react/jsx-runtime";
var REDUCE_MOTION_OPTIONS = [
  { value: "auto", label: "Default" },
  { value: "on", label: "On" },
  { value: "off", label: "Off" }
];
var CONTRAST_OPTIONS = [
  { value: "default", label: "Default" },
  { value: "high", label: "High" },
  { value: "extra-high", label: "Extra High" }
];
var TEXT_SIZE_OPTIONS = [
  { value: "default", label: "Default" },
  { value: "small", label: "Small" },
  { value: "large", label: "Large" },
  { value: "extra-large", label: "Extra Large" }
];
var SPACING_OPTIONS = [
  { value: "compact", label: "Compact" },
  { value: "comfortable", label: "Comfortable" },
  { value: "spacious", label: "Spacious" }
];
function SegmentedRow({
  label,
  description,
  value,
  options,
  onChange,
  iconsOnly
}) {
  return /* @__PURE__ */ jsx(SettingRow, { label, description, children: /* @__PURE__ */ jsx(
    ToggleGroup,
    {
      "aria-label": label,
      value: [value],
      onValueChange: (next) => {
        const v = next[0];
        if (v) onChange(v);
      },
      children: options.map((o) => /* @__PURE__ */ jsxs(
        ToggleGroupItem,
        {
          value: o.value,
          "aria-label": iconsOnly ? o.label : void 0,
          title: iconsOnly ? o.label : void 0,
          children: [
            o.icon,
            !iconsOnly && o.label
          ]
        },
        o.value
      ))
    }
  ) });
}
function CheckboxRow({
  id,
  label,
  description,
  checked,
  onCheckedChange
}) {
  return /* @__PURE__ */ jsxs("div", { className: "flex items-start gap-3", children: [
    /* @__PURE__ */ jsx(Checkbox, { id, checked, onCheckedChange, className: "mt-0.5" }),
    /* @__PURE__ */ jsxs("div", { className: "min-w-0", children: [
      /* @__PURE__ */ jsx(Label, { htmlFor: id, className: "cursor-pointer", children: label }),
      description && /* @__PURE__ */ jsx("p", { className: "mt-0.5 text-xs text-apt-text-muted", children: description })
    ] })
  ] });
}
var ThemePickerRow = process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "local" || process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "testing" || process.env.NEXT_PUBLIC_DEPLOYMENT_ENV === "staging" ? dynamic(() => import("@agentic-toolkit/adh/settings/ThemePickerRow"), { ssr: false }) : () => null;
function AppearancePanel() {
  const { prefs, set } = useAppearanceSettings();
  return /* @__PURE__ */ jsx("div", { className: "min-h-0 flex-1 overflow-y-auto px-6 py-6", children: /* @__PURE__ */ jsxs("div", { className: "max-w-3xl space-y-7", children: [
    /* @__PURE__ */ jsx("p", { className: "text-sm text-apt-text-muted", children: "\u201CDefault\u201D follows your device\u2019s own setting where possible. These preferences are saved to your account, so they follow you to every site in the family." }),
    /* @__PURE__ */ jsx(ThemePickerRow, {}),
    /* @__PURE__ */ jsx(
      SegmentedRow,
      {
        label: "Reduce motion",
        description: "Minimise animations and transitions.",
        value: prefs.reduceMotion,
        options: REDUCE_MOTION_OPTIONS,
        onChange: (reduceMotion) => set({ reduceMotion })
      }
    ),
    /* @__PURE__ */ jsx(
      SegmentedRow,
      {
        label: "Contrast",
        description: "Strengthen text and border contrast.",
        value: prefs.contrast,
        options: CONTRAST_OPTIONS,
        onChange: (contrast) => set({ contrast })
      }
    ),
    /* @__PURE__ */ jsx(
      SegmentedRow,
      {
        label: "Text size",
        value: prefs.textSize,
        options: TEXT_SIZE_OPTIONS,
        onChange: (textSize) => set({ textSize })
      }
    ),
    /* @__PURE__ */ jsx(
      SegmentedRow,
      {
        label: "Spacing",
        description: "Density of layout spacing.",
        value: prefs.spacing,
        options: SPACING_OPTIONS,
        onChange: (spacing) => set({ spacing })
      }
    ),
    /* @__PURE__ */ jsxs("div", { className: "space-y-4 border-t border-apt-border pt-6", children: [
      /* @__PURE__ */ jsx(
        CheckboxRow,
        {
          id: "appearance-focus-outlines",
          label: "Always show focus outlines",
          description: "Show the focus ring even when navigating with a mouse.",
          checked: prefs.focusOutlines,
          onCheckedChange: (focusOutlines) => set({ focusOutlines })
        }
      ),
      /* @__PURE__ */ jsx(
        CheckboxRow,
        {
          id: "appearance-underline-links",
          label: "Always underline links",
          checked: prefs.underlineLinks,
          onCheckedChange: (underlineLinks) => set({ underlineLinks })
        }
      )
    ] })
  ] }) });
}

// src/settings/HubPreferencesPanel.tsx
import { useCallback, useEffect, useRef, useState } from "react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  chordFromEvent,
  formatChord,
  sameChord,
  useRegisteredShortcuts
} from "@agenticdevelopertoolkit/ui/hooks/useShortcut";
import { SettingRow as SettingRow2 } from "@agentic-toolkit/account";
import {
  DEFAULT_SITE_MENU_SHORTCUT,
  setSiteMenuShortcut,
  useHubPreferences
} from "@agentic-toolkit/adh/header/hub-preferences";
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
var SITE_MENU_LABEL = "Site menu";
function HubPreferencesPanel() {
  const { siteMenuShortcut } = useHubPreferences();
  const registered = useRegisteredShortcuts();
  const [recording, setRecording] = useState({ state: "idle" });
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const registeredRef = useRef(registered);
  registeredRef.current = registered;
  const save = useCallback((keys) => {
    setSiteMenuShortcut(keys);
    setRecording({ state: "idle" });
  }, []);
  useEffect(() => {
    if (recording.state !== "listening") return;
    const onKeyDown = (event) => {
      event.preventDefault();
      event.stopPropagation();
      if (event.key === "Escape") {
        setRecording({ state: "idle" });
        return;
      }
      const keys = chordFromEvent(event);
      if (keys === null) return;
      const clash = registeredRef.current.find(
        (s) => s.label !== SITE_MENU_LABEL && sameChord(s.keys, keys)
      );
      if (clash) {
        setRecording({ state: "conflict", keys, with: clash.label });
        return;
      }
      setSiteMenuShortcut(keys);
      setRecording({ state: "idle" });
    };
    document.addEventListener("keydown", onKeyDown, true);
    return () => document.removeEventListener("keydown", onKeyDown, true);
  }, [recording.state]);
  const isDefault = siteMenuShortcut === DEFAULT_SITE_MENU_SHORTCUT;
  const isOff = siteMenuShortcut === "";
  return /* @__PURE__ */ jsx2("div", { className: "min-h-0 flex-1 overflow-y-auto px-6 py-6", children: /* @__PURE__ */ jsxs2("div", { className: "max-w-3xl space-y-7", children: [
    /* @__PURE__ */ jsx2("p", { className: "text-sm text-apt-text-muted", children: "Preferences for the hub\u2019s own chrome. Unlike the rest of your settings, these are saved to this browser rather than to your account \u2014 a keyboard shortcut belongs to the keyboard in front of you." }),
    /* @__PURE__ */ jsx2(
      SettingRow2,
      {
        label: "Site menu shortcut",
        description: "Opens and closes the site menu from anywhere, including while you are typing.",
        children: /* @__PURE__ */ jsxs2("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsx2(
            "span",
            {
              className: "min-w-24 rounded-md border border-apt-border px-3 py-1.5 text-center font-mono text-sm text-apt-text",
              "aria-live": "polite",
              children: recording.state === "listening" ? "Press keys\u2026" : !mounted ? "\xA0" : isOff ? "Off" : formatChord(siteMenuShortcut)
            }
          ),
          recording.state === "listening" ? /* @__PURE__ */ jsx2(
            Button,
            {
              variant: "outline",
              size: "sm",
              onClick: () => setRecording({ state: "idle" }),
              children: "Cancel"
            }
          ) : /* @__PURE__ */ jsx2(
            Button,
            {
              variant: "outline",
              size: "sm",
              onClick: () => setRecording({ state: "listening" }),
              children: isOff ? "Set" : "Change"
            }
          ),
          /* @__PURE__ */ jsx2(
            Button,
            {
              variant: "ghost",
              size: "sm",
              disabled: isDefault,
              onClick: () => save(DEFAULT_SITE_MENU_SHORTCUT),
              children: "Reset"
            }
          ),
          /* @__PURE__ */ jsx2(Button, { variant: "ghost", size: "sm", disabled: isOff, onClick: () => save(""), children: "Turn off" })
        ] })
      }
    ),
    recording.state === "listening" && /* @__PURE__ */ jsx2("p", { className: "text-xs text-apt-text-muted", children: "Press the combination you want. Escape cancels; Escape and Tab cannot be bound." }),
    recording.state === "conflict" && /* @__PURE__ */ jsxs2("p", { className: "text-xs text-apt-red", role: "alert", children: [
      formatChord(recording.keys),
      " is already",
      " ",
      /* @__PURE__ */ jsx2("span", { className: "font-medium", children: recording.with }),
      ". Pick another combination."
    ] })
  ] }) });
}

// src/settings/registry.tsx
import {
  SETTINGS_TOPICS,
  resolveSettingsTopic
} from "@agentic-toolkit/adh/settings/topics";
import { jsx as jsx3, jsxs as jsxs3 } from "react/jsx-runtime";
var ICONS = {
  account: /* @__PURE__ */ jsx3(User, { size: 16, "aria-hidden": true }),
  security: /* @__PURE__ */ jsx3(Shield, { size: 16, "aria-hidden": true }),
  subscription: /* @__PURE__ */ jsx3(CreditCard, { size: 16, "aria-hidden": true }),
  usage: /* @__PURE__ */ jsx3(Gauge, { size: 16, "aria-hidden": true }),
  profile: /* @__PURE__ */ jsx3(Globe, { size: 16, "aria-hidden": true }),
  appearance: /* @__PURE__ */ jsx3(Palette, { size: 16, "aria-hidden": true }),
  social: /* @__PURE__ */ jsx3(Share2, { size: 16, "aria-hidden": true }),
  addresses: /* @__PURE__ */ jsx3(MapPin, { size: 16, "aria-hidden": true }),
  contacts: /* @__PURE__ */ jsx3(Mail, { size: 16, "aria-hidden": true }),
  notifications: /* @__PURE__ */ jsx3(Bell, { size: 16, "aria-hidden": true }),
  tokens: /* @__PURE__ */ jsx3(Key, { size: 16, "aria-hidden": true }),
  assistants: /* @__PURE__ */ jsx3(Bot, { size: 16, "aria-hidden": true }),
  archived: /* @__PURE__ */ jsx3(Archive, { size: 16, "aria-hidden": true }),
  preferences: /* @__PURE__ */ jsx3(Keyboard, { size: 16, "aria-hidden": true })
};
var HELP = {
  account: "Your sign-in email and password.",
  subscription: "Your plan and billing.",
  usage: "This period\u2019s calls, data, tokens and spend, per principal.",
  profile: "Your public display name and profile URL.",
  appearance: "Theme, motion, contrast, text size, and spacing.",
  social: "Links to your public profiles on other platforms.",
  addresses: "Physical addresses shown on your card.",
  contacts: "Emails and phone numbers shown on your card.",
  tokens: "Create and revoke personal API tokens.",
  assistants: "Control, per tool, what each assistant may do on your behalf.",
  archived: "Organizations you've archived. Restore one while its handle is still free.",
  preferences: "How the hub itself behaves on this browser, including its keyboard shortcut."
};
var PANELS = {
  account: /* @__PURE__ */ jsx3(AccountPanel, {}),
  security: /* @__PURE__ */ jsx3(SecurityWorkspace, {}),
  subscription: /* @__PURE__ */ jsx3(SubscriptionPanel, {}),
  usage: /* @__PURE__ */ jsx3(UsagePanel, {}),
  profile: /* @__PURE__ */ jsx3(
    ProfilePanel,
    {
      reservedSlugs: reservedWorkspaceSlugs(),
      profileUrlFor: (slug) => siteUrl("hub", `/${encodeURIComponent(slug)}`, window.location.hostname)
    }
  ),
  appearance: /* @__PURE__ */ jsx3(AppearancePanel, {}),
  social: /* @__PURE__ */ jsx3(SocialLinksPanel, {}),
  addresses: /* @__PURE__ */ jsx3(AddressesPanel, {}),
  contacts: /* @__PURE__ */ jsx3(ContactInfoPanel, {}),
  notifications: /* @__PURE__ */ jsx3(NotificationsWorkspace, {}),
  tokens: /* @__PURE__ */ jsx3(TokensPanel, {}),
  assistants: /* @__PURE__ */ jsx3(AssistantsPanel, {}),
  archived: /* @__PURE__ */ jsx3(ArchivedPanel, {}),
  preferences: /* @__PURE__ */ jsx3(HubPreferencesPanel, {})
};
var SELF_TITLED = /* @__PURE__ */ new Set([
  "notifications",
  "security"
]);
var API_PATHS = {
  account: "/auth/me",
  usage: "/usage/summary",
  profile: "/auth/me",
  social: "/content/social-links",
  addresses: "/content/addresses",
  contacts: "/account/contacts",
  tokens: "/auth/tokens",
  assistants: "/access/personas/user-actable",
  archived: "/workspaces/archived"
};
function buildSettingsTopics() {
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
      content: /* @__PURE__ */ jsxs3("div", { className: "flex min-h-0 min-w-0 flex-1 flex-col", children: [
        !SELF_TITLED.has(t.id) && /* @__PURE__ */ jsx3(
          FeatureTitle,
          {
            title: t.label,
            help: HELP[t.id],
            trailing: apiPath ? /* @__PURE__ */ jsx3(RecordApiButton, { path: apiPath, pathValues: {}, title: `${t.label} API` }) : void 0
          }
        ),
        PANELS[t.id]
      ] })
    };
  });
}
function SettingsTab({ activeTopic }) {
  return /* @__PURE__ */ jsx3(SettingsDirtyProvider, { children: /* @__PURE__ */ jsx3(
    SettingsLayout,
    {
      topics: buildSettingsTopics(),
      activeId: resolveSettingsTopic(activeTopic)
    }
  ) });
}

// src/settings/UserSettingsOverlay.tsx
import { DEFAULT_SETTINGS_TOPIC } from "@agentic-toolkit/adh/settings/topics";
import { jsx as jsx4, jsxs as jsxs4 } from "react/jsx-runtime";
function UserSettingsOverlay({
  open,
  onOpenChange
}) {
  return /* @__PURE__ */ jsx4(ToolkitQueryProvider, { children: /* @__PURE__ */ jsx4(SettingsDirtyProvider2, { children: /* @__PURE__ */ jsx4(UserSettingsDialog, { open, onOpenChange }) }) });
}
function UserSettingsDialog({
  open,
  onOpenChange
}) {
  const [topic, setTopic] = useState2(DEFAULT_SETTINGS_TOPIC);
  const [openedWith, setOpenedWith] = useState2(open);
  if (open !== openedWith) {
    setOpenedWith(open);
    if (open) setTopic(DEFAULT_SETTINGS_TOPIC);
  }
  const topics = buildSettingsTopics();
  const { isAnyDirty } = useSettingsDirty();
  const [pendingExit, setPendingExit] = useState2(null);
  function attemptExit(action) {
    if (isAnyDirty()) setPendingExit(() => action);
    else action();
  }
  function handleOpenChange(next) {
    if (next) {
      onOpenChange(true);
      return;
    }
    attemptExit(() => onOpenChange(false));
  }
  const compact = useMediaQuery("(max-width: 639px)");
  return /* @__PURE__ */ jsx4(Dialog, { open, onOpenChange: handleOpenChange, children: /* @__PURE__ */ jsxs4(
    DialogContent,
    {
      className: "flex flex-col gap-0 overflow-hidden p-0",
      style: compact ? {
        width: "100vw",
        maxWidth: "100vw",
        height: "100dvh",
        maxHeight: "100dvh",
        borderRadius: 0,
        borderWidth: 0,
        paddingTop: "env(safe-area-inset-top)",
        paddingBottom: "env(safe-area-inset-bottom)"
      } : {
        width: "min(72rem, calc(100vw - 2rem))",
        maxWidth: "min(72rem, calc(100vw - 2rem))",
        // Tall enough to show all subscription plans without scrolling on a
        // typical desktop; still caps to the viewport on shorter screens.
        height: "min(56rem, calc(100dvh - 2rem))",
        maxHeight: "calc(100dvh - 2rem)"
      },
      children: [
        /* @__PURE__ */ jsx4(DialogTitle, { className: "shrink-0 border-b border-apt-border px-6 py-3 font-mono text-sm tracking-wide text-apt-gold", children: "User Settings" }),
        /* @__PURE__ */ jsx4("div", { className: "flex min-h-0 flex-1 flex-col", children: /* @__PURE__ */ jsx4(
          SettingsLayout2,
          {
            topics,
            activeId: topic,
            onNavigate: (t) => {
              if (t.id === topic) return;
              attemptExit(() => setTopic(t.id));
            }
          }
        ) }),
        /* @__PURE__ */ jsx4(
          UnsavedChangesAlert,
          {
            open: pendingExit !== null,
            onDiscard: () => {
              pendingExit?.();
              setPendingExit(null);
            },
            onStay: () => setPendingExit(null)
          }
        )
      ]
    }
  ) });
}
export {
  SettingsTab,
  UserSettingsOverlay,
  buildSettingsTopics
};
//# sourceMappingURL=UserSettingsOverlay.js.map