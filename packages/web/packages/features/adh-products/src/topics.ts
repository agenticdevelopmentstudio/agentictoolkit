/** Sidebar topics inside a PRODUCT (the Products FTD — each product IS an ecosystem).
 * The LAST topic ("Settings", id "settings" for deep-link stability) is the
 * entity pane itself — it edits the product's own fields and holds the Danger (delete)
 * section (see FTD spec §4–§5). Creating products happens on the Products landing / the
 * selector popup's "New Product…" dialog (rendered above these).
 *
 * Storage and Users are GROUP topics: each renders a nested topic→detail sub-rail of its members
 * (defined in the toolkit's EcosystemsFeature), not a single pane — Storage = Buckets / Access /
 * All Data / Storage Access Tokens, Users (topic id "invitations", for deep-link stability) =
 * Users / Requests / Pending users / Invites / Email Signup. Gaming and Gamification are groups
 * too, host-owned (ProductsFeature). Applications is not a group: it is ONE list — the
 * applications, a divider, then Settings, the ecosystem's client auth (ApplicationsGroup). A part
 * that is a feature of its own in the catalog — Storage Access Tokens, Email Signup, Client Auth —
 * is one that COMES WITH its row's feature (`includedWith`): the Manage features dialog does not
 * list it, and holding the row's feature is holding it (Mike, 2026-09-29).
 *
 * `features` names the catalog feature behind each row, and every row but Settings MUST name
 * one — a feature the Manage features dialog lists, never one that comes with another: the
 * feature manager (`featureRowState` in @agentic-toolkit/data/ecosystems) draws a row only while
 * the product holds it, so every row drawn is a ticked row in the dialog, and a new product —
 * which holds nothing — shows Settings alone. A row with one feature is drawn with the catalog's
 * label for it, never a copy of its own.
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
  // Messaging and Dashboards stand on their catalog features like every other row. They were
  // drawn unconditionally (2026-09-25), which put both on every new product — one that holds
  // nothing must show nothing but Settings (Mike, 2026-09-29). Both are `comingSoon` in the
  // catalog today, so neither row shows until the catalog ships it and the owner adds it.
  { id: "messaging", label: "Messaging", dividerAfter: false, features: ["messaging"] },
  // Applications: the product's applications, then — behind a divider — Settings, the ecosystem's
  // client auth (sign-in, sign-up, OAuth providers, login registration), which each application
  // may override in its own detail. Client Auth was a row of its own, then a feature of its own;
  // it is neither now, it comes in with Applications (Mike, 2026-09-29). PRODUCT_TOPIC_ALIASES and
  // PRODUCT_MEMBER_MOVES send its old addresses here.
  { id: "applications", label: "Applications", dividerAfter: false, features: ["applications"] },
  { id: "dashboards", label: "Dashboards", dividerAfter: true, features: ["dashboards"] },
  // Users: the product's people — the roster and its requests/invites, and Email Signup's
  // waitlists, which come with Users. How they sign in and sign up is Users ▸ Authentication; the
  // Authentication group all of this sat in is gone (Mike, 2026-09-29).
  { id: "invitations", label: "Users", dividerAfter: false, features: ["users"] },
  // (Communities sat here, was removed for having no surface on any host, and came back below
  // with the rest of the hub's Products group — parked deliberately this time, because the
  // workspace rail offered it and moving that rail down whole is what dropping it would undo.)
  // Gaming and Gamification — two features, so two rows (Mike, 2026-09-29), each a host-owned
  // GROUP (see ProductsFeature's GamingGroup). Gamification is badges/levels/streaks engagement on
  // any product; Gaming is a full dedicated game (engine/content/connections/effects) built on it,
  // which is why adding Gaming adds Gamification. PRODUCT_MEMBER_MOVES sends the gamification
  // members' old addresses under Gaming to their new row.
  { id: "gaming", label: "Gaming", dividerAfter: false, features: ["gaming"] },
  { id: "gamification", label: "Gamification", dividerAfter: false, features: ["gamification"] },
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
  // the shared placeholder, so {@link PLACEHOLDER_TOPIC_IDS} answers all of them in-package rather
  // than making both hosts write the same "coming soon" for each. (Customers came down with them
  // and is gone: it stood on `users`, which is the Users row above — not a feature of its own.)
  { id: "communities", label: "Communities", dividerAfter: false, features: ["communities"] },
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
 * Old top-level topic ids → the host-owned group that holds that pane now. `signin-apps` (Client
 * Auth) was a top-level row before it was a group member; its sign-in clients are each
 * application's own login registration now, so it goes to Applications, whose ApplicationsGroup
 * sends the old member id on to the list. ResourceExplorer matches a URL's topic segment against
 * the top-level list — without this, `…/<product>/signin-apps` matches nothing and renders an
 * apparently empty product. (`auth`, the realm's sign-in settings, needs nothing here: it is
 * Users ▸ Authentication, an in-package member EcosystemsFeature already aliases.)
 */
export const PRODUCT_TOPIC_ALIASES: Record<string, string> = {
  "signin-apps": "applications",
};

/**
 * Members that moved out of a group (ResourceExplorer's `memberMoves`): old group → member → the
 * group that holds it now. The Authentication group is retired — its members went to Storage,
 * Users and Applications (EcosystemsFeature knows the first two; Applications is this package's).
 * Gamification's members left Gaming for a row of their own.
 */
export const PRODUCT_MEMBER_MOVES: Record<string, Record<string, string | null>> = {
  authentication: { "signin-apps": "applications" },
  gaming: { catalog: "gamification", levels: "gamification", "custom-events": "gamification" },
};

/**
 * The product topics whose pane this package does NOT own, so every host must render them
 * itself through {@link ProductsFeatureProps.renderFeaturePanel}.
 *
 * Exported as data rather than left implicit in a switch's fall-through because it is the whole
 * contract of that seam, and a host has no other way to know what it will be asked for. The
 * package's own test asserts it against PRODUCT_TOPICS, so a topic added above without a pane
 * here fails loudly instead of rendering blank.
 *
 * "all-data" and "email-signup" are not topics — they are GROUP members (of Storage and of Users),
 * reached through the same seam, which is why they are listed here with the two that are rows.
 */
export const HOST_RENDERED_TOPIC_IDS = [
  "dashboards",
  "billing",
  "all-data",
  // A member of the Users group, and the only one whose pane the two hosts cannot
  // share: the hub's EmailSignupPanel reads its own workspace context and lives in the hub app
  // (18 files, ~5.5k lines, over hub-local API clients), so it is not importable from here. The
  // seam is how the hub renders the real thing while the products site says where it is managed
  // instead of drawing a blank pane.
  "email-signup",
] as const;

/**
 * The topics whose surface does not exist yet — the ones that came down from the hub's workspace
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
  "devices",
  "domains",
  "education",
  "notifications",
  "sites",
  "stores",
] as const;
