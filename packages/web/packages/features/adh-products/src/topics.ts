/** Sidebar topics inside a PRODUCT (the Products FTD — each product IS an ecosystem).
 * The LAST topic ("Settings", id "settings" for deep-link stability) is the
 * entity pane itself — it edits the product's own fields and holds the Danger (delete)
 * section (see FTD spec §4–§5). Creating products happens on the Products landing / the
 * selector popup's "New Product…" dialog (rendered above these).
 *
 * Storage / Users / Authentication are GROUP topics: each renders a nested topic→detail
 * sub-rail of its members (defined in the toolkit's EcosystemsFeature), not a single pane —
 * Storage = Buckets / Access / All Data, Users (topic id "invitations", for deep-link
 * stability) = Users / Requests / Pending users / Invites, Authentication = User Auth /
 * Sign-in apps / Storage Access Tokens / Email Signup.
 *
 * `features` names the catalog feature(s) behind each row: the rail draws a row only while the
 * product holds one of them, so the list and its Manage features dialog always agree. "Users" and
 * "Customers" both answer to `users` — the catalog's own copy says they are the same thing.
 *
 * These rows are all scoped to the OPEN PRODUCT's ecosystem. Several of them name a surface
 * that ALSO exists at workspace level, scoped to the workspace's default ecosystem instead —
 * Storage on agenticdeveloperstorage.com, Integrations on agenticdeveloperintegrations.com,
 * Tokens on the hub's own rail. Same pane, different scope; the split is deliberate and this
 * list is not the place to reconcile it.
 *
 * A plain data module, and its own package entry (`@agentic-toolkit/adh-products/topics`), so a
 * Server Component that only needs an id or a label does not drag the feature onto the client.
 *
 * It lives here rather than in the hub because BOTH hosts of the Products feature render it, and
 * a copy per host is two rails that nothing makes agree. */
export const PRODUCT_TOPICS = [
  // No "features" row: this list IS the product's features (EcosystemsFeature heads it
  // "Features"), and adding or removing them is the list's own title-row tool menu.
  { id: "storage", label: "Storage", dividerAfter: false, features: ["storage"] },
  { id: "integrations", label: "Integrations", dividerAfter: false, features: ["integrations"] },
  // Messaging: send email/SMS to this product's customers via its OWN connected
  // Postmark/Twilio integration (the promoted admin Messaging tool). Always shown; each
  // channel is disabled until its provider is connected on Integrations.
  { id: "messaging", label: "Messaging", dividerAfter: false, features: ["messaging"] },
  { id: "applications", label: "Applications", dividerAfter: false, features: ["applications"] },
  { id: "dashboards", label: "Dashboards", dividerAfter: true, features: ["dashboards"] },
  { id: "invitations", label: "Users", dividerAfter: false, features: ["users"] },
  // Everything about HOW someone gets in, as one GROUP rather than four rows spread down the
  // rail: the product's own auth policy (User Auth), the sign-in clients it vends
  // (oauth.clients — the apps a developer registers so their site can sign its own customers in
  // via GitHub-through-ADH), the storage tokens its machines authenticate with, and the waitlist
  // people join before any of it applies (Email Signup). They were `auth`, `signin-apps` and
  // `tokens` as top-level rows. The ids are unchanged, and the OLD ADDRESSES redirect: keeping an
  // id is only half of it, because ResourceExplorer matches the URL's topic segment against THIS
  // top-level list, so `…/<product>/tokens` would match nothing and render "Select a topic to
  // view." — an apparently empty product, no 404, nothing in the console. EcosystemsFeature's
  // `GROUP_MEMBER_GROUP` (derived from `groupMembers`) is what closes it, via the explorer's
  // `topicAliases`. Members themselves live in EcosystemsFeature's `groupMembers`.
  {
    id: "authentication",
    label: "Authentication",
    dividerAfter: false,
    features: ["user-authentication", "signin-apps", "storage-access-tokens", "email-signup"],
  },
  // (Communities sat here, was removed for having no surface on any host, and came back below
  // with the rest of the hub's Products group — parked deliberately this time, because the
  // workspace rail offered it and moving that rail down whole is what dropping it would undo.)
  // The product's gaming shape — a host-owned GROUP (see ProductsFeature's
  // productTopicPaneRenderer) whose member list depends on the realm's mode ('none' /
  // 'gamification' / 'game'): badges/levels/streaks engagement on a regular product, or a
  // full dedicated game (engine/content/connections/effects) with gamification tuned for it.
  { id: "gaming", label: "Gaming", dividerAfter: false, features: ["gaming", "gamification"] },
  // Per-product feature flags + server bags — named on/off toggles and arbitrary
  // key → JSON config values this product's apps / backend read at runtime.
  { id: "feature-flags", label: "Feature flags", dividerAfter: false, features: ["feature-flags"] },
  { id: "server-bags", label: "Server bags", dividerAfter: false, features: ["server-bags"] },
  { id: "billing", label: "Billing", dividerAfter: false, features: ["billing"] },
  // ── The rows that came DOWN from the hub's workspace rail (2026-08-24) ──────────────────────
  // Each one is a surface OF a product — a product has customers, devices, domains, a store;
  // a workspace does not — so the hub stopped offering them workspace-wide and they are topics
  // here, applied to the product the rail's parent level picked. They arrive together and they
  // arrive without panes: every one is a fleet site whose own workspace implementation is still
  // the shared placeholder, so {@link PLACEHOLDER_TOPIC_IDS} answers all eight in-package rather
  // than making both hosts write the same "coming soon" eight times.
  { id: "communities", label: "Communities", dividerAfter: false, features: ["communities"] },
  { id: "customers", label: "Customers", dividerAfter: false, features: ["users"] },
  { id: "devices", label: "Devices", dividerAfter: false, features: ["devices"] },
  { id: "domains", label: "Domains", dividerAfter: false, features: ["domains"] },
  { id: "education", label: "Education", dividerAfter: false, features: ["education"] },
  { id: "notifications", label: "Notifications", dividerAfter: false, features: ["notifications"] },
  { id: "sites", label: "Sites", dividerAfter: false, features: ["sites"] },
  { id: "stores", label: "Stores", dividerAfter: true, features: ["stores"] },
  // The product's own entity/settings pane (name/slug/description + Danger). Last in the
  // rail; selected by id === "settings" in the toolkit's EcosystemsFeature.
  { id: "settings", label: "Settings", dividerAfter: false },
] as const;

export type ProductTopicId = (typeof PRODUCT_TOPICS)[number]["id"];

/**
 * The product topics whose pane this package does NOT own, so every host must render them
 * itself through {@link ProductsFeatureProps.renderFeaturePanel}.
 *
 * Exported as data rather than left implicit in a switch's fall-through because it is the whole
 * contract of that seam, and a host has no other way to know what it will be asked for. The
 * package's own test asserts it against PRODUCT_TOPICS, so a topic added above without a pane
 * here fails loudly instead of rendering blank.
 *
 * "all-data" and "email-signup" are not topics — they are GROUP members (Storage's third,
 * Authentication's fourth), reached through the same seam, which is why they are listed here
 * with the two that are rows.
 */
export const HOST_RENDERED_TOPIC_IDS = [
  "dashboards",
  "billing",
  "all-data",
  // The Authentication group's fourth member, and the only one whose pane the two hosts cannot
  // share: the hub's EmailSignupPanel reads its own workspace context and lives in the hub app
  // (18 files, ~5.5k lines, over hub-local API clients), so it is not importable from here. The
  // seam is how the hub renders the real thing while the products site says where it is managed
  // instead of drawing a blank pane.
  "email-signup",
] as const;

/**
 * The topics whose surface does not exist yet — the eight that came down from the hub's workspace
 * rail with the shared site placeholder behind them. The package renders one "coming soon" pane
 * for all of them (see ProductsFeature's productTopicPaneRenderer), which is why they are NOT in
 * {@link HOST_RENDERED_TOPIC_IDS}: neither host owns a pane, so asking both for one would be two
 * copies of the same nothing.
 *
 * A topic leaves this list the day it gains a real pane — either in-package, or by moving to
 * HOST_RENDERED_TOPIC_IDS if the two hosts answer it differently. The package's own test asserts
 * every id here is a PRODUCT_TOPICS id and that the two lists are disjoint.
 */
export const PLACEHOLDER_TOPIC_IDS = [
  "communities",
  "customers",
  "devices",
  "domains",
  "education",
  "notifications",
  "sites",
  "stores",
] as const;
