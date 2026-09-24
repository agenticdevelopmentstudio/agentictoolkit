'use client'
"use client";

// src/profile/ProfileView.tsx
import { siteUrl, siteProdUrl } from "@agentic-toolkit/adh-registry";
import { UserCard, UserCardSkeleton } from "@agenticdevelopertoolkit/ui/blocks/user-card";

// src/header/useClientHost.ts
import { useEffect, useState } from "react";
function useClientHost() {
  const [host, setHost] = useState(null);
  useEffect(() => setHost(window.location.host), []);
  return host;
}

// src/profile/frame.ts
var PROFILE_FRAME_CLASS = "mx-auto max-w-2xl px-4 py-16 sm:px-6";

// src/profile/useViewerPrincipal.ts
import { useEffect as useEffect2, useState as useState2 } from "react";
import { useOptionalAuth } from "@agentic-toolkit/auth";
import { authedJson } from "@agentic-toolkit/auth/client";

// src/profile/normalize.ts
function principalFromUserCard(body) {
  return { ...body, kind: "user" };
}
function principalFromOrgCard(body) {
  return {
    slug: body.slug,
    displayName: body.displayName,
    createdAt: body.createdAt,
    description: body.description,
    personas: body.personas,
    avatarUrl: null,
    socialLinks: [],
    emails: [],
    phones: [],
    addresses: [],
    kind: "organization"
  };
}

// src/profile/useViewerPrincipal.ts
function useViewerPrincipal(slug, seed, enabled = true) {
  const auth = useOptionalAuth();
  const signedIn = auth?.isAuthenticated ?? false;
  const [wider, setWider] = useState2(null);
  const [pending, setPending] = useState2(false);
  useEffect2(() => {
    if (!enabled || !signedIn) {
      setWider(null);
      setPending(false);
      return;
    }
    let live = true;
    setWider(null);
    setPending(true);
    void (async () => {
      const encoded = encodeURIComponent(slug);
      try {
        const dto = await authedJson(`/api/users/${encoded}`);
        if (live) {
          setWider(principalFromUserCard(dto));
          setPending(false);
        }
        return;
      } catch (err) {
        if (err.status !== 404) {
          console.error(`Profile upgrade failed for ${slug}:`, err);
          if (live) setPending(false);
          return;
        }
      }
      try {
        const dto = await authedJson(`/api/orgs/${encoded}`);
        if (live) {
          setWider(principalFromOrgCard(dto));
          setPending(false);
        }
      } catch (err) {
        if (err.status !== 404) {
          console.error(`Profile upgrade failed for ${slug}:`, err);
        }
        if (live) setPending(false);
      }
    })();
    return () => {
      live = false;
    };
  }, [slug, signedIn, enabled]);
  return { principal: wider ?? seed, pending };
}

// src/profile/ProfileView.tsx
import { jsx, jsxs } from "react/jsx-runtime";
function ProfileView({
  principal,
  siteId,
  children,
  upgrade = true
}) {
  const { principal: shown0 } = useViewerPrincipal(principal.slug, principal, upgrade);
  const shown = shown0 ?? principal;
  const hostname = useClientHost();
  const fullProfileHref = siteId === "hub" ? null : hostname ? siteUrl("hub", `/${encodeURIComponent(shown.slug)}/profile`, hostname) : siteProdUrl("hub", `/${encodeURIComponent(shown.slug)}/profile`);
  return /* @__PURE__ */ jsxs("main", { className: PROFILE_FRAME_CLASS, children: [
    /* @__PURE__ */ jsx(UserCard, { user: shown }),
    shown.description && /* @__PURE__ */ jsx("p", { className: "mt-4 text-apt-text-muted", children: shown.description }),
    children,
    fullProfileHref && /* @__PURE__ */ jsx("div", { className: "mt-8 text-center", children: /* @__PURE__ */ jsx(
      "a",
      {
        href: fullProfileHref,
        className: "text-sm text-apt-text-muted underline underline-offset-4 hover:text-apt-text",
        children: "Full Profile"
      }
    ) })
  ] });
}
function ProfileSkeleton() {
  return /* @__PURE__ */ jsx("main", { className: PROFILE_FRAME_CLASS, children: /* @__PURE__ */ jsx(UserCardSkeleton, {}) });
}

// src/profile/ProfileNotFound.tsx
import { useState as useState3, useCallback, useRef } from "react";
import Link from "next/link";
import { Search } from "lucide-react";
import { Avatar, AvatarImage, AvatarFallback } from "@agenticdevelopertoolkit/ui/components/avatar";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
function initials(name) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? "").join("");
}
function ProfileNotFound() {
  const [query, setQuery] = useState3("");
  const [search, setSearch] = useState3({ status: "idle" });
  const abortRef = useRef(null);
  const handleSearch = useCallback(async (q) => {
    const trimmed = q.trim();
    if (!trimmed) return;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setSearch({ status: "loading" });
    try {
      const res = await fetch(
        `/api/public/users/search?q=${encodeURIComponent(trimmed)}`,
        { signal: controller.signal }
      );
      if (!res.ok) throw new Error(`Search failed (${res.status})`);
      const hits = await res.json();
      setSearch({ status: "success", hits });
    } catch (err) {
      if (err instanceof DOMException && err.name === "AbortError") return;
      setSearch({
        status: "error",
        message: err instanceof Error ? err.message : "Search failed. Try again."
      });
    }
  }, []);
  const onSubmit = (e) => {
    e.preventDefault();
    void handleSearch(query);
  };
  return /* @__PURE__ */ jsx2("main", { className: PROFILE_FRAME_CLASS, children: /* @__PURE__ */ jsxs2("div", { className: "rounded-xl border border-apt-border bg-apt-bg p-8", children: [
    /* @__PURE__ */ jsx2("h1", { className: "font-serif text-2xl font-medium text-apt-text sm:text-3xl", children: "Profile not found" }),
    /* @__PURE__ */ jsx2("p", { className: "mt-3 text-apt-text-muted", children: "This profile doesn't exist, or its owner has chosen not to show it to you." }),
    /* @__PURE__ */ jsxs2("div", { className: "mt-8", children: [
      /* @__PURE__ */ jsx2(
        "div",
        {
          className: "mb-3 font-mono text-[0.6rem] uppercase tracking-[0.1em] text-apt-text-dim",
          id: "profile-search-label",
          children: "Search for someone else"
        }
      ),
      /* @__PURE__ */ jsx2(
        "form",
        {
          onSubmit,
          role: "search",
          "aria-labelledby": "profile-search-label",
          children: /* @__PURE__ */ jsxs2("div", { className: "flex gap-2", children: [
            /* @__PURE__ */ jsx2("label", { htmlFor: "profile-search", className: "sr-only", children: "Search profiles by name or slug" }),
            /* @__PURE__ */ jsx2(
              Input,
              {
                id: "profile-search",
                type: "search",
                placeholder: "Name or @slug\u2026",
                value: query,
                onChange: (e) => setQuery(e.target.value),
                className: "flex-1"
              }
            ),
            /* @__PURE__ */ jsx2(
              Button,
              {
                type: "submit",
                size: "default",
                disabled: !query.trim() || search.status === "loading",
                "aria-label": "Search profiles",
                children: /* @__PURE__ */ jsx2(Search, { className: "size-4", "aria-hidden": "true" })
              }
            )
          ] })
        }
      ),
      search.status === "loading" && /* @__PURE__ */ jsx2(
        "p",
        {
          className: "mt-4 text-sm text-apt-text-muted",
          role: "status",
          "aria-live": "polite",
          children: "Searching\u2026"
        }
      ),
      search.status === "error" && /* @__PURE__ */ jsx2(ErrorText, { error: search.message, className: "mt-4" }),
      search.status === "success" && /* @__PURE__ */ jsx2("div", { "aria-live": "polite", children: search.hits.length === 0 ? /* @__PURE__ */ jsx2("p", { className: "mt-4 text-sm text-apt-text-muted", children: "Nothing found." }) : /* @__PURE__ */ jsx2(
        "ul",
        {
          className: "mt-4 space-y-2",
          "aria-label": "Search results",
          children: search.hits.map((hit) => {
            const displayName = hit.displayName ?? hit.slug;
            return (
              // The key carries the KIND, not the slug alone. The search merged two
              // namespaces into one response and a user and an organization may hold
              // the same slug in different tables, so a slug-only key can collide —
              // and two rows with one key make React reuse the wrong DOM node, showing
              // an organization wearing a person's face. An index key would be no
              // better: the list re-renders as the query changes, which is the same
              // bug in a form that is harder to see.
              /* @__PURE__ */ jsx2("li", { children: /* @__PURE__ */ jsxs2(
                Link,
                {
                  href: `/${encodeURIComponent(hit.slug)}`,
                  className: "flex items-center gap-3 rounded-lg border border-apt-border bg-apt-surface px-4 py-3 text-sm transition-colors hover:border-apt-border-strong hover:bg-apt-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-apt-gold/40",
                  children: [
                    /* @__PURE__ */ jsxs2(Avatar, { className: "size-8 shrink-0", children: [
                      hit.avatarUrl && /* @__PURE__ */ jsx2(
                        AvatarImage,
                        {
                          src: hit.avatarUrl,
                          alt: "",
                          "aria-hidden": "true"
                        }
                      ),
                      /* @__PURE__ */ jsx2(AvatarFallback, { className: "text-xs", children: initials(displayName) })
                    ] }),
                    /* @__PURE__ */ jsxs2("div", { className: "min-w-0", children: [
                      /* @__PURE__ */ jsx2("div", { className: "font-medium text-apt-text", children: displayName }),
                      /* @__PURE__ */ jsxs2("div", { className: "font-mono text-xs text-apt-text-muted", children: [
                        "@",
                        hit.slug,
                        " \xB7 ",
                        hit.kind === "organization" ? "org" : "user"
                      ] })
                    ] })
                  ]
                }
              ) }, `${hit.kind}:${hit.slug}`)
            );
          })
        }
      ) })
    ] })
  ] }) });
}

// src/profile/ProfileFallback.tsx
import { useEffect as useEffect3, useMemo, useState as useState4 } from "react";
import { jsx as jsx3 } from "react/jsx-runtime";
function ProfileFallback({ slug, siteId, section }) {
  const [state, setState] = useState4({ status: "loading" });
  const { principal: viewer, pending: viewerPending } = useViewerPrincipal(slug, null);
  const viewerSection = useMemo(() => viewer ? section?.(viewer) : void 0, [viewer, section]);
  useEffect3(() => {
    let cancelled = false;
    setState({ status: "loading" });
    void (async () => {
      try {
        const encoded = encodeURIComponent(slug);
        const users = await fetch(`/api/public/users/${encoded}`);
        if (cancelled) return;
        if (users.ok) {
          const body = await users.json();
          if (!cancelled) setState({ status: "found", principal: principalFromUserCard(body) });
          return;
        }
        if (users.status !== 404) return setState({ status: "error" });
        const orgs = await fetch(`/api/public/orgs/${encoded}`);
        if (cancelled) return;
        if (orgs.ok) {
          const body = await orgs.json();
          if (!cancelled) setState({ status: "found", principal: principalFromOrgCard(body) });
          return;
        }
        if (orgs.status === 404) return setState({ status: "missing" });
        setState({ status: "error" });
      } catch {
        if (!cancelled) setState({ status: "error" });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [slug]);
  if (viewer)
    return /* @__PURE__ */ jsx3(ProfileView, { principal: viewer, siteId, upgrade: false, children: viewerSection });
  if (state.status === "loading") return null;
  if (state.status === "found")
    return /* @__PURE__ */ jsx3(ProfileView, { principal: state.principal, siteId, upgrade: false, children: section?.(state.principal) });
  if (viewerPending) return null;
  if (state.status === "missing") return /* @__PURE__ */ jsx3(ProfileNotFound, {});
  return /* @__PURE__ */ jsx3("main", { className: PROFILE_FRAME_CLASS, children: /* @__PURE__ */ jsx3("p", { className: "text-apt-text-muted", children: "Couldn't load this profile. Reload the page to try again." }) });
}
export {
  ProfileFallback,
  ProfileNotFound,
  ProfileSkeleton,
  ProfileView,
  useViewerPrincipal
};
//# sourceMappingURL=index.js.map