'use client'

// src/theme-editor/areas.tsx
import {
  SiteHeader,
  SiteMenuSwitcher,
  WorkspacesMenuProvider,
  useWorkspacesMenu
} from "@agentic-toolkit/adh/header";
import { SiteFooter } from "@agentic-toolkit/adh/footer";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";
import {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter
} from "@agenticdevelopertoolkit/ui/components/card";
import { Input } from "@agenticdevelopertoolkit/ui/components/input";
import { jsx, jsxs } from "react/jsx-runtime";
var usePreviewHeaderAuth = () => ({
  user: { name: "Ada Lovelace", email: "ada@example.com" },
  onLogout: () => {
  }
});
var PREVIEW_WORKSPACES = {
  workspaces: [
    { id: "preview:ada", label: "Ada Lovelace", href: "#", current: true },
    { id: "preview:engine", label: "Analytical Engine", href: "#" }
  ],
  loading: false,
  select: () => {
  }
};
function HeaderPreview() {
  const header = /* @__PURE__ */ jsx(
    SiteHeader,
    {
      siteId: "hub",
      navLinks: [
        { label: "Docs", href: "#docs" },
        { label: "Pricing", href: "#pricing" }
      ],
      trailingNavLinks: [{ label: "Blog", href: "#blog" }],
      useAuthSource: usePreviewHeaderAuth,
      onSettings: () => {
      }
    }
  );
  const pageHasWorkspaces = useWorkspacesMenu() != null;
  return pageHasWorkspaces ? /* @__PURE__ */ jsx(WorkspacesMenuProvider, { value: PREVIEW_WORKSPACES, children: header }) : header;
}
function FooterPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "tep-preview", children: [
    /* @__PURE__ */ jsx("style", { children: `.tep-preview .adh-theme-switcher { display: none; }` }),
    /* @__PURE__ */ jsx(
      SiteFooter,
      {
        specimen: true,
        links: [
          { label: "GitHub", href: "#" },
          { label: "Status", href: "#" }
        ]
      }
    )
  ] });
}
function SiteMenuPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "flex items-center gap-3 p-5", children: [
    /* @__PURE__ */ jsx(SiteMenuSwitcher, { currentSiteId: "hub" }),
    /* @__PURE__ */ jsx("span", { className: "font-mono text-xs text-apt-text-dim", children: "\u2190 click to open the menu" })
  ] });
}
function GlobalPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "space-y-3 p-6", children: [
    /* @__PURE__ */ jsx("h1", { className: "text-headline-large", children: "The quick brown fox" }),
    /* @__PURE__ */ jsxs("p", { className: "text-body-large", children: [
      "Body copy in the base font.",
      " ",
      /* @__PURE__ */ jsx("a", { href: "#", className: "text-apt-gold underline", children: "an inline link" }),
      ", some ",
      /* @__PURE__ */ jsx("mark", { children: "highlighted" }),
      " text, and a sentence you can select to preview the selection style."
    ] }),
    /* @__PURE__ */ jsx("p", { className: "font-mono text-sm text-apt-text-muted", children: "Monospace \u2014 code & labels." })
  ] });
}
function MarketingPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "tep-marketing space-y-4 p-8 text-center", children: [
    /* @__PURE__ */ jsx("h1", { className: "text-display-small", children: "Build agentic software, faster." }),
    /* @__PURE__ */ jsx("p", { className: "text-body-large text-apt-text-muted", children: "A representative marketing hero (the real landing carries its own classes)." }),
    /* @__PURE__ */ jsx(Button, { children: "Get started" })
  ] });
}
function ComponentsPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "space-y-4 p-6", children: [
    /* @__PURE__ */ jsxs("div", { className: "flex flex-wrap gap-2", children: [
      /* @__PURE__ */ jsx(Button, { children: "Primary" }),
      /* @__PURE__ */ jsx(Button, { variant: "outline", children: "Outline" }),
      /* @__PURE__ */ jsx(Button, { variant: "ghost", children: "Ghost" }),
      /* @__PURE__ */ jsx(Button, { variant: "destructive", children: "Delete" })
    ] }),
    /* @__PURE__ */ jsx(Input, { placeholder: "An input field" }),
    /* @__PURE__ */ jsxs(Card, { className: "max-w-sm", children: [
      /* @__PURE__ */ jsxs(CardHeader, { children: [
        /* @__PURE__ */ jsx(CardTitle, { children: "Card title" }),
        /* @__PURE__ */ jsx(CardDescription, { children: "A short description of the card." })
      ] }),
      /* @__PURE__ */ jsx(CardContent, { children: "Card body content." }),
      /* @__PURE__ */ jsx(CardFooter, { children: /* @__PURE__ */ jsx(Button, { size: "sm", children: "Action" }) })
    ] })
  ] });
}
function TypePreview() {
  return /* @__PURE__ */ jsxs("div", { className: "space-y-3 p-6", children: [
    /* @__PURE__ */ jsx("p", { className: "text-display-small", children: "Display" }),
    /* @__PURE__ */ jsx("p", { className: "text-headline-large", children: "Headline" }),
    /* @__PURE__ */ jsx("p", { className: "text-title-large", children: "Title" }),
    /* @__PURE__ */ jsx("p", { className: "text-body-large", children: "Body text \u2014 the quick brown fox jumps over the lazy dog." }),
    /* @__PURE__ */ jsx("p", { className: "text-label-large", children: "Label" }),
    /* @__PURE__ */ jsx("p", { className: "text-code", children: "const code = true" })
  ] });
}
function CustomPreview() {
  return /* @__PURE__ */ jsxs("div", { className: "space-y-2 p-6 font-mono text-[0.8rem] text-apt-text-muted", children: [
    /* @__PURE__ */ jsx("p", { className: "text-apt-text", children: "Free-form CSS \u2014 any selector, any property." }),
    /* @__PURE__ */ jsx("p", { children: "It is concatenated into the live stylesheet and applies across the whole site, so you can target anything the curated sections don't cover." }),
    /* @__PURE__ */ jsx("p", { className: "pt-1 text-apt-text-dim", children: "Examples:" }),
    /* @__PURE__ */ jsx("pre", { className: "overflow-x-auto rounded bg-apt-bg p-2 text-apt-text-dim", children: `:root { --type-headline-large-size: 2.5rem; }
.landing-page .adh-header__title { color: #fff; }
[data-slot="button"] { letter-spacing: 0.04em; }` })
  ] });
}
var typeVars = (scale, steps) => steps.flatMap((s) => [
  `--type-${scale}-${s}-size`,
  `--type-${scale}-${s}-line-height`,
  `--type-${scale}-${s}-weight`
]);
var THEME_AREAS = [
  {
    id: "global",
    label: "Global",
    Preview: GlobalPreview,
    items: [
      // — Base & color —
      {
        id: "global.base",
        label: "Base text",
        selector: ":root",
        vars: ["--font-sans", "--font-serif", "--font-mono", "--color-surface", "--color-on-surface"],
        hint: "Base fonts & background \u2014 cascade everywhere"
      },
      {
        id: "global.brand-colors",
        label: "Brand colors",
        selector: ":root",
        vars: [
          "--color-primary",
          "--color-primary-bright",
          "--color-on-primary",
          "--color-secondary",
          "--color-tertiary",
          "--color-error",
          "--color-success",
          "--color-warning"
        ]
      },
      {
        id: "global.surfaces",
        label: "Surfaces & text",
        selector: ":root",
        vars: [
          "--color-surface",
          "--color-surface-container",
          "--color-surface-container-high",
          "--color-on-surface",
          "--color-on-surface-variant",
          "--color-text-dim",
          "--color-outline"
        ]
      },
      { id: "global.links", label: "Links", selector: "a", props: ["color", "text-decoration-line"] },
      {
        id: "global.selection",
        label: "Selection / highlight",
        selector: "::selection",
        defaultCss: "::selection {\n  background: var(--color-accent-dim);\n  color: var(--color-accent);\n}\n"
      },
      // — Header —
      {
        id: "global.header-bar",
        label: "Header bar",
        selector: ".adh-header",
        props: ["background-color", "border-bottom-color", "box-shadow"],
        Preview: HeaderPreview
      },
      {
        id: "global.header-title",
        label: "Header title",
        selector: ".adh-header__title",
        props: ["color", "font-family", "font-size", "font-weight", "font-style", "letter-spacing"],
        Preview: HeaderPreview
      },
      {
        id: "global.header-nav",
        label: "Header nav links",
        selector: ".adh-header__nav-link",
        props: ["color", "font-family", "font-size", "letter-spacing", "text-transform"],
        Preview: HeaderPreview
      },
      {
        id: "global.header-badges",
        label: "Header badges",
        selector: ".adh-header__badge",
        props: ["color", "background-color", "border-color", "border-radius", "font-size"],
        Preview: HeaderPreview
      },
      {
        id: "global.auth-menu",
        label: "Authenticated menu",
        selector: ".adh-avatar-menu-trigger",
        props: ["color", "background-color", "border-color", "border-radius"],
        Preview: HeaderPreview
      },
      // — Footer —
      {
        id: "global.footer-bar",
        label: "Footer bar",
        selector: ".adh-footer",
        props: ["background-color", "border-top-color", "color"],
        Preview: FooterPreview
      },
      {
        id: "global.footer-text",
        label: "Footer text",
        selector: ".adh-footer__copyright",
        props: ["color", "font-family", "font-size", "letter-spacing"],
        Preview: FooterPreview
      },
      {
        id: "global.footer-links",
        label: "Footer links",
        selector: ".adh-footer__link",
        props: ["color", "font-family", "font-size"],
        Preview: FooterPreview
      },
      {
        id: "global.footer-brand",
        label: "Footer brand",
        selector: ".adh-footer__brand-link",
        props: ["color", "font-weight"],
        Preview: FooterPreview
      },
      // — Site menu —
      {
        id: "global.menu-trigger",
        label: "Site-menu trigger",
        selector: ".adh-nav-popover__trigger",
        props: ["color", "font-family", "font-size"],
        Preview: SiteMenuPreview
      },
      {
        id: "global.menu-items",
        label: "Site-menu items",
        selector: ".adh-dropdown-menu__item",
        defaultCss: ".adh-dropdown-menu__item {\n  color: var(--color-text-primary);\n  font-family: var(--font-mono);\n}\n",
        Preview: SiteMenuPreview
      },
      // — Shared components —
      {
        id: "global.buttons",
        label: "Buttons",
        selector: '[data-slot="button"]',
        props: ["color", "background-color", "border-radius", "font-weight", "padding"],
        Preview: ComponentsPreview
      },
      {
        id: "global.cards",
        label: "Cards",
        selector: '[data-slot="card"]',
        props: ["background-color", "border-color", "border-radius", "color"],
        Preview: ComponentsPreview
      },
      {
        id: "global.inputs",
        label: "Inputs",
        selector: '[data-slot="input"]',
        props: ["background-color", "border-color", "border-radius", "color", "height"],
        Preview: ComponentsPreview
      }
    ]
  },
  {
    id: "type",
    label: "Typography",
    Preview: TypePreview,
    items: [
      { id: "type.display", label: "Display", selector: ":root", vars: typeVars("display", ["large", "medium", "small"]) },
      { id: "type.headline", label: "Headline", selector: ":root", vars: typeVars("headline", ["large", "medium", "small"]) },
      { id: "type.title", label: "Title", selector: ":root", vars: typeVars("title", ["large", "medium", "small"]) },
      { id: "type.body", label: "Body", selector: ":root", vars: typeVars("body", ["large", "medium", "small"]) },
      { id: "type.label", label: "Label", selector: ":root", vars: typeVars("label", ["large", "medium", "small"]) },
      { id: "type.code", label: "Code", selector: ":root", vars: ["--type-code-size", "--type-code-line-height", "--type-code-weight"] }
    ]
  },
  {
    id: "marketing",
    label: "Marketing landing",
    Preview: MarketingPreview,
    items: [
      { id: "marketing.hero", label: "Hero heading", selector: ".tep-marketing h1", props: ["color", "font-family", "font-size", "font-weight"] },
      { id: "marketing.cta", label: "Call to action", selector: '.tep-marketing [data-slot="button"]', props: ["color", "background-color", "border-radius"] }
    ]
  },
  {
    id: "custom",
    label: "Custom CSS",
    Preview: CustomPreview,
    items: [
      {
        id: "custom.css",
        label: "Custom CSS",
        selector: "",
        defaultCss: "/* Free-form CSS \u2014 any selector, any property. Applies across the whole site.\n   Examples:\n     :root { --type-headline-large-size: 2.5rem; }\n     .landing-page .adh-header__title { color: #fff; }\n*/\n"
      }
    ]
  }
];
function readItemCss(item, scope) {
  const fallback = item.defaultCss ?? `${item.selector} {
  
}
`;
  if (typeof document === "undefined") return fallback;
  const fmt = (decls) => decls.length ? `${item.selector} {
${decls.map((d) => `  ${d}`).join("\n")}
}
` : fallback;
  if (item.vars?.length) {
    const cs = getComputedStyle(document.documentElement);
    return fmt(
      item.vars.map((v) => [v, cs.getPropertyValue(v).trim()]).filter(([, val]) => val).map(([v, val]) => `${v}: ${val};`)
    );
  }
  if (item.props?.length) {
    let el = null;
    try {
      el = (scope ?? document).querySelector(item.selector) ?? document.querySelector(item.selector);
    } catch {
      el = null;
    }
    if (el) {
      const cs = getComputedStyle(el);
      return fmt(
        item.props.map((p) => [p, cs.getPropertyValue(p).trim()]).filter(([, val]) => val).map(([p, val]) => `${p}: ${val};`)
      );
    }
  }
  return fallback;
}

// src/theme-editor/CssEditor.tsx
import { useRef } from "react";
import Editor from "@monaco-editor/react";
import { Button as Button2 } from "@agenticdevelopertoolkit/ui/components/button";
import { jsx as jsx2, jsxs as jsxs2 } from "react/jsx-runtime";
function CssEditor({
  value,
  onChange,
  height = 280
}) {
  const editorRef = useRef(null);
  const beforeMount = (monaco) => {
    monaco.editor.defineTheme("adh-dark", {
      base: "vs-dark",
      inherit: true,
      rules: [],
      // Match --color-surface so the editor blends into the pane.
      colors: { "editor.background": "#0c0c0f" }
    });
  };
  const onMount = (editor) => {
    editorRef.current = editor;
  };
  const format = () => {
    void editorRef.current?.getAction("editor.action.formatDocument")?.run();
  };
  return /* @__PURE__ */ jsxs2("div", { className: "overflow-hidden rounded-lg border border-apt-border", children: [
    /* @__PURE__ */ jsxs2("div", { className: "flex items-center justify-between border-b border-apt-border bg-apt-bg px-2.5 py-1", children: [
      /* @__PURE__ */ jsx2("span", { className: "font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted", children: "CSS" }),
      /* @__PURE__ */ jsx2(Button2, { variant: "ghost", size: "sm", onClick: format, className: "font-mono text-xs", children: "Format" })
    ] }),
    /* @__PURE__ */ jsx2(
      Editor,
      {
        height,
        language: "css",
        theme: "adh-dark",
        value,
        onChange: (v) => onChange(v ?? ""),
        beforeMount,
        onMount,
        options: {
          minimap: { enabled: false },
          fontSize: 13,
          lineNumbers: "off",
          folding: false,
          scrollBeyondLastLine: false,
          automaticLayout: true,
          tabSize: 2,
          wordWrap: "on",
          padding: { top: 8, bottom: 8 },
          renderLineHighlight: "none",
          overviewRulerLanes: 0
        },
        loading: /* @__PURE__ */ jsx2("div", { className: "p-3 font-mono text-xs text-apt-text-dim", children: "Loading editor\u2026" })
      }
    )
  ] });
}

// src/theme-editor/surface.ts
var ITEMS_BY_ID = new Map(THEME_AREAS.flatMap((area) => area.items).map((item) => [item.id, item]));
var themeAreasSurface = {
  areas: THEME_AREAS,
  readItemCss: (itemId, scope) => {
    const item = ITEMS_BY_ID.get(itemId);
    return item ? readItemCss(item, scope) : "";
  },
  CssEditor
};
export {
  CssEditor,
  THEME_AREAS,
  readItemCss,
  themeAreasSurface
};
//# sourceMappingURL=index.js.map