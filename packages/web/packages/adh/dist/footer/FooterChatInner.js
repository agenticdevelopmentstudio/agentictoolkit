'use client'

"use client";

// src/footer/FooterChatInner.tsx
import { createPortal } from "react-dom";
import { BitbagDock } from "@agentic-toolkit/bitbag";

// src/footer/chat-theme-store.ts
import { useCallback, useSyncExternalStore } from "react";
import { themeIds } from "@agentic-toolkit/bitbag";
import { DEV_BUILD } from "@agentic-toolkit/adh-registry/deployment-env";
var STORAGE_KEY = "adh-chat-theme";
var THEME_SWITCH_ENABLED = DEV_BUILD;
function readStored() {
  if (!THEME_SWITCH_ENABLED) return null;
  if (typeof window === "undefined") return null;
  try {
    const v = window.localStorage.getItem(STORAGE_KEY);
    if (v && themeIds.includes(v)) return v;
  } catch {
  }
  return null;
}
function writeStored(next) {
  if (typeof window === "undefined") return;
  try {
    if (next) window.localStorage.setItem(STORAGE_KEY, next);
    else window.localStorage.removeItem(STORAGE_KEY);
  } catch {
  }
  window.dispatchEvent(new CustomEvent(STORAGE_KEY));
}
function subscribe(callback) {
  if (typeof window === "undefined") return () => {
  };
  window.addEventListener(STORAGE_KEY, callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener(STORAGE_KEY, callback);
    window.removeEventListener("storage", callback);
  };
}
function useChatTheme() {
  const theme = useSyncExternalStore(subscribe, readStored, () => null);
  const setTheme = useCallback((next) => writeStored(next), []);
  return [theme, setTheme];
}

// src/footer/useFooterRestOffset.ts
import { useLayoutEffect } from "react";
var REST_OFFSET_VAR = "--adh-footer-rest-x";
var REST_SLOT_SELECTOR = ".adh-footer--with-chat .adh-footer__legal";
function restOffset(doc) {
  const host = doc.querySelector(REST_SLOT_SELECTOR);
  if (!host) return null;
  const slot = parseFloat(getComputedStyle(host).marginLeft) || 0;
  return host.getBoundingClientRect().left - slot / 2 - doc.documentElement.clientWidth / 2;
}
function useFooterRestOffset() {
  useLayoutEffect(() => {
    const root = document.documentElement;
    const update = () => {
      const x = restOffset(document);
      if (x === null) root.style.removeProperty(REST_OFFSET_VAR);
      else root.style.setProperty(REST_OFFSET_VAR, `${x}px`);
    };
    update();
    window.addEventListener("resize", update);
    const ro = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(update);
    for (const el of document.querySelectorAll(".adh-footer, " + REST_SLOT_SELECTOR)) ro?.observe(el);
    let live = true;
    document.fonts?.ready.then(() => {
      if (live) update();
    });
    return () => {
      live = false;
      window.removeEventListener("resize", update);
      ro?.disconnect();
      root.style.removeProperty(REST_OFFSET_VAR);
    };
  }, []);
}

// src/footer/FooterChatInner.tsx
import "@agentic-toolkit/bitbag/css/bitbag-dock.css";
import { jsx } from "react/jsx-runtime";
function FooterChatInner() {
  const [chatTheme] = useChatTheme();
  useFooterRestOffset();
  if (typeof document === "undefined") return null;
  return createPortal(
    /* @__PURE__ */ jsx(BitbagDock, { className: "adh-footer__chat", theme: chatTheme ?? void 0, rest: "avatar" }),
    document.body
  );
}
export {
  FooterChatInner as default
};
//# sourceMappingURL=FooterChatInner.js.map