'use client'

"use client";

// src/header/AdhHeader.tsx
import "react";

// src/header/AvatarMenu.tsx
import Link from "next/link";
import { ChevronDown, Home, LogOut, Settings, User as UserIcon, Wrench } from "lucide-react";
import { Avatar, AvatarFallback, AvatarImage } from "@agenticdevelopertoolkit/ui/components/avatar";
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLinkItem,
  DropdownMenuSeparator
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";

// src/layout/SlideNavigation.tsx
import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
var SLIDE_ATTR = "data-adh-slide";
var RENDER_TIMEOUT_MS = 1500;
var slides = [];
var MAX_SLIDES = 20;
var renderedPath = null;
var waiters = /* @__PURE__ */ new Set();
var push = null;
function untilRendered(path) {
  if (renderedPath === path) return Promise.resolve();
  return new Promise((resolve) => {
    const waiter = { path, resolve };
    waiters.add(waiter);
    setTimeout(() => {
      if (waiters.delete(waiter)) resolve();
    }, RENDER_TIMEOUT_MS);
  });
}
function canSlide() {
  if (typeof document === "undefined") return false;
  if (typeof document.startViewTransition !== "function") return false;
  return !window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}
function runSlide(direction, target, update) {
  const root = document.documentElement;
  root.setAttribute(SLIDE_ATTR, direction);
  const transition = document.startViewTransition(async () => {
    update();
    await untilRendered(target);
  });
  void transition.finished.finally(() => {
    if (root.getAttribute(SLIDE_ATTR) === direction) root.removeAttribute(SLIDE_ATTR);
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
  runSlide("forward", to, () => navigate(href));
  return true;
}

// src/header/AvatarMenu.tsx
import { Fragment, jsx, jsxs } from "react/jsx-runtime";
function firstNameOf(name) {
  return name.trim().split(/\s+/)[0] || name;
}
function initialsOf(name) {
  if (!name) return "";
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]?.toUpperCase() ?? "").join("");
}
function AvatarMenu({
  user,
  homeHref = "/",
  profileHref,
  onLogout,
  settingsHref,
  onSettings,
  onDebugOptions,
  debugOptionsHint
}) {
  const avatarInner = /* @__PURE__ */ jsxs(Avatar, { className: "adh-avatar-menu-trigger__avatar", children: [
    user.imageUrl && /* @__PURE__ */ jsx(AvatarImage, { src: user.imageUrl, alt: user.name }),
    /* @__PURE__ */ jsx(AvatarFallback, { children: initialsOf(user.name) || /* @__PURE__ */ jsx(UserIcon, { className: "adh-avatar-menu-trigger__fallback-icon" }) })
  ] });
  const settingsBody = /* @__PURE__ */ jsxs(Fragment, { children: [
    /* @__PURE__ */ jsx(Settings, { className: "adh-avatar-menu__item-icon" }),
    /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-label", children: "User Settings" })
  ] });
  const settingsItem = onSettings ? /* @__PURE__ */ jsx(DropdownMenuItem, { onClick: onSettings, className: "adh-avatar-menu__item", children: settingsBody }) : settingsHref ? /* @__PURE__ */ jsx(DropdownMenuLinkItem, { render: /* @__PURE__ */ jsx(Link, { href: settingsHref }), className: "adh-avatar-menu__item", children: settingsBody }) : null;
  return /* @__PURE__ */ jsxs(DropdownMenu, { children: [
    /* @__PURE__ */ jsxs(
      DropdownMenuTrigger,
      {
        className: "adh-avatar-menu-trigger",
        "aria-label": `Open ${user.name} menu`,
        children: [
          /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu-trigger__avatar-wrap", children: avatarInner }),
          /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu-trigger__chevron", "aria-hidden": "true", children: /* @__PURE__ */ jsx(ChevronDown, { className: "adh-avatar-menu-trigger__chevron-icon" }) })
        ]
      }
    ),
    /* @__PURE__ */ jsxs(DropdownMenuContent, { className: "adh-avatar-menu", align: "end", sideOffset: 8, children: [
      /* @__PURE__ */ jsx("div", { className: "adh-avatar-menu__header", children: /* @__PURE__ */ jsx("div", { className: "adh-avatar-menu__identity", children: /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__name", children: user.fullName ? `Welcome ${firstNameOf(user.fullName)}!` : user.name }) }) }),
      /* @__PURE__ */ jsx(DropdownMenuSeparator, {}),
      /* @__PURE__ */ jsxs(DropdownMenuLinkItem, { render: /* @__PURE__ */ jsx(Link, { href: homeHref }), className: "adh-avatar-menu__item", children: [
        /* @__PURE__ */ jsx(Home, { className: "adh-avatar-menu__item-icon" }),
        /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-label", children: "Home" })
      ] }),
      profileHref && /* @__PURE__ */ jsxs(
        DropdownMenuLinkItem,
        {
          render: /* @__PURE__ */ jsx(
            Link,
            {
              href: profileHref,
              onClick: (e) => {
                if (e.defaultPrevented || e.button !== 0) return;
                if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
                if (slideNavigate(profileHref)) e.preventDefault();
              }
            }
          ),
          className: "adh-avatar-menu__item",
          children: [
            /* @__PURE__ */ jsx(UserIcon, { className: "adh-avatar-menu__item-icon" }),
            /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-label", children: "Profile" })
          ]
        }
      ),
      settingsItem && /* @__PURE__ */ jsxs(Fragment, { children: [
        /* @__PURE__ */ jsx(DropdownMenuSeparator, {}),
        settingsItem
      ] }),
      onLogout && /* @__PURE__ */ jsxs(Fragment, { children: [
        /* @__PURE__ */ jsx(DropdownMenuSeparator, {}),
        /* @__PURE__ */ jsxs(
          DropdownMenuItem,
          {
            onClick: onLogout,
            className: "adh-avatar-menu__item",
            children: [
              /* @__PURE__ */ jsx(LogOut, { className: "adh-avatar-menu__item-icon" }),
              /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-label", children: "Log out" })
            ]
          }
        )
      ] }),
      onDebugOptions && /* @__PURE__ */ jsxs(Fragment, { children: [
        /* @__PURE__ */ jsx(DropdownMenuSeparator, {}),
        /* @__PURE__ */ jsxs(DropdownMenuItem, { onClick: onDebugOptions, className: "adh-avatar-menu__item", children: [
          /* @__PURE__ */ jsx(Wrench, { className: "adh-avatar-menu__item-icon" }),
          /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-label", children: "Debug Options" }),
          debugOptionsHint && /* @__PURE__ */ jsx("span", { className: "adh-avatar-menu__item-hint", children: debugOptionsHint })
        ] })
      ] })
    ] })
  ] });
}

// src/header/AuthButtons.tsx
import { Fragment as Fragment2, jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
function AuthButtons({
  onSignup,
  onLogin,
  signupHref,
  loginHref,
  signupLabel = "join",
  loginLabel = "login"
}) {
  const loginNode = onLogin ? (
    // adh-ui-allow: cs-no-bespoke — this is the <a> two lines down in button clothing: same affordance, same .adh-header__nav-link identity, chosen only by whether a handler or an href was passed. A @agenticdevelopertoolkit/ui <Button> brings its own visual identity, which is exactly what must NOT happen to a nav link.
    /* @__PURE__ */ jsx2("button", { type: "button", onClick: onLogin, className: "adh-header__nav-link adh-header__nav-link--button", children: loginLabel })
  ) : loginHref ? /* @__PURE__ */ jsx2("a", { href: loginHref, className: "adh-header__nav-link", children: loginLabel }) : null;
  const signupNode = onSignup ? (
    // adh-ui-allow: cs-no-bespoke — same as loginNode above: the handler variant of a nav link, not a button. Keep the two branches visually identical.
    /* @__PURE__ */ jsx2("button", { type: "button", onClick: onSignup, className: "adh-header__nav-link adh-header__nav-link--button", children: signupLabel })
  ) : signupHref ? /* @__PURE__ */ jsx2("a", { href: signupHref, className: "adh-header__nav-link", children: signupLabel }) : null;
  return /* @__PURE__ */ jsxs2(Fragment2, { children: [
    loginNode,
    signupNode
  ] });
}

// src/header/SiteSwitcher.tsx
import Link3 from "next/link";
import "react";

// src/header/NavigationPopover.tsx
import {
  Fragment as Fragment3,
  useCallback,
  useEffect as useEffect2,
  useId,
  useMemo,
  useRef,
  useState
} from "react";
import { ChevronDown as ChevronDown2 } from "lucide-react";

// src/header/NavLink.tsx
import Link2 from "next/link";
import { usePathname as usePathname2 } from "next/navigation";
import { jsx as jsx3 } from "react/jsx-runtime";
function pathMatches(pathname, pattern) {
  if (pattern === pathname) return true;
  if (pattern.endsWith("/*")) {
    const prefix = pattern.slice(0, -2);
    return pathname === prefix || pathname.startsWith(`${prefix}/`);
  }
  return false;
}
function NavLinkItem({ link }) {
  const pathname = usePathname2() ?? "";
  const matchers = link.matchPaths ?? [link.href];
  const active = matchers.some((m) => pathMatches(pathname, m));
  return /* @__PURE__ */ jsx3(
    Link2,
    {
      href: link.href,
      "aria-current": active ? "page" : void 0,
      className: "adh-header__nav-link",
      "data-active": active ? "" : void 0,
      children: link.label
    }
  );
}

// src/header/NavigationPopover.tsx
import { cn, noAutofillProps } from "@agenticdevelopertoolkit/ui";
import { confirmNavigation, GUARDED_NAV_ATTR } from "@agenticdevelopertoolkit/ui/lib/navigation-guard";
import { useShortcut, chordFromEvent, sameChord } from "@agenticdevelopertoolkit/ui/hooks/useShortcut";
import {
  DropdownMenu as DropdownMenu2,
  DropdownMenuTrigger as DropdownMenuTrigger2,
  DropdownMenuContent as DropdownMenuContent2,
  DropdownMenuLabel,
  DropdownMenuSeparator as DropdownMenuSeparator2,
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { Fragment as Fragment4, jsx as jsx4, jsxs as jsxs3 } from "react/jsx-runtime";
var GUARDED_NAV_PROPS = { [GUARDED_NAV_ATTR]: "" };
function highlightMatch(text, query) {
  const needle = query.trim();
  if (!needle) return text;
  const lower = text.toLowerCase();
  const ln = needle.toLowerCase();
  const out = [];
  let i = 0;
  let key = 0;
  while (i < text.length) {
    const at = lower.indexOf(ln, i);
    if (at === -1) {
      out.push(text.slice(i));
      break;
    }
    if (at > i) out.push(text.slice(i, at));
    out.push(
      /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__hl", children: text.slice(at, at + needle.length) }, key++)
    );
    i = at + needle.length;
  }
  return out;
}
function IconSlot({ icon: Icon }) {
  if (!Icon) return null;
  return /* @__PURE__ */ jsx4(Icon, { className: "adh-dropdown-menu__item-icon adh-nav-popover__icon", "aria-hidden": true });
}
function topicItem(entry) {
  return {
    key: `topic:${entry.label}`,
    label: entry.label,
    description: entry.description,
    href: entry.href,
    icon: entry.icon,
    current: entry.current
  };
}
function isModifiedClick(event) {
  return event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey;
}
function NavigationPopover({
  entries,
  triggerLabel,
  triggerContent,
  triggerText,
  triggerIcon,
  triggerClassName,
  placeholder = "Search, or browse topics",
  emptyLabel = "No matches",
  onChoose,
  commandTrailing,
  searchCommand,
  footer,
  sectionLabels,
  openShortcut
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [nav, setNav] = useState({ kind: "none" });
  const [searchIndex, setSearchIndex] = useState(0);
  const inputRef = useRef(null);
  const uid = useId();
  const navByKeyboard = useRef(false);
  const suppressFocusRestore = useRef(false);
  const close = useCallback((opts) => {
    if (opts?.restoreFocus === false) suppressFocusRestore.current = true;
    setOpen(false);
  }, []);
  useShortcut(
    {
      keys: openShortcut?.keys ?? "",
      label: openShortcut?.label ?? "",
      group: "Navigation",
      allowInInput: true,
      enabled: Boolean(openShortcut?.keys)
    },
    () => setOpen((cur) => !cur)
  );
  const closeOnShortcut = useCallback(
    (event) => {
      const keys = openShortcut?.keys;
      if (!keys) return;
      const chord = chordFromEvent(event.nativeEvent);
      if (chord === null || !sameChord(chord, keys)) return;
      event.preventDefault();
      setOpen(false);
    },
    [openShortcut?.keys]
  );
  const chooseItem = useCallback(
    (item) => {
      setOpen(false);
      if (item.onSelect) {
        item.onSelect();
        return;
      }
      if (onChoose) {
        onChoose(item);
        return;
      }
      if (item.href && item.href !== "#") {
        const href = item.href;
        void confirmNavigation().then((ok) => {
          if (ok) window.location.assign(href);
        });
      }
    },
    [onChoose]
  );
  const searchTargets = useMemo(() => {
    const out = [];
    for (const e of entries) {
      if (e.kind === "topic") {
        if (e.href !== void 0) out.push({ item: topicItem(e), area: null });
        for (const item of e.items) out.push({ item, area: e.label });
      } else {
        out.push({ item: e.item, area: null });
      }
    }
    return out;
  }, [entries]);
  const searchResults = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return [];
    return searchTargets.filter(
      (t) => t.item.label.toLowerCase().includes(needle) || (t.item.description?.toLowerCase().includes(needle) ?? false)
    );
  }, [searchTargets, query]);
  const trimmed = query.trim();
  const searching = trimmed.length > 0;
  const cmdActive = searching && (searchCommand?.matches(trimmed) ?? false);
  const searchActive = searchResults.length === 0 ? -1 : Math.min(searchIndex, searchResults.length - 1);
  const selectCommand = useCallback(() => {
    if (!searchCommand) return;
    close({ restoreFocus: false });
    searchCommand.onSelect();
  }, [close, searchCommand]);
  const leaveRows = useCallback(() => {
    if (navByKeyboard.current) return;
    setNav((cur) => cur.kind === "none" ? cur : { kind: "none" });
  }, []);
  const disclosed = nav.kind === "sub" ? nav.entry : nav.kind === "top" && nav.open ? nav.entry : null;
  const activeKey = searching ? cmdActive ? "cmd" : searchActive >= 0 ? `s${searchActive}` : null : nav.kind === "sub" ? `e${nav.entry}s${nav.item}` : nav.kind === "top" ? `e${nav.entry}` : null;
  const activeId = activeKey ? `${uid}-${activeKey}` : void 0;
  useEffect2(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => {
      if (document.activeElement !== inputRef.current) inputRef.current?.focus();
    });
    return () => cancelAnimationFrame(frame);
  }, [open, nav, searching]);
  useEffect2(() => {
    if (!navByKeyboard.current || !activeKey) return;
    document.getElementById(`${uid}-${activeKey}`)?.scrollIntoView({ block: "nearest" });
  }, [uid, activeKey, query]);
  function moveSel(dir) {
    navByKeyboard.current = true;
    if (nav.kind === "sub") {
      const entry = entries[nav.entry];
      if (entry?.kind === "topic") {
        const next = nav.item + dir;
        if (next >= 0 && next < entry.items.length) {
          setNav({ kind: "sub", entry: nav.entry, item: next });
          return;
        }
        const siblingIdx = nav.entry + dir;
        const sibling = entries[siblingIdx];
        if (sibling?.kind === "topic") {
          setNav({ kind: "sub", entry: siblingIdx, item: dir > 0 ? 0 : sibling.items.length - 1 });
        }
        return;
      }
    }
    const n = entries.length;
    if (!n) return;
    const cur = nav.kind === "none" ? null : nav.entry;
    const nextEntry = cur === null ? dir > 0 ? 0 : n - 1 : (cur + dir + n) % n;
    setNav({ kind: "top", entry: nextEntry, open: false });
  }
  function discloseRight() {
    if (nav.kind !== "top") return;
    if (entries[nav.entry]?.kind !== "topic") return;
    navByKeyboard.current = true;
    setNav({ kind: "sub", entry: nav.entry, item: 0 });
  }
  function collapseLeft() {
    navByKeyboard.current = true;
    if (nav.kind === "sub" || nav.kind === "top" && nav.open) {
      setNav({ kind: "top", entry: nav.entry, open: false });
    }
  }
  function choose() {
    if (searching) {
      if (cmdActive) {
        selectCommand();
        return;
      }
      const target = searchResults[searchActive]?.item;
      if (!target) return;
      chooseItem(target);
      return;
    }
    if (nav.kind === "none") return;
    const entry = entries[nav.entry];
    if (!entry) return;
    if (nav.kind === "top") {
      if (entry.kind === "topic") {
        if (entry.href) {
          chooseItem(topicItem(entry));
          return;
        }
        discloseRight();
        return;
      }
      chooseItem(entry.item);
      return;
    }
    if (entry.kind === "topic") {
      const item = entry.items[nav.item];
      if (item) chooseItem(item);
    }
  }
  function handleOpenChange(next) {
    setOpen(next);
    if (next) {
      setQuery("");
      setNav({ kind: "none" });
      setSearchIndex(0);
    }
  }
  function handleInputKeyDown(event) {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        event.stopPropagation();
        navByKeyboard.current = true;
        if (searching) setSearchIndex(Math.min(searchActive + 1, searchResults.length - 1));
        else moveSel(1);
        break;
      case "ArrowUp":
        event.preventDefault();
        event.stopPropagation();
        navByKeyboard.current = true;
        if (searching) setSearchIndex(Math.max(searchActive - 1, 0));
        else moveSel(-1);
        break;
      case "ArrowRight":
        if (!searching) {
          event.preventDefault();
          event.stopPropagation();
          discloseRight();
        } else {
          event.stopPropagation();
        }
        break;
      case "ArrowLeft":
        if (!searching) {
          event.preventDefault();
          event.stopPropagation();
          collapseLeft();
        } else {
          event.stopPropagation();
        }
        break;
      case "Enter":
        event.preventDefault();
        event.stopPropagation();
        choose();
        break;
      case "Tab":
        event.preventDefault();
        event.stopPropagation();
        break;
      case "Escape":
        break;
      default:
        event.stopPropagation();
    }
  }
  function renderItem(item, entryIndex, j) {
    const isActive = nav.kind === "sub" && nav.entry === entryIndex && nav.item === j;
    return /* @__PURE__ */ jsxs3(
      "a",
      {
        id: `${uid}-e${entryIndex}s${j}`,
        "data-nav": `e${entryIndex}s${j}`,
        role: "menuitem",
        "aria-current": item.current ? "page" : void 0,
        href: item.href,
        ...GUARDED_NAV_PROPS,
        className: cn("adh-dropdown-menu__item", {
          "adh-nav-popover__item--active": isActive,
          "adh-nav-popover__item--current": item.current
        }),
        onMouseDown: (event) => event.preventDefault(),
        onMouseMove: () => {
          navByKeyboard.current = false;
          setNav({ kind: "sub", entry: entryIndex, item: j });
        },
        onClick: (event) => {
          if (isModifiedClick(event)) return;
          event.preventDefault();
          chooseItem(item);
        },
        children: [
          /* @__PURE__ */ jsx4(IconSlot, { icon: item.icon }),
          /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__link-name", children: item.label }),
          item.description && /* @__PURE__ */ jsx4("span", { className: "adh-dropdown-menu__shortcut", children: item.description })
        ]
      },
      `${item.key}-${entryIndex}-${j}`
    );
  }
  return (
    // Controlled so `close()` actually closes the menu — trailing controls and
    // the search command both close it programmatically before handing off.
    /* @__PURE__ */ jsxs3(DropdownMenu2, { open, onOpenChange: handleOpenChange, children: [
      /* @__PURE__ */ jsx4(
        DropdownMenuTrigger2,
        {
          className: cn("adh-header__title adh-nav-popover__trigger", triggerClassName),
          "aria-label": triggerLabel,
          children: triggerContent ?? /* @__PURE__ */ jsxs3(Fragment4, { children: [
            triggerIcon,
            /* @__PURE__ */ jsx4("span", { children: triggerText ?? triggerLabel }),
            /* @__PURE__ */ jsx4(ChevronDown2, { className: "adh-nav-popover__chevron", "aria-hidden": true })
          ] })
        }
      ),
      /* @__PURE__ */ jsxs3(
        DropdownMenuContent2,
        {
          align: "start",
          className: "adh-nav-popover__menu",
          onKeyDownCapture: closeOnShortcut,
          onMouseLeave: (event) => {
            const to = event.relatedTarget;
            if (to instanceof Element && to.closest('[role="menu"]')) return;
            setNav(
              (cur) => cur.kind === "top" && cur.open ? { kind: "top", entry: cur.entry, open: false } : cur
            );
          },
          finalFocus: () => {
            if (suppressFocusRestore.current) {
              suppressFocusRestore.current = false;
              return false;
            }
            return true;
          },
          children: [
            /* @__PURE__ */ jsxs3("div", { className: "adh-nav-popover__search", onMouseMove: leaveRows, children: [
              /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__prompt", "aria-hidden": true, children: ">" }),
              /* @__PURE__ */ jsx4(
                "input",
                {
                  ref: inputRef,
                  type: "text",
                  className: "adh-nav-popover__search-input",
                  placeholder,
                  "aria-label": placeholder,
                  role: "combobox",
                  "aria-expanded": true,
                  "aria-controls": `${uid}-list`,
                  "aria-activedescendant": activeId,
                  ...noAutofillProps,
                  spellCheck: false,
                  value: query,
                  onChange: (event) => {
                    navByKeyboard.current = true;
                    setQuery(event.target.value);
                    setSearchIndex(0);
                    setNav({ kind: "none" });
                  },
                  onKeyDown: handleInputKeyDown
                }
              ),
              commandTrailing?.({ close })
            ] }),
            /* @__PURE__ */ jsx4(DropdownMenuSeparator2, {}),
            /* @__PURE__ */ jsxs3("div", { id: `${uid}-list`, className: "adh-nav-popover__list", children: [
              !searching && entries.map((entry, index) => {
                const prev = entries[index - 1];
                const divider = prev !== void 0 && prev.section !== entry.section;
                const heading = prev === void 0 || prev.section !== entry.section ? sectionLabels?.[entry.section] : void 0;
                const sep = /* @__PURE__ */ jsxs3(Fragment4, { children: [
                  divider && /* @__PURE__ */ jsx4("div", { className: "adh-dropdown-menu__separator", role: "separator" }),
                  heading && /* @__PURE__ */ jsx4(DropdownMenuLabel, { className: "adh-nav-popover__section-label", children: heading })
                ] });
                if (entry.kind === "topic") {
                  return /* @__PURE__ */ jsxs3(Fragment3, { children: [
                    sep,
                    /* @__PURE__ */ jsxs3(
                      DropdownMenuSub,
                      {
                        open: index === disclosed,
                        onOpenChange: (next) => {
                          if (next) {
                            navByKeyboard.current = false;
                            setNav({ kind: "top", entry: index, open: true });
                          }
                        },
                        children: [
                          /* @__PURE__ */ jsxs3(
                            DropdownMenuSubTrigger,
                            {
                              render: entry.href !== void 0 ? /* @__PURE__ */ jsx4(
                                "a",
                                {
                                  href: entry.href,
                                  "aria-current": entry.current ? "page" : void 0,
                                  ...GUARDED_NAV_PROPS,
                                  onClick: (event) => {
                                    if (isModifiedClick(event)) return;
                                    event.preventDefault();
                                    chooseItem(topicItem(entry));
                                  }
                                }
                              ) : void 0,
                              id: `${uid}-e${index}`,
                              "data-nav": `e${index}`,
                              className: cn("adh-nav-popover__topic", {
                                "adh-nav-popover__item--active": nav.kind === "top" && nav.entry === index,
                                "adh-nav-popover__item--current": entry.current,
                                "adh-nav-popover__item--indent": entry.indent
                              }),
                              onMouseDown: (event) => event.preventDefault(),
                              onMouseMove: () => {
                                navByKeyboard.current = false;
                                setNav({ kind: "top", entry: index, open: true });
                              },
                              children: [
                                /* @__PURE__ */ jsx4(IconSlot, { icon: entry.icon }),
                                /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__link-name", children: entry.label }),
                                entry.description && /* @__PURE__ */ jsx4("span", { className: "adh-dropdown-menu__shortcut", children: entry.description })
                              ]
                            }
                          ),
                          /* @__PURE__ */ jsx4(DropdownMenuSubContent, { className: "adh-nav-popover__submenu", children: entry.items.map((item, j) => renderItem(item, index, j)) })
                        ]
                      }
                    )
                  ] }, `topic-${index}`);
                }
                const isActive = nav.kind === "top" && nav.entry === index;
                return /* @__PURE__ */ jsxs3(Fragment3, { children: [
                  sep,
                  /* @__PURE__ */ jsxs3(
                    "a",
                    {
                      id: `${uid}-e${index}`,
                      "data-nav": `e${index}`,
                      role: "menuitem",
                      "aria-current": entry.item.current ? "page" : void 0,
                      href: entry.item.href,
                      ...GUARDED_NAV_PROPS,
                      className: cn("adh-dropdown-menu__item", {
                        "adh-nav-popover__item--active": isActive,
                        "adh-nav-popover__item--current": entry.item.current,
                        "adh-nav-popover__item--indent": entry.indent
                      }),
                      onMouseDown: (event) => event.preventDefault(),
                      onMouseMove: () => {
                        navByKeyboard.current = false;
                        setNav({ kind: "top", entry: index, open: false });
                      },
                      onClick: (event) => {
                        if (isModifiedClick(event)) return;
                        event.preventDefault();
                        chooseItem(entry.item);
                      },
                      children: [
                        /* @__PURE__ */ jsx4(IconSlot, { icon: entry.item.icon }),
                        /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__link-name", children: entry.item.label }),
                        entry.blurb && entry.item.description && /* @__PURE__ */ jsx4("span", { className: "adh-dropdown-menu__shortcut", children: entry.item.description })
                      ]
                    }
                  )
                ] }, `leaf-${entry.item.key}`);
              }),
              searching && cmdActive && searchCommand && /* @__PURE__ */ jsxs3(
                "button",
                {
                  type: "button",
                  id: `${uid}-cmd`,
                  role: "menuitem",
                  className: "adh-dropdown-menu__item adh-nav-popover__item--active adh-nav-popover__help-row",
                  onMouseDown: (event) => event.preventDefault(),
                  onClick: selectCommand,
                  children: [
                    /* @__PURE__ */ jsx4("span", { children: searchCommand.label }),
                    searchCommand.shortcut && /* @__PURE__ */ jsx4("span", { className: "adh-dropdown-menu__shortcut", children: searchCommand.shortcut })
                  ]
                }
              ),
              searching && !cmdActive && searchResults.map((result, index) => {
                const { item, area } = result;
                const isActive = index === searchActive;
                return /* @__PURE__ */ jsxs3(
                  "a",
                  {
                    id: `${uid}-s${index}`,
                    "data-search": index,
                    role: "menuitem",
                    "aria-current": item.current ? "page" : void 0,
                    href: item.href,
                    ...GUARDED_NAV_PROPS,
                    className: cn("adh-dropdown-menu__item adh-nav-popover__match", {
                      "adh-nav-popover__item--active": isActive,
                      "adh-nav-popover__item--current": item.current
                    }),
                    onMouseDown: (event) => event.preventDefault(),
                    onMouseMove: () => {
                      navByKeyboard.current = false;
                      setSearchIndex(index);
                    },
                    onClick: (event) => {
                      if (isModifiedClick(event)) return;
                      event.preventDefault();
                      chooseItem(item);
                    },
                    children: [
                      /* @__PURE__ */ jsx4(IconSlot, { icon: item.icon }),
                      area && /* @__PURE__ */ jsxs3(Fragment4, { children: [
                        /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__area", children: area }),
                        /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__arrow", "aria-hidden": true, children: "\u2192" })
                      ] }),
                      /* @__PURE__ */ jsx4("span", { className: "adh-nav-popover__link-name", children: highlightMatch(item.label, query) }),
                      item.description && /* @__PURE__ */ jsx4("span", { className: "adh-dropdown-menu__shortcut", children: highlightMatch(item.description, query) })
                    ]
                  },
                  `${item.key}-${index}`
                );
              })
            ] }),
            searching && !cmdActive && searchResults.length === 0 && /* @__PURE__ */ jsx4(
              "p",
              {
                className: "adh-nav-popover__empty",
                role: "status",
                "aria-live": "polite",
                onMouseMove: leaveRows,
                children: emptyLabel
              }
            ),
            footer && /* @__PURE__ */ jsxs3(Fragment4, { children: [
              /* @__PURE__ */ jsx4(
                "div",
                {
                  className: "adh-dropdown-menu__separator",
                  role: "separator",
                  onMouseMove: leaveRows
                }
              ),
              /* @__PURE__ */ jsx4("div", { className: "adh-nav-popover__footer", onMouseMove: leaveRows, children: footer })
            ] })
          ]
        }
      )
    ] })
  );
}

// src/header/SiteOptionsMenu.tsx
import { Grid3x3 } from "lucide-react";

// src/components/ui/button.tsx
import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { jsx as jsx5 } from "react/jsx-runtime";
function joinClasses(...parts) {
  return parts.filter(Boolean).join(" ");
}
var Button = React.forwardRef(
  ({ className, variant = "default", size = "default", asChild = false, type, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return /* @__PURE__ */ jsx5(
      Comp,
      {
        className: joinClasses(
          "adh-button",
          `adh-button--${variant}`,
          `adh-button--size-${size}`,
          className
        ),
        ref,
        type: asChild ? type : type ?? "button",
        ...props
      }
    );
  }
);
Button.displayName = "Button";

// src/header/SiteOptionsMenu.tsx
import {
  DropdownMenu as DropdownMenu3,
  DropdownMenuTrigger as DropdownMenuTrigger3,
  DropdownMenuContent as DropdownMenuContent3,
  DropdownMenuLinkItem as DropdownMenuLinkItem2,
  DropdownMenuLabel as DropdownMenuLabel2,
  DropdownMenuSeparator as DropdownMenuSeparator3
} from "@agenticdevelopertoolkit/ui/components/dropdown-menu";
import { jsx as jsx6, jsxs as jsxs4 } from "react/jsx-runtime";
function SiteOptionsMenu({
  sites,
  triggerLabel = "Sites",
  groupLabel = "Sites"
}) {
  if (sites.length === 0) return null;
  return /* @__PURE__ */ jsxs4(DropdownMenu3, { children: [
    /* @__PURE__ */ jsxs4(
      DropdownMenuTrigger3,
      {
        render: /* @__PURE__ */ jsx6(Button, { variant: "ghost", size: "sm", "aria-label": triggerLabel }),
        children: [
          /* @__PURE__ */ jsx6(Grid3x3, { className: "adh-button__icon" }),
          /* @__PURE__ */ jsx6("span", { children: triggerLabel })
        ]
      }
    ),
    /* @__PURE__ */ jsxs4(DropdownMenuContent3, { align: "end", children: [
      /* @__PURE__ */ jsx6(DropdownMenuLabel2, { children: groupLabel }),
      /* @__PURE__ */ jsx6(DropdownMenuSeparator3, {}),
      sites.map((site) => (
        // LinkItem, not Item-wrapping-an-anchor: these are cross-SITE hrefs, so the
        // browser's own link semantics (middle-click, open-in-new-tab, status bar)
        // are the point, and LinkItem is the engine's way of keeping them.
        /* @__PURE__ */ jsxs4(DropdownMenuLinkItem2, { render: /* @__PURE__ */ jsx6("a", { href: site.href }), children: [
          /* @__PURE__ */ jsx6("span", { children: site.label }),
          site.description && /* @__PURE__ */ jsx6("span", { className: "adh-dropdown-menu__shortcut", children: site.description })
        ] }, site.href)
      ))
    ] })
  ] });
}

// src/header/SiteSwitcher.tsx
import { jsx as jsx7 } from "react/jsx-runtime";
function SiteSwitcher({
  siteName,
  siteNameHref = "/",
  sites = [],
  onSwitchSite
}) {
  if (sites.length === 0) {
    return /* @__PURE__ */ jsx7(Link3, { href: siteNameHref, className: "adh-header__title", children: siteName });
  }
  const entries = sites.map((site) => ({
    kind: "leaf",
    section: 0,
    item: {
      //  `id` is optional on the published `SiteLink` (its owner, SiteOptionsMenu,
      //  never reads it), so fall back to the href — unique among switch targets by
      //  construction, and a stable key either way.
      key: site.id ?? site.href,
      label: site.label,
      description: site.description,
      href: site.href
    }
  }));
  return /* @__PURE__ */ jsx7(
    NavigationPopover,
    {
      entries,
      triggerLabel: `${siteName} \u2014 switch site`,
      triggerText: siteName,
      triggerClassName: "adh-header__title",
      onChoose: (item) => {
        const href = onSwitchSite?.(item.key) ?? item.href;
        if (href) window.location.assign(href);
      }
    }
  );
}

// src/header/PreviewNotice.tsx
import { useEffect as useEffect3, useId as useId2, useRef as useRef2, useState as useState2 } from "react";
import { ChevronDown as ChevronDown3, TriangleAlert } from "lucide-react";
import { jsx as jsx8, jsxs as jsxs5 } from "react/jsx-runtime";
var DEFAULT_PREVIEW_NOTICE = "Developer Preview Release";
var DEFAULT_PREVIEW_DETAIL = "We are in very early stages, and are only taking requests to join.";
function PreviewNotice({
  notice = DEFAULT_PREVIEW_NOTICE,
  detail = DEFAULT_PREVIEW_DETAIL
}) {
  const [open, setOpen] = useState2(false);
  const panelId = useId2();
  const triggerRef = useRef2(null);
  useEffect3(() => {
    if (!open) return;
    const onClick = (e) => {
      if (triggerRef.current?.contains(e.target)) return;
      setOpen(false);
    };
    const onKeyDown = (e) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("click", onClick, true);
    document.addEventListener("keydown", onKeyDown, true);
    return () => {
      document.removeEventListener("click", onClick, true);
      document.removeEventListener("keydown", onKeyDown, true);
    };
  }, [open]);
  return /* @__PURE__ */ jsx8("div", { className: "adh-header__preview", children: /* @__PURE__ */ jsxs5("span", { className: "adh-header__preview-disclosure", onMouseLeave: () => setOpen(false), children: [
    /* @__PURE__ */ jsxs5(
      "button",
      {
        ref: triggerRef,
        type: "button",
        className: "adh-header__preview-trigger",
        "aria-expanded": open,
        "aria-controls": open ? panelId : void 0,
        onClick: () => setOpen((v) => !v),
        children: [
          /* @__PURE__ */ jsx8(TriangleAlert, { className: "adh-header__preview-icon", "aria-hidden": true }),
          /* @__PURE__ */ jsx8("span", { className: "adh-header__preview-text", children: notice }),
          /* @__PURE__ */ jsx8(TriangleAlert, { className: "adh-header__preview-icon", "aria-hidden": true }),
          /* @__PURE__ */ jsx8(ChevronDown3, { className: "adh-header__preview-caret", "aria-hidden": true })
        ]
      }
    ),
    open && /* @__PURE__ */ jsx8("span", { className: "adh-header__preview-panel", id: panelId, children: detail })
  ] }) });
}

// src/header/AdhHeader.tsx
import { Badge } from "@agenticdevelopertoolkit/ui/components/badge";
import { HelpEnabled } from "@agenticdevelopertoolkit/ui/components/help-enabled";
import { jsx as jsx9, jsxs as jsxs6 } from "react/jsx-runtime";
function AdhHeader({
  siteName,
  siteNameHref = "/",
  sites,
  onSwitchSite,
  siteSwitcher,
  debugMenu,
  pageTitle,
  pageTitleHelp,
  pageTitleHelpFallback,
  center,
  badges = [],
  leadingActions,
  navLinks = [],
  trailingNavLinks = [],
  preAuthLinks,
  accountActions,
  homeHref,
  profileHref,
  onDebugOptions,
  debugOptionsHint,
  previewNotice,
  previewDetail,
  user,
  authLoading = false,
  loginHref,
  signupHref,
  onLogin,
  onSignup,
  onLogout,
  settingsHref,
  onSettings
}) {
  const barLinks = siteSwitcher ? navLinks : navLinks.filter((l) => l.href !== siteNameHref);
  return /* @__PURE__ */ jsxs6("header", { className: "adh-header", role: "banner", children: [
    /* @__PURE__ */ jsx9(PreviewNotice, { notice: previewNotice, detail: previewDetail }),
    /* @__PURE__ */ jsxs6("div", { className: "adh-header__container", children: [
      /* @__PURE__ */ jsxs6("div", { className: "adh-header__lead", children: [
        /* @__PURE__ */ jsxs6("div", { className: "adh-header__brand-row", children: [
          siteSwitcher ?? /* @__PURE__ */ jsx9(
            SiteSwitcher,
            {
              siteName,
              siteNameHref,
              sites,
              onSwitchSite
            }
          ),
          debugMenu
        ] }),
        badges.length > 0 && /* @__PURE__ */ jsx9("span", { className: "adh-header__badges", "aria-hidden": "true", children: badges.map((badge) => (
          // The ui Badge owns the skin; the adh-header__badge* classes stay
          // as stable hooks — they're a theme-editor surface.
          /* @__PURE__ */ jsx9(
            Badge,
            {
              variant: badge.tone ?? "neutral",
              className: badge.tone ? `adh-header__badge adh-header__badge--${badge.tone}` : "adh-header__badge",
              children: badge.label
            },
            badge.label
          )
        )) })
      ] }),
      center ? /* @__PURE__ */ jsx9("div", { className: "adh-header__center", children: center }) : pageTitle && (pageTitleHelp ? (
        // The TRIGGER carries the title class, rather than wrapping a span that
        // has it: `.adh-header__page-title` is absolutely centred and sets
        // `pointer-events: none`, so a button around it would be both mispositioned
        // and unclickable over the text. The inner span exists to keep the
        // ellipsis, which a flex item cannot do for itself.
        /* @__PURE__ */ jsx9(
          HelpEnabled,
          {
            id: pageTitleHelp,
            fallback: pageTitleHelpFallback,
            className: "adh-header__page-title adh-header__page-title--help",
            children: /* @__PURE__ */ jsx9("span", { className: "adh-header__page-title-text", children: pageTitle })
          }
        )
      ) : /* @__PURE__ */ jsx9("span", { className: "adh-header__page-title", children: pageTitle })),
      /* @__PURE__ */ jsxs6("nav", { className: "adh-header__nav", "aria-label": "Primary", children: [
        leadingActions && /* @__PURE__ */ jsx9("span", { className: "adh-header__actions", children: leadingActions }),
        barLinks.length > 0 && /* @__PURE__ */ jsx9("span", { className: "adh-header__links", children: barLinks.map((link) => /* @__PURE__ */ jsx9(NavLinkItem, { link }, link.href + link.label)) }),
        preAuthLinks,
        accountActions,
        authLoading && !user ? /* @__PURE__ */ jsx9(
          "span",
          {
            className: "adh-header__auth-spinner",
            role: "status",
            "aria-label": "Checking sign-in"
          }
        ) : user ? /* @__PURE__ */ jsx9(
          AvatarMenu,
          {
            user,
            homeHref,
            profileHref,
            onLogout,
            settingsHref,
            onSettings,
            onDebugOptions,
            debugOptionsHint
          }
        ) : /* @__PURE__ */ jsx9(
          AuthButtons,
          {
            loginHref,
            signupHref,
            onLogin,
            onSignup
          }
        ),
        trailingNavLinks.map((link) => /* @__PURE__ */ jsx9(NavLinkItem, { link }, link.href + link.label))
      ] })
    ] })
  ] });
}

// src/footer/AdhFooter.tsx
import Link4 from "next/link";
import { jsx as jsx10, jsxs as jsxs7 } from "react/jsx-runtime";
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
  return /* @__PURE__ */ jsxs7("span", { className: ["adh-footer__menu-host", className].filter(Boolean).join(" "), style: anchor, children: [
    /* @__PURE__ */ jsx10(
      "button",
      {
        type: "button",
        popoverTarget: id,
        "aria-label": ariaLabel,
        "aria-haspopup": "menu",
        className: `${triggerClassName} adh-footer__menu-trigger`,
        children: label
      }
    ),
    /* @__PURE__ */ jsx10("div", { id, popover: "auto", className: "adh-footer__menu", children: /* @__PURE__ */ jsx10("ul", { className: "adh-footer__menu-list", children: items.map((item) => /* @__PURE__ */ jsx10("li", { children: "popoverTarget" in item ? /* @__PURE__ */ jsx10(
      "button",
      {
        type: "button",
        popoverTarget: item.popoverTarget,
        "aria-label": item.ariaLabel,
        className: menuItemClass("adh-footer__menu-item"),
        onClick: (e) => closeContainingMenu(e.currentTarget),
        children: item.label
      }
    ) : /* @__PURE__ */ jsx10(
      Link4,
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
  return /* @__PURE__ */ jsxs7("footer", { className: "adh-footer", role: "contentinfo", children: [
    /* @__PURE__ */ jsxs7("div", { className: "adh-footer__container", children: [
      copyright && /* @__PURE__ */ jsx10("span", { className: "adh-footer__copyright", children: copyright }),
      links.length > 0 && /* @__PURE__ */ jsx10("nav", { className: "adh-footer__links", "aria-label": "Footer", children: links.map(
        (link) => "menuId" in link ? /* @__PURE__ */ jsx10(
          FooterMenu,
          {
            id: link.menuId,
            label: link.label,
            items: link.items,
            ariaLabel: link.ariaLabel,
            className: link.className
          },
          `menu:${link.menuId}`
        ) : "popoverTarget" in link ? /* @__PURE__ */ jsx10(
          "button",
          {
            type: "button",
            popoverTarget: link.popoverTarget,
            "aria-label": link.ariaLabel,
            className: ["adh-footer__link adh-footer__sites-trigger", link.className].filter(Boolean).join(" "),
            children: link.label
          },
          `popover:${link.popoverTarget}`
        ) : /* @__PURE__ */ jsx10(
          Link4,
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

// src/themes/adh-themes.ts
var ADH_THEME_COOKIE = "adh-theme";
var BASE_CUT_ALIASES = ["adh-iosevka"];
var isBaseCutAlias = (key) => BASE_CUT_ALIASES.includes(key);
var ADH_THEMES = [
  { key: "adh", label: "ADH" },
  { key: "adh-iosevka", label: "Iosevka" },
  { key: "adh-manrope", label: "Manrope" },
  { key: "adh-courier", label: "Courier" },
  { key: "adh-comic", label: "Comic" },
  { key: "adh-jetbrains", label: "JetBrains" },
  { key: "adh-fira", label: "Fira" }
].filter((t) => !isBaseCutAlias(t.key));
var DEFAULT_ADH_THEME = "adh";
var BASE_FACE_THEMES = [
  DEFAULT_ADH_THEME,
  ...BASE_CUT_ALIASES,
  "charcoal",
  "fishlamp"
];
export {
  ADH_THEMES,
  ADH_THEME_COOKIE,
  AdhFooter,
  AdhHeader,
  AuthButtons,
  AvatarMenu,
  DEFAULT_ADH_THEME,
  NavLinkItem,
  SiteOptionsMenu
};
//# sourceMappingURL=index.js.map