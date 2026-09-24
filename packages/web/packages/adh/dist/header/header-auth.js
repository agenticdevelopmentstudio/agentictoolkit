'use client'

"use client";

// src/header/header-auth.ts
import {
  useAuth,
  beginLogin,
  isAdmin,
  ssoSwitchUrl,
  currentReturnTo
} from "@agentic-toolkit/auth";
import { siteHomePath } from "@agentic-toolkit/adh-registry";
function toAvatarUser(u, fallback = "User") {
  const fullName = u.name?.trim() || void 0;
  return {
    name: fullName || u.label?.trim() || u.email?.split("@")[0] || fallback,
    fullName,
    slug: u.slug?.trim() || void 0,
    imageUrl: u.avatarUrl || void 0
  };
}
var SSO_SWITCH = (href) => ssoSwitchUrl(href);
function ssoSwitchResolver(signedIn) {
  return signedIn ? SSO_SWITCH : void 0;
}
function useAnonymousHeaderAuth(_opts) {
  return { user: null, authLoading: false };
}
function defaultReturnTo(siteId) {
  const here = currentReturnTo();
  if (here === void 0 || !siteId) return here ?? "/";
  return window.location.pathname === "/" ? siteHomePath(siteId) : here;
}
function makeSmartHeaderAuth(cfg = {}) {
  const { clientId = "adh", returnTo, avatarFallback = "User" } = cfg;
  return function useSmartHeaderAuth(opts) {
    const { user, logout, isLoading } = useAuth();
    const login = () => beginLogin({ clientId, returnTo: returnTo?.() ?? defaultReturnTo(opts.siteId) });
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
        void logout();
      }
    };
  };
}
export {
  defaultReturnTo,
  makeSmartHeaderAuth,
  ssoSwitchResolver,
  toAvatarUser,
  useAnonymousHeaderAuth
};
//# sourceMappingURL=header-auth.js.map