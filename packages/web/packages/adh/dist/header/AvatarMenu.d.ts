export type AvatarMenuUser = {
    /** What this account is CALLED — the personal name when one is known, else the
     *  handle a source falls back to (hub's slug, the email local-part, 'User'; see
     *  `toAvatarUser`). Never empty by contract, which is why the trigger can use it
     *  as its accessible name and the avatar can derive initials from it. */
    name: string;
    /** The person's own name, when the backend actually holds one. Present ⇒ the menu
     *  GREETS by its first word; absent ⇒ it prints `name` plainly.
     *
     *  Two fields rather than one because a handle is not a name, and only the source
     *  knows which it handed over: greeting "Welcome mikefullerton!" is worse than
     *  printing the handle. `name` still equals this whenever a name exists, so no
     *  caller has to choose between them for a11y or initials. */
    fullName?: string;
    /** The account's handle. Data only — it does NOT gate the Profile row (see
     *  `AvatarMenuProps.profileHref`); a caller that has resolved a slug but knows this
     *  site carries no `/<slug>/profile` route must still withhold `profileHref`. */
    slug?: string;
    imageUrl?: string;
};
export type AvatarMenuProps = {
    user: AvatarMenuUser;
    /** Where "Home" points. The site's own post-login landing, supplied by the
     *  registry-aware wrapper; defaults to the site root. */
    homeHref?: string;
    /** Where the Profile row points, and whether it renders at all — present ⇒ the row
     *  offers it, absent ⇒ the row is omitted. This component resolves no site ids and
     *  holds no route map (same reason `homeHref` arrives pre-built rather than being
     *  derived from a slug here): the `/<slug>/profile` route this row links to does not
     *  exist on every site the shared header renders on, so the registry-aware wrapper
     *  decides, from the account's slug AND the current site's own route map, whether
     *  there is anywhere to send this row — and hands in the finished href only when
     *  both hold. */
    profileHref?: string;
    onLogout?: () => void;
    settingsHref?: string;
    onSettings?: () => void;
    /** Opens the Debug console. Present ⇒ the menu ends with a divider and a "Debug
     *  Options" row; absent ⇒ no row. The caller owns the gate (dev build, or an adh
     *  admin) and the console — this component only offers the door. */
    onDebugOptions?: () => void;
    /** Secondary text on the Debug row ("Sim: prod"). Shown, but kept out of the row's
     *  NAME — it is the row's accessible description instead — so the name is stably
     *  "Debug Options" whether or not production is being simulated. */
    debugOptionsHint?: string;
};
/**
 * The signed-in account menu: the avatar in the bar, and under it the user's name
 * plus the account destinations — Home, Profile, User Settings, Log out — and, for a
 * developer or an adh admin only, Debug Options, last and behind its own divider.
 *
 * It is an ACCOUNT menu, not a nav menu. A site's own destinations live in the bar
 * and in the site-name menu (the brand dropdown); routing them through here as well
 * grew this popup to the length of the site's whole feature list.
 *
 * **This menu is CLOSED at SIX rows. Add nothing further** — no seventh row, no slot,
 * no prop that lets a host inject one. Not a workspace picker, not a theme toggle,
 * not a docs link, not a site-specific action. Everything proposed for here already
 * has a home: `AdhHeader`'s bar slots (`navLinks`, `trailingNavLinks`, `preAuthLinks`,
 * `leadingActions`) or `SiteMenu`, which is also where the bar's links go below
 * 768px. The rows are what was LEFT after this popup had absorbed the hub's whole
 * feature list and had to be emptied again; there is no threshold at which one more
 * is harmless, which is why the rule is a count and not a taste. Profile, and then
 * Debug Options (moved here from a bug-glyph dropdown of its own in the bar), were added
 * by the repo owner's explicit instruction — which is the only way the count moves.
 * (Repo rule: `.claude/skills/project-guidelines/topics/ui-development.md`.)
 */
export declare function AvatarMenu({ user, homeHref, profileHref, onLogout, settingsHref, onSettings, onDebugOptions, debugOptionsHint, }: AvatarMenuProps): import("react").JSX.Element;
//# sourceMappingURL=AvatarMenu.d.ts.map