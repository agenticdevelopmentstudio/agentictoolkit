'use client'

// src/layout/AppErrorBoundary.tsx
import { ErrorBoundary } from "@sentry/react";
import { useEffect } from "react";

// src/layout/chunk-recovery.ts
var CHUNK_UPDATE_COPY = {
  title: "Updating to the latest version",
  description: "A newer version of the site is available. Reloading now\u2026",
  retryLabel: "Reload now"
};
var RELOAD_GUARD_KEY = "adh:chunk-reload-at";
var RELOAD_COOLDOWN_MS = 1e4;
function isChunkLoadError(error) {
  if (!error || typeof error !== "object") return false;
  const { name, message } = error;
  if (name === "ChunkLoadError") return true;
  return typeof message === "string" && /Loading (CSS )?chunk|Failed to load chunk/i.test(message);
}
function recoverFromChunkError(error) {
  if (typeof window === "undefined" || !isChunkLoadError(error)) return false;
  try {
    const now = Date.now();
    const last = Number(window.sessionStorage.getItem(RELOAD_GUARD_KEY));
    if (now - last < RELOAD_COOLDOWN_MS) return false;
    window.sessionStorage.setItem(RELOAD_GUARD_KEY, String(now));
  } catch {
    return false;
  }
  window.location.reload();
  return true;
}

// src/layout/ErrorFallback.tsx
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import { jsx, jsxs } from "react/jsx-runtime";
function ErrorFallback({
  onRetry,
  retryLabel = "Try again",
  title = "Something went wrong",
  description = "An unexpected error occurred and has been reported to our team. Reloading the page usually fixes it."
}) {
  return /* @__PURE__ */ jsxs(
    "div",
    {
      role: "alert",
      className: "flex min-h-[60vh] flex-1 flex-col items-center justify-center gap-3 p-8 text-center",
      children: [
        /* @__PURE__ */ jsx("h1", { className: "text-lg font-semibold text-apt-text", children: title }),
        /* @__PURE__ */ jsx("p", { className: "max-w-md text-sm text-apt-text-muted", children: description }),
        /* @__PURE__ */ jsx(Button, { variant: "outline", onClick: onRetry, className: "mt-1", children: retryLabel })
      ]
    }
  );
}

// src/layout/AppErrorBoundary.tsx
import { jsx as jsx2 } from "react/jsx-runtime";
function Fallback({ error }) {
  useEffect(() => {
    recoverFromChunkError(error);
  }, [error]);
  if (isChunkLoadError(error)) {
    return /* @__PURE__ */ jsx2(ErrorFallback, { onRetry: () => window.location.reload(), ...CHUNK_UPDATE_COPY });
  }
  return /* @__PURE__ */ jsx2(ErrorFallback, { onRetry: () => window.location.reload(), retryLabel: "Reload" });
}
function AppErrorBoundary({ children }) {
  return /* @__PURE__ */ jsx2(ErrorBoundary, { fallback: ({ error }) => /* @__PURE__ */ jsx2(Fallback, { error }), children });
}

// src/layout/DevAnimScale.tsx
import { useEffect as useEffect2 } from "react";
import { useSlowAnimations, slowAnimationVars } from "@agenticdevelopertoolkit/ui/blocks";
function DevAnimScale() {
  const slow = useSlowAnimations();
  useEffect2(() => {
    if (!slow) return;
    const root = document.documentElement;
    const vars = slowAnimationVars();
    for (const [name, value] of Object.entries(vars)) root.style.setProperty(name, value);
    return () => {
      for (const name of Object.keys(vars)) root.style.removeProperty(name);
    };
  }, [slow]);
  return null;
}

// src/layout/HierarchicalDetailViewFlag.tsx
import { HierarchicalDetailViewProvider } from "@agenticdevelopertoolkit/ui/blocks";
import { jsx as jsx3 } from "react/jsx-runtime";
function HierarchicalDetailViewFlag({ children }) {
  return /* @__PURE__ */ jsx3(HierarchicalDetailViewProvider, { menuDetail: false, children });
}

// src/layout/HtdvLayoutLogSwitch.tsx
import { useEffect as useEffect3 } from "react";
import { setHtdvLayoutLog } from "@agenticdevelopertoolkit/ui/blocks";
function HtdvLayoutLogSwitch() {
  useEffect3(() => {
    setHtdvLayoutLog(true);
  }, []);
  return null;
}

// src/layout/SwipeHistory.tsx
import { useEffect as useEffect4 } from "react";
var SWIPE_MIN_DISTANCE = 80;
var SWIPE_MAX_DURATION_MS = 600;
var SWIPE_AXIS_RATIO = 2;
var SWIPE_EDGE_GUTTER = 24;
function classifySwipe(start, end, viewportWidth) {
  if (start.x < SWIPE_EDGE_GUTTER || start.x > viewportWidth - SWIPE_EDGE_GUTTER) return null;
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  if (end.t - start.t > SWIPE_MAX_DURATION_MS) return null;
  if (Math.abs(dx) < SWIPE_MIN_DISTANCE) return null;
  if (Math.abs(dx) < SWIPE_AXIS_RATIO * Math.abs(dy)) return null;
  return dx > 0 ? "back" : "forward";
}
var EXEMPT_SELECTOR = 'input, textarea, select, [contenteditable=""], [contenteditable="true"], [role="dialog"], [role="menu"], [role="listbox"], [role="slider"], [data-no-swipe-nav]';
function insideHorizontalScroller(el) {
  for (let node = el; node && node !== document.body; node = node.parentElement) {
    if (node.scrollWidth <= node.clientWidth) continue;
    const overflowX = getComputedStyle(node).overflowX;
    if (overflowX === "auto" || overflowX === "scroll") return true;
  }
  return false;
}
function swipeExempt(target) {
  if (!(target instanceof Element)) return false;
  return target.closest(EXEMPT_SELECTOR) !== null || insideHorizontalScroller(target);
}
function SwipeHistory() {
  useEffect4(() => {
    if (!window.matchMedia?.("(pointer: coarse)").matches) return;
    let start = null;
    const onStart = (e) => {
      start = null;
      const touch = e.touches[0];
      if (!touch || e.touches.length !== 1 || swipeExempt(e.target)) return;
      start = { x: touch.clientX, y: touch.clientY, t: e.timeStamp };
    };
    const onEnd = (e) => {
      if (!start) return;
      const touch = e.changedTouches[0];
      const from = start;
      start = null;
      if (!touch) return;
      const direction = classifySwipe(
        from,
        { x: touch.clientX, y: touch.clientY, t: e.timeStamp },
        window.innerWidth
      );
      if (direction === "back") window.history.back();
      else if (direction === "forward") window.history.forward();
    };
    const onCancel = () => {
      start = null;
    };
    document.addEventListener("touchstart", onStart, { passive: true });
    document.addEventListener("touchend", onEnd, { passive: true });
    document.addEventListener("touchcancel", onCancel, { passive: true });
    return () => {
      document.removeEventListener("touchstart", onStart);
      document.removeEventListener("touchend", onEnd);
      document.removeEventListener("touchcancel", onCancel);
    };
  }, []);
  return null;
}

// src/layout/AdhAppShell.tsx
import { Fragment, jsx as jsx4, jsxs as jsxs2 } from "react/jsx-runtime";
function AdhAppShell({ header, children, footer, devTools = false }) {
  return /* @__PURE__ */ jsxs2(Fragment, { children: [
    devTools && /* @__PURE__ */ jsx4(DevAnimScale, {}),
    devTools && /* @__PURE__ */ jsx4(HtdvLayoutLogSwitch, {}),
    /* @__PURE__ */ jsx4(SwipeHistory, {}),
    /* @__PURE__ */ jsx4(HierarchicalDetailViewFlag, { children: /* @__PURE__ */ jsxs2("div", { className: "adh-app-shell", children: [
      header,
      /* @__PURE__ */ jsx4("main", { className: "adh-app-shell__main", children: /* @__PURE__ */ jsx4(AppErrorBoundary, { children }) }),
      footer
    ] }) })
  ] });
}

// src/layout/RouteError.tsx
import { useEffect as useEffect5 } from "react";
import { captureException } from "@agentic-toolkit/adh/telemetry/report-error";
import { jsx as jsx5 } from "react/jsx-runtime";
function RouteError({
  error,
  reset
}) {
  const chunk = isChunkLoadError(error);
  useEffect5(() => {
    captureException(error, { boundary: "route-error", digest: error.digest ?? null });
    recoverFromChunkError(error);
  }, [error]);
  if (chunk) {
    return /* @__PURE__ */ jsx5(ErrorFallback, { onRetry: () => window.location.reload(), ...CHUNK_UPDATE_COPY });
  }
  return /* @__PURE__ */ jsx5(ErrorFallback, { onRetry: reset });
}

// src/layout/GlobalError.tsx
import { useEffect as useEffect6 } from "react";
import { captureException as captureException2 } from "@agentic-toolkit/adh/telemetry/report-error";
import { jsx as jsx6, jsxs as jsxs3 } from "react/jsx-runtime";
function GlobalError({
  error,
  reset
}) {
  const chunk = isChunkLoadError(error);
  useEffect6(() => {
    captureException2(error, { boundary: "global-error", digest: error.digest ?? null });
    recoverFromChunkError(error);
  }, [error]);
  return /* @__PURE__ */ jsx6("html", { lang: "en", children: /* @__PURE__ */ jsxs3(
    "body",
    {
      style: {
        margin: 0,
        minHeight: "100vh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 12,
        padding: 24,
        textAlign: "center",
        fontFamily: "system-ui, -apple-system, sans-serif"
      },
      children: [
        /* @__PURE__ */ jsx6("h1", { style: { fontSize: "1.125rem", fontWeight: 600, margin: 0 }, children: chunk ? CHUNK_UPDATE_COPY.title : "Something went wrong" }),
        /* @__PURE__ */ jsx6("p", { style: { fontSize: "0.875rem", margin: 0, maxWidth: 420 }, children: chunk ? CHUNK_UPDATE_COPY.description : "An unexpected error occurred and has been reported to our team." }),
        /* @__PURE__ */ jsx6(
          "button",
          {
            type: "button",
            onClick: chunk ? () => window.location.reload() : reset,
            style: { marginTop: 4, padding: "6px 12px", fontSize: "0.875rem", cursor: "pointer" },
            children: chunk ? CHUNK_UPDATE_COPY.retryLabel : "Try again"
          }
        )
      ]
    }
  ) });
}

// src/layout/SiteNotFound.tsx
import { useEffect as useEffect7 } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Fragment as Fragment2, jsx as jsx7, jsxs as jsxs4 } from "react/jsx-runtime";
function SiteNotFound({ siteSwitchHash, children }) {
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  useEffect7(() => {
    if (typeof window === "undefined") return;
    const hash = window.location.hash;
    if (hash !== siteSwitchHash && !hash.startsWith(`${siteSwitchHash}&`)) return;
    const segments = pathname.split("/").filter(Boolean);
    if (segments.length === 0) return;
    segments.pop();
    const parent = segments.length ? `/${segments.join("/")}` : "/";
    router.replace(parent === "/" ? "/" : `${parent}${siteSwitchHash}`);
  }, [pathname, router, siteSwitchHash]);
  return /* @__PURE__ */ jsx7(Fragment2, { children: children ?? /* @__PURE__ */ jsxs4("div", { className: "adh-not-found", children: [
    /* @__PURE__ */ jsx7("h1", { className: "adh-not-found__title", children: "404" }),
    /* @__PURE__ */ jsx7("p", { className: "adh-not-found__text", children: "This page could not be found." }),
    /* @__PURE__ */ jsx7("a", { className: "adh-not-found__link", href: "/", children: "Go to the home page" })
  ] }) });
}

// src/layout/HomePlaceholder.tsx
import { jsx as jsx8, jsxs as jsxs5 } from "react/jsx-runtime";
function HomePlaceholder({ siteLabel, blurb }) {
  return /* @__PURE__ */ jsxs5("section", { className: "adh-home-placeholder", children: [
    /* @__PURE__ */ jsx8("p", { className: "adh-home-placeholder__eyebrow", children: "Home \xB7 Workspace" }),
    /* @__PURE__ */ jsxs5("h1", { className: "adh-home-placeholder__title", children: [
      "Your ",
      /* @__PURE__ */ jsx8("span", { className: "adh-home-placeholder__accent", children: siteLabel }),
      " ",
      "workspace"
    ] }),
    /* @__PURE__ */ jsx8("p", { className: "adh-home-placeholder__text", children: blurb ?? "This is your authenticated home. The features for this site are on the way." })
  ] });
}

// src/layout/AppShell.tsx
import { SiteFooter } from "@agentic-toolkit/adh/footer";
import { SiteTelemetryProvider as TelemetryProvider } from "@agentic-toolkit/adh/telemetry";
import { FeatureFlagsProvider } from "@agentic-toolkit/adh/flags";
import { HelpProvider } from "@agentic-toolkit/adh/help";
import { SettingsOverlayProvider } from "@agentic-toolkit/adh/settings";
import { AdhAppShell as AdhAppShell2 } from "@agentic-toolkit/adh/layout";
import { liveBuildIdentity } from "@agentic-toolkit/adh/live-build-identity";
import { DEV_BUILD } from "@agentic-toolkit/adh-registry/deployment-env";
import { jsx as jsx9 } from "react/jsx-runtime";
var DEV_TOOLS_BUILD_ENABLED = DEV_BUILD;
function AppShell({ header, children, footer }) {
  return (
    // FeatureFlagsProvider wraps the WHOLE shell, not just the page: the header/landing are
    // consumers, and a site's own pages read the same one flag set rather than fetching it a
    // second time.
    /* @__PURE__ */ jsx9(FeatureFlagsProvider, { children: /* @__PURE__ */ jsx9(HelpProvider, { children: /* @__PURE__ */ jsx9(TelemetryProvider, { children: /* @__PURE__ */ jsx9(SettingsOverlayProvider, { children: /* @__PURE__ */ jsx9(
      AdhAppShell2,
      {
        header,
        footer: /* @__PURE__ */ jsx9(SiteFooter, { links: footer?.links, live: liveBuildIdentity() }),
        devTools: DEV_TOOLS_BUILD_ENABLED,
        children
      }
    ) }) }) }) })
  );
}

// src/layout/SiteSwitchNotFound.tsx
import { SITE_SWITCH_HASH } from "@agentic-toolkit/adh-registry";
import { SiteNotFound as AdhSiteNotFound } from "@agentic-toolkit/adh/layout";
import { jsx as jsx10 } from "react/jsx-runtime";
function SiteSwitchNotFound({ children }) {
  return /* @__PURE__ */ jsx10(AdhSiteNotFound, { siteSwitchHash: SITE_SWITCH_HASH, children });
}

// src/layout/SiteHomePlaceholder.tsx
import { getSite } from "@agentic-toolkit/adh-registry";
import { HomePlaceholder as AdhHomePlaceholder } from "@agentic-toolkit/adh/layout";
import { jsx as jsx11 } from "react/jsx-runtime";
function SiteHomePlaceholder({ siteId, blurb }) {
  return /* @__PURE__ */ jsx11(AdhHomePlaceholder, { siteLabel: getSite(siteId)?.label ?? "", blurb });
}

// src/layout/SiteLanding.tsx
import { jsx as jsx12, jsxs as jsxs6 } from "react/jsx-runtime";
var SERIF = "var(--font-serif, ui-serif, Georgia, serif)";
var SANS = "var(--font-sans, ui-sans-serif, system-ui, sans-serif)";
var MONO = "var(--font-mono, ui-monospace, monospace)";
var TEXT = "var(--color-text-primary, #e8e6e3)";
var MUTED = "var(--color-text-secondary, #8a8a9a)";
var ACCENT = "var(--color-accent, #c4a35a)";
var BORDER = "var(--color-border, #2a2a35)";
var wrap = {
  flex: 1,
  display: "flex",
  flexDirection: "column",
  alignItems: "center",
  justifyContent: "center",
  textAlign: "center",
  padding: "5rem 1.5rem",
  fontFamily: SERIF,
  color: TEXT
};
function SiteLanding({
  eyebrow,
  titleLead = "Agentic Developer",
  titleAccent,
  blurb
}) {
  return /* @__PURE__ */ jsx12("main", { style: wrap, children: /* @__PURE__ */ jsxs6("div", { style: { maxWidth: 720 }, children: [
    /* @__PURE__ */ jsx12(
      "div",
      {
        style: {
          fontFamily: `var(--type-landing-eyebrow-font, ${MONO})`,
          fontSize: "var(--type-landing-eyebrow-size, 0.7rem)",
          lineHeight: "var(--type-landing-eyebrow-line-height, 1.4)",
          letterSpacing: "var(--type-landing-eyebrow-tracking, 0.24em)",
          fontWeight: "var(--type-landing-eyebrow-weight, 500)",
          textTransform: "var(--type-landing-eyebrow-transform, uppercase)",
          color: MUTED,
          marginBottom: "1.75rem"
        },
        children: eyebrow
      }
    ),
    /* @__PURE__ */ jsxs6(
      "h1",
      {
        style: {
          fontFamily: `var(--type-landing-title-font, ${SERIF})`,
          fontSize: "var(--type-landing-title-size, clamp(2.6rem, 6vw, 4.5rem))",
          lineHeight: "var(--type-landing-title-line-height, 1.04)",
          letterSpacing: "var(--type-landing-title-tracking, -0.02em)",
          fontWeight: "var(--type-landing-title-weight, 400)",
          margin: "0 0 1.5rem"
        },
        children: [
          titleLead,
          " ",
          /* @__PURE__ */ jsx12("span", { style: { color: ACCENT, fontStyle: "italic" }, children: titleAccent })
        ]
      }
    ),
    /* @__PURE__ */ jsx12(
      "p",
      {
        style: {
          fontFamily: `var(--type-landing-lede-font, ${SANS})`,
          fontSize: "var(--type-landing-lede-size, 1.1rem)",
          lineHeight: "var(--type-landing-lede-line-height, 1.7)",
          fontWeight: "var(--type-landing-lede-weight, 400)",
          letterSpacing: "var(--type-landing-lede-tracking, 0)",
          color: MUTED,
          margin: "0 auto 2.75rem",
          maxWidth: 560
        },
        children: blurb
      }
    ),
    /* @__PURE__ */ jsx12(
      "div",
      {
        role: "separator",
        "aria-hidden": "true",
        style: {
          height: 1,
          background: `linear-gradient(to right, transparent, ${BORDER}, transparent)`,
          margin: "1rem 0 0"
        }
      }
    )
  ] }) });
}
export {
  AdhAppShell,
  AppErrorBoundary,
  AppShell,
  ErrorFallback,
  GlobalError,
  HierarchicalDetailViewFlag,
  HomePlaceholder,
  RouteError,
  SiteHomePlaceholder,
  SiteLanding,
  SiteNotFound,
  SiteSwitchNotFound
};
//# sourceMappingURL=index.js.map