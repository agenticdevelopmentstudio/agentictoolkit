'use client'

// Relative, and TYPE-ONLY — the one shape of self-import in this package that is safe
// to write relatively. `verbatimModuleSyntax: true` erases a whole-statement `import
// type` before tsup ever sees it, so neither statement below can be inlined and neither
// can fork module state; the preserved-import rule (package path + a matching `external`
// entry) has nothing to bite on. Two statements because the two types live in two
// sibling modules — NOT `from './index'`, which would make this file import its own
// package barrel and re-create the cycle the export contract exists to avoid.
import type { AdhHeaderAuthProps } from './AdhHeader'
import type { AvatarMenuUser } from './AvatarMenu'
// VALUE import, so the opposite rule applies and the full package path is load-bearing:
// this package builds `bundle: true, splitting: false`, and `@agentic-toolkit/auth` holds
// the token store, the refresh timer and the AuthContext at module scope. Inlined, this
// entry would carry a private, never-refreshed copy of the session — a visitor logged in
// through the site's own toolkit-auth import would read as signed out here, in production
// builds only (dev/vitest/tsc all resolve the `development` condition to src). The other
// half of the remedy is the matching `@agentic-toolkit/auth` entry in tsup's `external`.
import {
  useAuth,
  beginLogin,
  isAdmin,
  ssoSwitchUrl,
  currentReturnTo,
  type AuthUser,
} from '@agentic-toolkit/auth'
// The site table, for the post-login landing rule below. Same package specifier
// SiteHeader (this entry's sibling) already uses — `siteHomePath` is a pure lookup
// over a static table, so it carries no module state to fork.
import { siteHomePath, type SiteId } from '@agentic-toolkit/adh-registry'

/**
 * The resolved auth values the shared header needs — its only view of "who is
 * signed in and what do login / logout / cross-site switch do". An auth *source*
 * (see {@link HeaderAuthSource}) produces this; {@link SiteHeader} spreads it onto
 * the auth-agnostic `AdhHeader`.
 *
 * Derived from `AdhHeaderAuthProps` (the header's own auth slice) so it can't drift:
 * an auth prop added to the header flows into this type automatically. `user` is
 * widened to required — a source always decides signed-in-or-not. Every other field
 * stays optional: a source supplies *either* `onLogin` *or* `loginHref` (AdhHeader
 * uses the handler when present, else the href), never both.
 */
export type HeaderAuthState = Omit<AdhHeaderAuthProps, 'user'> & {
  user: AvatarMenuUser | null
}

/** Per-site config the default source consumes; forwarded from SiteHeader's props. */
export interface HeaderAuthSourceOptions {
  /** OAuth client id for the login redirect (default 'adh'). */
  clientId?: string
  /**
   * The site the header is rendered for — SiteHeader forwards its own `siteId`. A
   * session-aware source needs it to resolve the site's post-login landing
   * (`siteHomePath`), which is the Login/Sign-up return target the contract
   * prescribes from a site's root (docs/platform/login-and-return.md §2).
   */
  siteId?: SiteId
  /** Called after a successful logout — e.g. to navigate away from a gated page. */
  onAfterLogout?: () => void
}

/**
 * An injectable auth source: a React hook returning {@link HeaderAuthState}. It is
 * a hook (may call `useAuth`/`useRouter`/`useState`) and SiteHeader invokes it
 * unconditionally, once, at the top of its body — so it must obey the rules of
 * hooks and be a stable, module-level function (not redefined inline per render).
 */
export type HeaderAuthSource = (opts: HeaderAuthSourceOptions) => HeaderAuthState

/**
 * Map a backend auth user onto the header's avatar shape — the single home for the
 * `name || label || email-local-part || fallback` rule, so every source maps
 * identically. `fallback` lets admin show 'Admin' rather than 'User'. The email
 * local-part avoids leaking the full address, which the menu no longer prints at
 * all: the address itself is not carried onto the avatar shape, so no header
 * surface can grow a display of it without coming back through here.
 *
 * `name` is the PERSON'S NAME and nothing else — it is what the menu greets, so a
 * source that only has a handle must pass it as `label` instead. That split is the
 * whole point of the second field: hub used to resolve `displayName || slug` and
 * hand the result in as `name`, which greeted a signed-in visitor by their slug
 * ("mikefullerton") while their actual name sat unread in `AuthUser.name`.
 */
export function toAvatarUser(
  u: Pick<AuthUser, 'email' | 'avatarUrl'> & {
    /** The person's own name (`AuthUser.name`, or a profile override). */
    name?: string | null
    /** The handle to fall back to when there is no name — hub passes the slug. */
    label?: string | null
    /** The account's handle, carried through for the Profile row's href. Distinct from `label`,
     *  which is a DISPLAY fallback and is absent whenever a real name exists — an account with a
     *  name still has a profile. */
    slug?: string | null
  },
  fallback = 'User',
): AvatarMenuUser {
  const fullName = u.name?.trim() || undefined
  return {
    name: fullName || u.label?.trim() || u.email?.split('@')[0] || fallback,
    fullName,
    slug: u.slug?.trim() || undefined,
    imageUrl: u.avatarUrl || undefined,
  }
}

/** The signed-in resolver itself, hoisted to module scope rather than written inline
 *  below, because its IDENTITY is a dependency: {@link ssoSwitchResolver} is called
 *  from inside a hook on every render, and the site menu memoizes every row's
 *  resolved href on the function it gets back — a fresh closure per render would
 *  re-run env detection and URL parsing across the whole tree each time. It closes
 *  over nothing, so one instance is all there ever needs to be. */
const SSO_SWITCH = (href: string): string => ssoSwitchUrl(href)

/**
 * The cross-site switch resolver every adh-SSO source uses. Signed in: route a site
 * switch through a silent SSO redirect so the target lands ALREADY logged in (its
 * AuthProvider exchanges the bounced #code in place) — no logged-out flash, no full
 * reload. Signed out: `undefined`, so the switcher uses the href as-is. The switch
 * always uses the shared cross-site 'adh' client (`ssoSwitchUrl`'s default), NOT a
 * site's own login client — only the 'adh' client's return-origin allow-list spans
 * every sibling site. One home for the rule, shared by every SSO source.
 *
 * Both results are stable references (see {@link SSO_SWITCH}), so a caller may pass
 * this straight into a memo dependency list.
 */
export function ssoSwitchResolver(
  signedIn: boolean,
): ((defaultHref: string) => string) | undefined {
  return signedIn ? SSO_SWITCH : undefined
}

/**
 * The anonymous header auth source — the SiteHeader default, for sites whose
 * header is not session-aware (e.g. status, which mounts no adh AuthProvider).
 * It never reads the session: the bar is a fixed logged-out state (Login +
 * Sign up). The marketing/feature-site family no longer uses it — those sites
 * are session-aware via {@link makeSmartHeaderAuth} (see MarketingSiteHeader
 * and docs/platform/feature-sites-redesign.md).
 *
 * It supplies neither `onLogin`/`onSignup` nor `loginHref`/`signupHref`, so
 * AdhHeader falls back to the hub's `/login` and `/signup` ({@link resolveHubHref}).
 * Those hub pages send an already-authenticated visitor straight on to `/home`,
 * which gives the desired behaviour: click Login/Sign up → hub `/home` when signed
 * in, else the hub login/signup page. Auth lives entirely on the hub.
 *
 * A "smart" site that wants session-aware login/returnTo passes its own source to
 * SiteHeader instead — see docs/platform/auth-realms-and-header-modes.md.
 *
 * A plain hook (no inner hook calls) so a site with no adh AuthProvider can mount
 * the shared header without one.
 */
export function useAnonymousHeaderAuth(_opts: HeaderAuthSourceOptions): HeaderAuthState {
  return { user: null, authLoading: false }
}

/** Config for {@link makeSmartHeaderAuth} — a per-site auth realm slice. */
export interface SmartHeaderAuthConfig {
  /**
   * OAuth client id for the SSO login / logout / switch (default `'adh'`, the
   * central developer realm). This is the realm seam: a **vended** ecosystem's
   * sites pass their own client here, and — once the AS honours the client's
   * ecosystem (see docs/platform/auth-realms-and-header-modes.md) — the very same source
   * authenticates that ecosystem's pool with no other change.
   */
  clientId?: string
  /**
   * Where login / sign up return to after the SSO round-trip. A FUNCTION, read at
   * click time so it reflects the page the user is actually on — not wherever the
   * source was built. An explicit return always wins
   * (docs/platform/login-and-return.md §2); omit it to get {@link defaultReturnTo}.
   */
  returnTo?: () => string
  /** Avatar-name fallback when the user has neither a name nor email (default 'User'). */
  avatarFallback?: string
}


/**
 * The default post-login destination for a satellite's header Login / Sign up —
 * the SHARED rule, so no site has to patch it locally.
 *
 * From the site's ROOT it is that site's own post-login landing (`/home` when the
 * site declares one, else `/`): the home-or-root return target of
 * docs/platform/login-and-return.md §2, and the fix for the classic "signed in from
 * the landing, stranded back on the anonymous landing" walk. From ANY OTHER page it
 * is the page the visitor is standing on, so a profile-driven funnel keeps its place
 * ("sign in, come back to *this* persona") — the bespoke case the same section
 * carves out.
 *
 * Read at CLICK time (inside the handler), so `/home` hangs off the click and
 * nothing else: an already-signed-in visitor who arrives at `/` on their own is
 * never redirected. With no `siteId` (a source built outside SiteHeader) it degrades
 * to the current address rather than guessing a landing.
 *
 * That address is `currentReturnTo()` — auth's, the SAME one the SSO bounce and the
 * integrations connect round-trip come back to — and NOT a local `pathname + search`,
 * which is what this read used to be. The two differ by the hash, and the hash is not
 * decoration on a console: it is the only record that a surface shown in a DIALOG was
 * open. Dropping it sent a visitor who clicked Login from inside Connections back to a
 * page with the dialog closed and nothing saying the login had worked. Its `undefined`
 * off the browser is this function's SSR guard, and `'/'` is the site root a header
 * rendered on the server can honestly name.
 */
export function defaultReturnTo(siteId?: SiteId): string {
  const here = currentReturnTo()
  if (here === undefined || !siteId) return here ?? '/'
  return window.location.pathname === '/' ? siteHomePath(siteId) : here
}

/**
 * Build a **smart** header auth source for an SSO *satellite* — a public brand
 * site that has NO local login page and authenticates through the central AS.
 * This is the third header shape, distinct from the two built-in sources:
 *  - {@link useAnonymousHeaderAuth} (dumb marketing bar, never reads the session);
 *  - the hub / admin sources (session-aware, but with their OWN local `/login`
 *    pages and auth contexts) — see each site's `header-for-*.tsx`.
 *
 * A satellite has neither: it reads the shared adh session (`useAuth`, so the
 * site must be inside an `AuthProvider`) and runs BOTH Login and Sign up through
 * `beginLogin({ clientId, returnTo })`, so the visitor lands back on the page they
 * started from, recognised. Logout defers to the context's `logout()` (which ends
 * the central SSO session + re-arms the cold-load check).
 *
 * This is the reusable shape a **vended** ecosystem's sites reuse — same source,
 * a different `clientId` (see docs/platform/auth-realms-and-header-modes.md). Call it ONCE
 * at module scope and pass the returned hook to `<SiteHeader useAuthSource>`; the
 * result is a hook (it calls `useAuth`), so it must be a stable reference across
 * renders — never rebuild it inline per render.
 */
export function makeSmartHeaderAuth(cfg: SmartHeaderAuthConfig = {}): HeaderAuthSource {
  const { clientId = 'adh', returnTo, avatarFallback = 'User' } = cfg
  return function useSmartHeaderAuth(opts: HeaderAuthSourceOptions): HeaderAuthState {
    const { user, logout, isLoading } = useAuth()
    // Login AND Sign up start the same SSO round-trip, returning to the resolved
    // destination — the central login UI is where an account is created or entered.
    // A config `returnTo` wins; otherwise the shared home-or-root rule, which needs
    // the siteId SiteHeader forwards.
    const login = (): void =>
      beginLogin({ clientId, returnTo: returnTo?.() ?? defaultReturnTo(opts.siteId) })
    return {
      user: user ? toAvatarUser(user, avatarFallback) : null,
      // Unlocks Debug Options (the avatar menu's last row) in every env for a
      // signed-in adh admin — see AdhHeaderAuthProps — and appends the admin
      // consoles to the site menu, or on the hub to the workspace menu. Those are
      // the only two things it does; every other row of those menus is the same for
      // everyone.
      userIsAdmin: isAdmin(user),
      // Spinner while the session resolves, not a flash of the signed-out buttons.
      authLoading: isLoading,
      resolveSwitchHref: ssoSwitchResolver(user != null),
      onLogin: login,
      onSignup: login,
      // context.logout already runs ssoLogout({ clientId }) + clearSsoChecked.
      onLogout: () => {
        void logout()
      },
    }
  }
}
