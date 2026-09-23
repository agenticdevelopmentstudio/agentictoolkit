'use client'

"use client";

// src/footer/AdhFooter.tsx
import Link from "next/link";
import { ChevronUp } from "lucide-react";
import { jsx, jsxs } from "react/jsx-runtime";
function closeContainingMenu(el) {
  const menu = el.closest("[popover]");
  if (menu && "hidePopover" in menu && menu.matches(":popover-open")) menu.hidePopover();
}
function menuItemClass(extra) {
  return ["adh-footer__link", extra].filter(Boolean).join(" ");
}
function FooterMenu({
  id,
  label,
  items,
  ariaLabel,
  className,
  triggerClassName = "adh-footer__link"
}) {
  const anchor = { "--adh-footer-menu-anchor": `--${id}` };
  return /* @__PURE__ */ jsxs("span", { className: ["adh-footer__menu-host", className].filter(Boolean).join(" "), style: anchor, children: [
    /* @__PURE__ */ jsxs(
      "button",
      {
        type: "button",
        popoverTarget: id,
        "aria-label": ariaLabel,
        "aria-haspopup": "menu",
        className: `${triggerClassName} adh-footer__menu-trigger`,
        children: [
          label,
          /* @__PURE__ */ jsx(ChevronUp, { className: "adh-footer__menu-caret", "aria-hidden": true })
        ]
      }
    ),
    /* @__PURE__ */ jsx("div", { id, popover: "auto", className: "adh-footer__menu", children: /* @__PURE__ */ jsx("ul", { className: "adh-footer__menu-list", children: items.map((item) => /* @__PURE__ */ jsx("li", { children: "popoverTarget" in item ? /* @__PURE__ */ jsx(
      "button",
      {
        type: "button",
        popoverTarget: item.popoverTarget,
        "aria-label": item.ariaLabel,
        className: menuItemClass("adh-footer__menu-item"),
        onClick: (e) => closeContainingMenu(e.currentTarget),
        children: item.label
      }
    ) : /* @__PURE__ */ jsx(
      Link,
      {
        href: item.href,
        className: menuItemClass("adh-footer__menu-item"),
        prefetch: item.prefetch,
        onClick: (e) => {
          closeContainingMenu(e.currentTarget);
          item.onSelect?.(e);
        },
        children: item.label
      }
    ) }, "popoverTarget" in item ? `popover:${item.popoverTarget}` : `href:${item.href}`)) }) })
  ] });
}
function AdhFooter({ links = [], copyright, trailing }) {
  return /* @__PURE__ */ jsxs("footer", { className: "adh-footer", role: "contentinfo", children: [
    /* @__PURE__ */ jsxs("div", { className: "adh-footer__container", children: [
      copyright && /* @__PURE__ */ jsx("span", { className: "adh-footer__copyright", children: copyright }),
      links.length > 0 && /* @__PURE__ */ jsx("nav", { className: "adh-footer__links", "aria-label": "Footer", children: links.map(
        (link) => "menuId" in link ? /* @__PURE__ */ jsx(
          FooterMenu,
          {
            id: link.menuId,
            label: link.label,
            items: link.items,
            ariaLabel: link.ariaLabel,
            className: link.className
          },
          `menu:${link.menuId}`
        ) : "popoverTarget" in link ? /* @__PURE__ */ jsx(
          "button",
          {
            type: "button",
            popoverTarget: link.popoverTarget,
            "aria-label": link.ariaLabel,
            className: ["adh-footer__link adh-footer__sites-trigger", link.className].filter(Boolean).join(" "),
            children: link.label
          },
          `popover:${link.popoverTarget}`
        ) : /* @__PURE__ */ jsx(
          Link,
          {
            href: link.href,
            className: menuItemClass(link.className),
            onClick: link.onSelect,
            prefetch: link.prefetch,
            children: link.label
          },
          `href:${link.href}:${link.label}`
        )
      ) })
    ] }),
    trailing
  ] });
}

// src/footer/SiteFooter.tsx
import {
  AdhFooter as ToolkitFooter,
  FooterMenu as FooterMenu2
} from "@agentic-toolkit/adh/footer";

// src/footer/AboutModal.tsx
import { getSite, siteProdUrl } from "@agentic-toolkit/adh-registry";

// src/footer/AdhModalPopover.tsx
import { X } from "lucide-react";
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
function AdhModalPopover({ id, title, children, bodyClassName }) {
  const titleId = `${id}-title`;
  return /* @__PURE__ */ jsxs2(
    "div",
    {
      id,
      popover: "auto",
      role: "dialog",
      "aria-modal": "true",
      "aria-labelledby": titleId,
      tabIndex: -1,
      className: "adh-modal",
      children: [
        /* @__PURE__ */ jsxs2("div", { className: "adh-modal__header", children: [
          /* @__PURE__ */ jsx2("h2", { id: titleId, className: "adh-modal__title", children: title }),
          /* @__PURE__ */ jsx2(
            "button",
            {
              type: "button",
              className: "adh-modal__close",
              popoverTarget: id,
              popoverTargetAction: "hide",
              "aria-label": "Close",
              children: /* @__PURE__ */ jsx2(X, { className: "adh-modal__close-icon", "aria-hidden": true })
            }
          )
        ] }),
        /* @__PURE__ */ jsx2("div", { className: `adh-modal__body${bodyClassName ? ` ${bodyClassName}` : ""}`, children })
      ]
    }
  );
}

// src/footer/AboutModal.tsx
import { jsx as jsx3, jsxs as jsxs3 } from "react/jsx-runtime";
var ABOUT_DIALOG_ID = "adh-about-dialog";
var BRAND_LABEL = "Agentic Development Studio";
var BRAND_HREF = "https://agenticdevelopmentstudio.com/";
function hostOf(href) {
  return new URL(href).host;
}
function Entry({ name, href, children }) {
  return /* @__PURE__ */ jsxs3("section", { className: "adh-about__entry", children: [
    /* @__PURE__ */ jsx3("h3", { className: "adh-about__name", children: name }),
    /* @__PURE__ */ jsx3("p", { className: "adh-about__blurb", children }),
    /* @__PURE__ */ jsx3("a", { className: "adh-about__link", href, children: hostOf(href) })
  ] });
}
function AboutModal({ version }) {
  const fishlamp = getSite("fishlamp");
  return /* @__PURE__ */ jsxs3(AdhModalPopover, { id: ABOUT_DIALOG_ID, title: "About", bodyClassName: "adh-modal__body--about", children: [
    /* @__PURE__ */ jsx3(Entry, { name: BRAND_LABEL, href: BRAND_HREF, children: "The company behind the Agentic Developer family of sites, and the name on their copyright." }),
    fishlamp && /* @__PURE__ */ jsxs3(Entry, { name: fishlamp.label, href: siteProdUrl("fishlamp", "/"), children: [
      fishlamp.description,
      "."
    ] }),
    /* @__PURE__ */ jsxs3("dl", { className: "adh-about__build", children: [
      /* @__PURE__ */ jsx3("dt", { children: "Site version" }),
      /* @__PURE__ */ jsx3("dd", { children: version ?? "Not recorded in this build" })
    ] })
  ] });
}

// src/footer/FooterChat.tsx
import dynamic from "next/dynamic";
import { jsx as jsx4 } from "react/jsx-runtime";
var FooterChatInner = dynamic(() => import("@agentic-toolkit/adh/footer/FooterChatInner"), {
  ssr: false
});
function FooterChat() {
  return /* @__PURE__ */ jsx4(FooterChatInner, {});
}

// src/footer/SitesOverview.tsx
import { FOOTER_SITES, groupSitesByCategory, siteProdUrl as siteProdUrl2 } from "@agentic-toolkit/adh-registry";
import { jsx as jsx5, jsxs as jsxs4 } from "react/jsx-runtime";
var SITES_OVERVIEW_POPOVER_ID = "adh-sites-overview";
function SitesPopover() {
  const groups = groupSitesByCategory(FOOTER_SITES);
  return /* @__PURE__ */ jsx5(AdhModalPopover, { id: SITES_OVERVIEW_POPOVER_ID, title: "The Agentic Developer family", children: groups.map((group) => /* @__PURE__ */ jsxs4(
    "nav",
    {
      className: "adh-sites-popover__group",
      "aria-label": group.label,
      children: [
        /* @__PURE__ */ jsx5("h3", { className: "adh-sites-popover__group-title", children: group.label }),
        /* @__PURE__ */ jsx5("ul", { className: "adh-sites-popover__list", children: group.sites.map((site) => /* @__PURE__ */ jsx5("li", { children: /* @__PURE__ */ jsxs4(
          "a",
          {
            className: "adh-sites-popover__item",
            href: siteProdUrl2(site.id, "/"),
            children: [
              /* @__PURE__ */ jsx5("span", { className: "adh-sites-popover__name", children: site.label }),
              site.description && /* @__PURE__ */ jsx5("span", { className: "adh-sites-popover__blurb", children: site.description })
            ]
          }
        ) }, site.id)) })
      ]
    },
    group.label
  )) });
}

// src/footer/LegalModals.tsx
import { useEffect, useState } from "react";
import { LEGAL_EFFECTIVE_DATE, TermsBody, PrivacyBody } from "@agentic-toolkit/adh/legal";
import { jsx as jsx6, jsxs as jsxs5 } from "react/jsx-runtime";
var TERMS_DIALOG_ID = "adh-terms-dialog";
var PRIVACY_DIALOG_ID = "adh-privacy-dialog";
function useOpenedOnce(id) {
  const [opened, setOpened] = useState(false);
  useEffect(() => {
    if (opened) return;
    const el = document.getElementById(id);
    if (!el) return;
    const onToggle = (e) => {
      if (e.newState === "open") setOpened(true);
    };
    el.addEventListener("toggle", onToggle);
    return () => el.removeEventListener("toggle", onToggle);
  }, [id, opened]);
  return opened;
}
function LegalDoc({ children }) {
  return /* @__PURE__ */ jsxs5("article", { className: "adh-legal-doc", children: [
    /* @__PURE__ */ jsxs5("p", { className: "adh-legal-doc__meta", children: [
      "Effective ",
      LEGAL_EFFECTIVE_DATE
    ] }),
    children
  ] });
}
function TermsModal() {
  const opened = useOpenedOnce(TERMS_DIALOG_ID);
  return /* @__PURE__ */ jsx6(AdhModalPopover, { id: TERMS_DIALOG_ID, title: "Terms of Service", bodyClassName: "adh-modal__body--legal", children: opened && /* @__PURE__ */ jsx6(LegalDoc, { children: /* @__PURE__ */ jsx6(TermsBody, {}) }) });
}
function PrivacyModal() {
  const opened = useOpenedOnce(PRIVACY_DIALOG_ID);
  return /* @__PURE__ */ jsx6(AdhModalPopover, { id: PRIVACY_DIALOG_ID, title: "Privacy Policy", bodyClassName: "adh-modal__body--legal", children: opened && /* @__PURE__ */ jsx6(LegalDoc, { children: /* @__PURE__ */ jsx6(PrivacyBody, {}) }) });
}
function openLegalModal(dialogId) {
  return (e) => {
    if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const el = document.getElementById(dialogId);
    if (el && "showPopover" in el) {
      e.preventDefault();
      el.showPopover();
    }
  };
}

// src/footer/SiteFooter.tsx
import { Fragment, jsx as jsx7, jsxs as jsxs6 } from "react/jsx-runtime";
var COPYRIGHT_PREFIX = "\xA9 2026 ";
var COPYRIGHT_MENU_ID = "adh-footer-copyright-menu";
var LEGAL_MENU_ID = "adh-footer-legal-menu";
var COPYRIGHT_MENU = [
  { label: "About", popoverTarget: ABOUT_DIALOG_ID },
  {
    label: "Sites",
    popoverTarget: SITES_OVERVIEW_POPOVER_ID,
    ariaLabel: "Sites \u2014 Agentic Developer family overview"
  }
];
var TERMS = {
  label: "Terms",
  href: "/terms",
  onSelect: openLegalModal(TERMS_DIALOG_ID),
  prefetch: false
};
var PRIVACY = {
  label: "Privacy",
  href: "/privacy",
  onSelect: openLegalModal(PRIVACY_DIALOG_ID),
  prefetch: false
};
var LEGAL_LINKS = [
  { ...TERMS, className: "adh-footer__link--wide" },
  { ...PRIVACY, className: "adh-footer__link--wide" },
  { label: "Legal", menuId: LEGAL_MENU_ID, items: [TERMS, PRIVACY], className: "adh-footer__link--narrow" }
];
function buildVersionLabel(live) {
  const version = live?.version ?? process.env.NEXT_PUBLIC_ADH_SITE_VERSION ?? "";
  const sha = live?.sha ?? process.env.NEXT_PUBLIC_ADH_RELEASE ?? "";
  const label = [version && `v${version}`, sha && sha.slice(0, 8)].filter(Boolean).join(" \xB7 ");
  if (!label) return null;
  return /* @__PURE__ */ jsx7("span", { title: sha || void 0, children: label });
}
function SiteFooter({ links = [], chat = true, live }) {
  return /* @__PURE__ */ jsxs6(Fragment, { children: [
    /* @__PURE__ */ jsx7(
      ToolkitFooter,
      {
        links: [...links, ...LEGAL_LINKS],
        copyright: /* @__PURE__ */ jsx7(
          FooterMenu2,
          {
            id: COPYRIGHT_MENU_ID,
            triggerClassName: "adh-footer__copyright-trigger",
            label: /* @__PURE__ */ jsxs6(Fragment, { children: [
              COPYRIGHT_PREFIX,
              /* @__PURE__ */ jsx7("span", { className: "adh-footer__brand-link", children: BRAND_LABEL })
            ] }),
            items: COPYRIGHT_MENU
          }
        ),
        trailing: chat ? /* @__PURE__ */ jsx7(FooterChat, {}) : null
      }
    ),
    /* @__PURE__ */ jsx7(AboutModal, { version: buildVersionLabel(live) }),
    /* @__PURE__ */ jsx7(SitesPopover, {}),
    /* @__PURE__ */ jsx7(TermsModal, {}),
    /* @__PURE__ */ jsx7(PrivacyModal, {})
  ] });
}

// src/footer/seededBackend.ts
var BITBAG_PERSONA = { name: "bitbag" };
function hash(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = h * 31 + s.charCodeAt(i) | 0;
  return h;
}
var SeededBackend = class {
  constructor(opts) {
    this.opts = opts;
  }
  opts;
  async sendMessage(text, _history) {
    await new Promise((r) => setTimeout(r, this.opts.delayMs ?? 450));
    for (const { match, reply } of this.opts.seeded) {
      if (match.test(text)) return reply;
    }
    const { fallbacks } = this.opts;
    return fallbacks[Math.abs(hash(text)) % fallbacks.length] ?? fallbacks[0];
  }
};
function createSeededBackend(opts) {
  return new SeededBackend(opts);
}

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
export {
  AdhFooter,
  BITBAG_PERSONA,
  FooterMenu,
  SITES_OVERVIEW_POPOVER_ID,
  SiteFooter,
  createSeededBackend,
  useChatTheme
};
//# sourceMappingURL=index.js.map