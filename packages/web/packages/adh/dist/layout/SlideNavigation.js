'use client'

"use client";

// src/layout/SlideNavigation.tsx
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
var SLIDE_ATTR = "data-adh-slide";
var RENDER_TIMEOUT_MS = 1500;
var slides = [];
var MAX_SLIDES = 20;
var renderedPath = null;
var renderedIndex = null;
var waiters = /* @__PURE__ */ new Set();
var push = null;
function currentEntryIndex() {
  const index = window.navigation?.currentEntry?.index;
  return typeof index === "number" && index >= 0 ? index : null;
}
function markRendered(path) {
  renderedPath = path;
  renderedIndex = currentEntryIndex();
  for (const w of waiters) {
    if (w.path === path) {
      waiters.delete(w);
      w.resolve(true);
    }
  }
}
function untilRendered(path) {
  if (renderedPath === path) return Promise.resolve(true);
  return new Promise((resolve) => {
    const waiter = { path, resolve };
    waiters.add(waiter);
    setTimeout(() => {
      if (waiters.delete(waiter)) resolve(false);
    }, RENDER_TIMEOUT_MS);
  });
}
function abandonWaits() {
  for (const w of waiters) w.resolve(false);
  waiters.clear();
}
function canSlide() {
  if (typeof document === "undefined") return false;
  if (typeof document.startViewTransition !== "function") return false;
  const choice = document.documentElement.dataset.reduceMotion;
  if (choice === "on") return false;
  if (choice === "off") return true;
  return !window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}
var activeSlide = null;
function runSlide(direction, target, update) {
  const root = document.documentElement;
  const token = {};
  activeSlide = token;
  root.setAttribute(SLIDE_ATTR, direction);
  const transition = document.startViewTransition(async () => {
    if (!update() || !await untilRendered(target)) transition.skipTransition();
  });
  void transition.finished.finally(() => {
    if (activeSlide !== token) return;
    activeSlide = null;
    root.removeAttribute(SLIDE_ATTR);
  });
}
function pathOf(href) {
  return new URL(href, window.location.href).pathname;
}
function slideNavigate(href) {
  const navigate = push;
  if (!navigate || !canSlide()) return false;
  const from = window.location.pathname;
  const to = pathOf(href);
  if (from === to) return false;
  slides.push({ from, to });
  if (slides.length > MAX_SLIDES) slides.shift();
  runSlide("forward", to, () => {
    navigate(href);
    return true;
  });
  return true;
}
function slidBetween(a, b) {
  return slides.some((s) => s.from === a && s.to === b || s.from === b && s.to === a);
}
var REPLAYED = /* @__PURE__ */ Symbol("adh-slide-replayed");
function SlideTransitions() {
  const pathname = usePathname();
  const router = useRouter();
  useEffect(() => {
    const own = (href) => router.push(href);
    push = own;
    return () => {
      if (push === own) push = null;
    };
  }, [router]);
  useEffect(() => {
    if (pathname) markRendered(pathname);
  }, [pathname]);
  useEffect(() => {
    let traversals = 0;
    const onPopState = (e) => {
      if (e[REPLAYED]) return;
      const seen = ++traversals;
      abandonWaits();
      const from = renderedPath;
      const to = window.location.pathname;
      if (!from || from === to || !canSlide() || !slidBetween(from, to)) return;
      const index = currentEntryIndex();
      if (index === null || renderedIndex === null || index === renderedIndex) return;
      e.stopImmediatePropagation();
      runSlide(index < renderedIndex ? "back" : "forward", to, () => {
        if (traversals !== seen || window.location.pathname !== to) return false;
        const replay = new PopStateEvent("popstate", { state: window.history.state });
        replay[REPLAYED] = true;
        window.dispatchEvent(replay);
        return true;
      });
    };
    window.addEventListener("popstate", onPopState, { capture: true });
    return () => window.removeEventListener("popstate", onPopState, { capture: true });
  }, []);
  return null;
}
export {
  SLIDE_ATTR,
  SlideTransitions,
  canSlide,
  slideNavigate
};
//# sourceMappingURL=SlideNavigation.js.map