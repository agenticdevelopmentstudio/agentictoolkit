'use client'
"use client";

"use client";

// src/home/SiteHomeRoute.tsx
import "react";
import { useParams } from "next/navigation";

// src/home/SiteHomeShell.tsx
import { useCallback as useCallback3 } from "react";
import { usePathname } from "next/navigation";
import { TopicSelectHint } from "@agenticdevelopertoolkit/ui/blocks";
import { useResourceList, workspacesApi } from "@agentic-toolkit/data";
import { HomeBarHost } from "@agentic-toolkit/resource";

// src/profile/ProfileFallback.tsx
import { useEffect as useEffect3, useMemo, useState as useState4 } from "react";

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

// src/profile/ProfileNotFound.tsx
import { useState, useCallback, useRef } from "react";
import Link from "next/link";
import { Search } from "lucide-react";
import { Avatar, AvatarImage, AvatarFallback } from "@agenticdevelopertoolkit/ui/components/avatar";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { ErrorText } from "@agenticdevelopertoolkit/ui/components/error-text";
import { jsx, jsxs } from "react/jsx-runtime";
function initials(name) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? "").join("");
}
function ProfileNotFound() {
  const [query, setQuery] = useState("");
  const [search, setSearch] = useState({ status: "idle" });
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
  return /* @__PURE__ */ jsx("main", { className: "mx-auto max-w-2xl px-4 py-16 sm:px-6", children: /* @__PURE__ */ jsxs("div", { className: "rounded-xl border border-apt-border bg-apt-bg p-8", children: [
    /* @__PURE__ */ jsx("h1", { className: "font-serif text-2xl font-medium text-apt-text sm:text-3xl", children: "Profile not found" }),
    /* @__PURE__ */ jsx("p", { className: "mt-3 text-apt-text-muted", children: "This profile doesn't exist, or its owner has chosen not to show it to you." }),
    /* @__PURE__ */ jsxs("div", { className: "mt-8", children: [
      /* @__PURE__ */ jsx(
        "div",
        {
          className: "mb-3 font-mono text-[0.6rem] uppercase tracking-[0.1em] text-apt-text-dim",
          id: "profile-search-label",
          children: "Search for someone else"
        }
      ),
      /* @__PURE__ */ jsx(
        "form",
        {
          onSubmit,
          role: "search",
          "aria-labelledby": "profile-search-label",
          children: /* @__PURE__ */ jsxs("div", { className: "flex gap-2", children: [
            /* @__PURE__ */ jsx("label", { htmlFor: "profile-search", className: "sr-only", children: "Search profiles by name or slug" }),
            /* @__PURE__ */ jsx(
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
            /* @__PURE__ */ jsx(
              Button,
              {
                type: "submit",
                size: "default",
                disabled: !query.trim() || search.status === "loading",
                "aria-label": "Search profiles",
                children: /* @__PURE__ */ jsx(Search, { className: "size-4", "aria-hidden": "true" })
              }
            )
          ] })
        }
      ),
      search.status === "loading" && /* @__PURE__ */ jsx(
        "p",
        {
          className: "mt-4 text-sm text-apt-text-muted",
          role: "status",
          "aria-live": "polite",
          children: "Searching\u2026"
        }
      ),
      search.status === "error" && /* @__PURE__ */ jsx(ErrorText, { error: search.message, className: "mt-4" }),
      search.status === "success" && /* @__PURE__ */ jsx("div", { "aria-live": "polite", children: search.hits.length === 0 ? /* @__PURE__ */ jsx("p", { className: "mt-4 text-sm text-apt-text-muted", children: "Nothing found." }) : /* @__PURE__ */ jsx(
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
              /* @__PURE__ */ jsx("li", { children: /* @__PURE__ */ jsxs(
                Link,
                {
                  href: `/${encodeURIComponent(hit.slug)}`,
                  className: "flex items-center gap-3 rounded-lg border border-apt-border bg-apt-surface px-4 py-3 text-sm transition-colors hover:border-apt-border-strong hover:bg-apt-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-apt-gold/40",
                  children: [
                    /* @__PURE__ */ jsxs(Avatar, { className: "size-8 shrink-0", children: [
                      hit.avatarUrl && /* @__PURE__ */ jsx(
                        AvatarImage,
                        {
                          src: hit.avatarUrl,
                          alt: "",
                          "aria-hidden": "true"
                        }
                      ),
                      /* @__PURE__ */ jsx(AvatarFallback, { className: "text-xs", children: initials(displayName) })
                    ] }),
                    /* @__PURE__ */ jsxs("div", { className: "min-w-0", children: [
                      /* @__PURE__ */ jsx("div", { className: "font-medium text-apt-text", children: displayName }),
                      /* @__PURE__ */ jsxs("div", { className: "font-mono text-xs text-apt-text-muted", children: [
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

// src/profile/ProfileView.tsx
import { siteUrl, siteProdUrl } from "@agentic-toolkit/adh-registry";
import { UserCard } from "@agenticdevelopertoolkit/ui/blocks/user-card";

// src/header/useClientHost.ts
import { useEffect, useState as useState2 } from "react";
function useClientHost() {
  const [host, setHost] = useState2(null);
  useEffect(() => setHost(window.location.host), []);
  return host;
}

// src/profile/useViewerPrincipal.ts
import { useEffect as useEffect2, useState as useState3 } from "react";
import { useOptionalAuth } from "@agentic-toolkit/auth";
import { authedJson } from "@agentic-toolkit/auth/client";
function useViewerPrincipal(slug, seed, enabled = true) {
  const auth = useOptionalAuth();
  const signedIn = auth?.isAuthenticated ?? false;
  const [wider, setWider] = useState3(null);
  const [pending, setPending] = useState3(false);
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
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
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
  return /* @__PURE__ */ jsxs2("main", { className: "mx-auto max-w-2xl px-4 py-16 sm:px-6", children: [
    /* @__PURE__ */ jsx2(UserCard, { user: shown }),
    shown.description && /* @__PURE__ */ jsx2("p", { className: "mt-4 text-apt-text-muted", children: shown.description }),
    children,
    fullProfileHref && /* @__PURE__ */ jsx2("div", { className: "mt-8 text-center", children: /* @__PURE__ */ jsx2(
      "a",
      {
        href: fullProfileHref,
        className: "text-sm text-apt-text-muted underline underline-offset-4 hover:text-apt-text",
        children: "Full Profile"
      }
    ) })
  ] });
}

// src/profile/ProfileFallback.tsx
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
  return /* @__PURE__ */ jsx3("main", { className: "mx-auto max-w-2xl px-4 py-16 sm:px-6", children: /* @__PURE__ */ jsx3("p", { className: "text-apt-text-muted", children: "Couldn't load this profile. Reload the page to try again." }) });
}

// src/home/SiteHomeShell.tsx
import { useSiteIdOrNull } from "@agentic-toolkit/adh/site/site-id";

// src/home/WorkspaceBar.tsx
import "react";

// src/home/WorkspacePicker.tsx
import "react";
import { ChevronDown } from "lucide-react";
import { PopupMenu } from "@agenticdevelopertoolkit/ui/blocks";
import { jsx as jsx4 } from "react/jsx-runtime";
function WorkspacePicker({
  workspaces,
  selected,
  onSelect
}) {
  const allLabel = workspaces === null ? "Loading\u2026" : workspaces.length === 0 ? "No workspaces" : selected === null ? "Loading\u2026" : null;
  return /* @__PURE__ */ jsx4(
    PopupMenu,
    {
      items: (workspaces ?? []).map((w) => ({ id: w.slug, label: w.name })),
      selectedId: selected,
      onSelect: (id) => {
        if (id) onSelect(id);
      },
      allLabel,
      ariaLabel: "Workspace",
      icon: /* @__PURE__ */ jsx4(ChevronDown, { size: 14, "aria-hidden": true, className: "shrink-0 text-apt-text-muted" }),
      className: "w-auto max-w-full"
    }
  );
}

// src/home/WorkspaceBar.tsx
import { jsx as jsx5, jsxs as jsxs3 } from "react/jsx-runtime";
function WorkspaceBar({
  workspaces,
  selected,
  onSelect,
  action
}) {
  return (
    // Three tracks, not a flex row: the label+picker group sits in the middle one so it is centred
    // on the BAR, not merely centred in what the action leaves over. A flex row can't do this —
    // the hub's action is `ml-auto`, so the group it pushes right of centre is off-centre by
    // exactly the action's width, and a site that passes no action would centre it differently
    // again. The empty first and third tracks are what make the two cases identical.
    /* @__PURE__ */ jsxs3("div", { className: "adh-home__toolbar", children: [
      /* @__PURE__ */ jsx5("div", { className: "adh-home__toolbar-control", children: /* @__PURE__ */ jsx5(WorkspacePicker, { workspaces, selected, onSelect }) }),
      action
    ] })
  );
}

// src/home/useWorkspaceRoute.ts
import { useCallback as useCallback2, useEffect as useEffect4, useMemo as useMemo2, useRef as useRef2, useState as useState5 } from "react";
import { useRouter } from "next/navigation";
import {
  useResourceItemQuery,
  useResourceItemWriter,
  workspacePrefsApi,
  readCachedWorkspace,
  writeCachedWorkspace
} from "@agentic-toolkit/data";
var PREFS_CACHE_KEY = "workspace-prefs";
var PREFS_ID = "me";
var loadPrefs = () => workspacePrefsApi.get();
var seededByUs = null;
var SEED_HANDOFF_MS = 1e4;
function withUrlExtras(href) {
  if (typeof window === "undefined") return href;
  if (href.includes("?") || href.includes("#")) return href;
  return href + window.location.search + window.location.hash;
}
function useWorkspaceRoute({
  workspaces,
  workspaceSlug,
  hrefFor,
  switchHrefFor,
  canPersist
}) {
  const router = useRouter();
  const [stored, setStored] = useState5(() => readCachedWorkspace());
  const { item: prefs, error: prefsError } = useResourceItemQuery(
    PREFS_CACHE_KEY,
    PREFS_ID,
    loadPrefs
  );
  const writePrefs = useResourceItemWriter(PREFS_CACHE_KEY);
  const settledByRead = prefs !== null || prefsError !== null;
  const [bailed, setBailed] = useState5(false);
  useEffect4(() => {
    if (settledByRead) return;
    const bail = setTimeout(() => setBailed(true), 5e3);
    return () => clearTimeout(bail);
  }, [settledByRead]);
  const prefsSettled = settledByRead || bailed;
  const arrivedOnOwnGuess = useRef2(
    workspaceSlug !== void 0 && seededByUs !== null && workspaceSlug === seededByUs.slug && Date.now() - seededByUs.at <= SEED_HANDOFF_MS
  );
  const [pendingWrite, setPendingWrite] = useState5(
    () => arrivedOnOwnGuess.current ? null : workspaceSlug ?? null
  );
  useEffect4(() => {
    seededByUs = null;
  }, []);
  const [wroteLocally, setWroteLocally] = useState5(false);
  const preference = wroteLocally ? stored : prefs?.slug ?? stored;
  useEffect4(() => {
    if (prefs?.slug && !wroteLocally) writeCachedWorkspace(prefs.slug);
  }, [prefs, wroteLocally]);
  const resolved = useMemo2(() => {
    if (workspaces === null) return void 0;
    const known = (s) => s && workspaces.some((w) => w.slug === s) ? s : null;
    const fromUrl = known(workspaceSlug);
    if (fromUrl) return fromUrl;
    if (workspaceSlug !== void 0) return void 0;
    if (!prefsSettled) return void 0;
    return known(preference) ?? workspaces[0]?.slug ?? null;
  }, [workspaces, workspaceSlug, preference, prefsSettled]);
  useEffect4(() => {
    if (resolved && resolved !== workspaceSlug) {
      seededByUs = { slug: resolved, at: Date.now() };
      router.replace(withUrlExtras(hrefFor(resolved)), { scroll: false });
    }
  }, [resolved, workspaceSlug, hrefFor, router]);
  useEffect4(() => {
    if (!resolved || resolved !== workspaceSlug || pendingWrite !== resolved) return;
    if (resolved === preference) return;
    setPendingWrite(null);
    if (canPersist && !canPersist(resolved)) return;
    setWroteLocally(true);
    writeCachedWorkspace(resolved);
    setStored(resolved);
    writePrefs(PREFS_ID, { slug: resolved });
    workspacePrefsApi.put({ slug: resolved }).catch(() => {
    });
  }, [resolved, workspaceSlug, preference, pendingWrite, canPersist, writePrefs]);
  const onSelect = useCallback2(
    (slug) => {
      seededByUs = null;
      setPendingWrite(slug);
      router.push((switchHrefFor ?? hrefFor)(slug), { scroll: false });
    },
    [hrefFor, switchHrefFor, router]
  );
  return { resolved, onSelect };
}

// src/home/workspacePathTail.ts
function workspacePathTail(pathname) {
  return pathname.split("/").filter(Boolean).slice(1);
}

// src/home/SiteHomeShell.tsx
import { Fragment, jsx as jsx6, jsxs as jsxs4 } from "react/jsx-runtime";
var loadWorkspaces = () => workspacesApi.list();
function SiteHomeShell({
  workspaceSlug,
  workspaceHref,
  children
}) {
  const { items: workspaces, error, isFetching } = useResourceList(
    "workspaces",
    loadWorkspaces
  );
  const hrefFor = useCallback3(
    (slug) => workspaceHref?.(slug) ?? `/${slug}`,
    [workspaceHref]
  );
  const pathname = usePathname() ?? "";
  const switchHrefFor = useCallback3(
    (slug) => `/${[slug, ...workspacePathTail(pathname)].join("/")}`,
    [pathname]
  );
  const { resolved, onSelect } = useWorkspaceRoute({
    workspaces,
    workspaceSlug,
    hrefFor,
    switchHrefFor
  });
  const workspace = workspaces?.find((w) => w.slug === resolved) ?? null;
  const siteId = useSiteIdOrNull();
  if (workspaceSlug !== void 0 && workspaces !== null && !isFetching && !workspaces.some((w) => w.slug === workspaceSlug)) {
    if (siteId === null) {
      throw new Error(
        "SiteHomeShell reached the profile branch outside <SiteIdProvider> \u2014 the workspace layout must mount it"
      );
    }
    return /* @__PURE__ */ jsx6(ProfileFallback, { slug: workspaceSlug, siteId });
  }
  return /* @__PURE__ */ jsxs4(Fragment, { children: [
    /* @__PURE__ */ jsx6(
      WorkspaceBar,
      {
        workspaces,
        selected: resolved ?? null,
        onSelect
      }
    ),
    /* @__PURE__ */ jsxs4(HomeBarHost, { children: [
      error !== null && workspaces === null && /* @__PURE__ */ jsx6(TopicSelectHint, { title: "Couldn't load your workspaces. Reload the page to try again." }),
      resolved === null && /* @__PURE__ */ jsx6(TopicSelectHint, { title: "No workspaces yet \u2014 create one from the hub to get started." }),
      resolved !== void 0 && resolved !== null && resolved === workspaceSlug && workspace !== null && children({
        workspaceSlug: resolved,
        scopedBase: `/${resolved}`,
        workspace
      })
    ] })
  ] });
}

// src/home/SiteHomeRoute.tsx
import { jsx as jsx7 } from "react/jsx-runtime";
var EMPTY_HOST_SEAMS = Object.freeze({});
function SiteHomeRoute({
  model,
  path,
  host
}) {
  const params = useParams();
  const raw = params?.path;
  const fromUrl = raw === void 0 ? [] : Array.isArray(raw) ? raw : [raw];
  const rest = path !== void 0 ? path : fromUrl;
  const workspaceSlug = params?.workspace;
  const view = model.parse(rest);
  const Shell = model.shell ?? SiteHomeShell;
  return /* @__PURE__ */ jsx7(
    Shell,
    {
      workspaceSlug,
      ...model.workspaceHref !== void 0 ? { workspaceHref: model.workspaceHref } : {},
      children: (scope) => model.render({ ...scope, view }, host ?? EMPTY_HOST_SEAMS)
    }
  );
}

// src/home/SiteHomeModel.ts
import { notFound } from "next/navigation";
function defineSiteHome(model) {
  return model;
}
function noSubPath(segments) {
  if (segments.length > 0) notFound();
  return null;
}

// src/home/WorkspaceOrProfileGate.tsx
import { useParams as useParams2 } from "next/navigation";
import { useAuth } from "@agentic-toolkit/auth";
import { useSiteId } from "@agentic-toolkit/adh/site/site-id";
import { Fragment as Fragment2, jsx as jsx8 } from "react/jsx-runtime";
function WorkspaceOrProfileGate({ children }) {
  const { isAuthenticated, isLoading } = useAuth();
  const params = useParams2();
  const slug = params?.workspace;
  const siteId = useSiteId();
  if (isLoading) return null;
  if (!isAuthenticated) {
    return slug ? /* @__PURE__ */ jsx8(ProfileFallback, { slug, siteId }) : null;
  }
  return /* @__PURE__ */ jsx8(Fragment2, { children });
}
export {
  SiteHomeRoute,
  SiteHomeShell,
  WorkspaceBar,
  WorkspaceOrProfileGate,
  WorkspacePicker,
  defineSiteHome,
  noSubPath,
  useWorkspaceRoute,
  workspacePathTail
};
//# sourceMappingURL=index.js.map