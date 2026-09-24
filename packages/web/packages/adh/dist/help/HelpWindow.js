'use client'

"use client";

// src/help/HelpWindow.tsx
import { useMemo } from "react";
import { HierarchicalDetailView } from "@agenticdevelopertoolkit/ui/blocks";
import { EmptyState } from "@agenticdevelopertoolkit/ui/components/empty-state";
import { FloatingWindow } from "@agentic-toolkit/adh/debug-env";

// src/help/topics.ts
var HELP_TOPICS = [
  {
    id: "chat",
    label: "Chat",
    slug: "chat",
    description: "Ask bitbag anything about building on the Agentic Developer Hub.",
    view: "chat"
  },
  {
    // Placeholder section: no guide content of its own (the old walkthrough was stale and was
    // removed) — selecting it opens OAuth beneath, so its landing is the children overview, exactly
    // like Reference. Give it a `contentKey` again when a real quickstart guide is written.
    id: "quickstart",
    label: "Quickstart",
    slug: "quickstart",
    description: "Register an app, get a token, and make your first call.",
    children: [
      {
        id: "oauth",
        label: "OAuth",
        slug: "quickstart/oauth",
        description: "Authorize on behalf of a user with the OAuth 2.0 flow.",
        children: [
          { id: "oauth-overview", label: "Overview", slug: "quickstart/oauth/overview", description: "How the flow fits together.", contentKey: "oauth-overview" },
          { id: "oauth-register-app", label: "Register app", slug: "quickstart/oauth/register-app", description: "Create OAuth credentials.", contentKey: "oauth-register-app" },
          { id: "oauth-authorize", label: "Authorize", slug: "quickstart/oauth/authorize", description: "Send the user to consent.", contentKey: "oauth-authorize" },
          { id: "oauth-token-exchange", label: "Token exchange", slug: "quickstart/oauth/token-exchange", description: "Trade the code for tokens.", contentKey: "oauth-token-exchange" },
          { id: "oauth-refresh", label: "Refresh", slug: "quickstart/oauth/refresh", description: "Keep the session alive.", contentKey: "oauth-refresh" }
        ]
      }
    ]
  },
  {
    id: "reference",
    label: "Reference",
    slug: "reference",
    description: "Error codes, webhooks, and what changed.",
    children: [
      { id: "errors", label: "Errors", slug: "reference/errors", description: "Error codes and what they mean.", contentKey: "errors" },
      { id: "webhooks", label: "Webhooks", slug: "reference/webhooks", description: "Events the hub can push to you.", contentKey: "webhooks" },
      { id: "changelog", label: "Changelog", slug: "reference/changelog", description: "Recent API changes.", contentKey: "changelog" }
    ]
  },
  {
    id: "rest-api",
    label: "REST API",
    slug: "rest-api",
    description: "Browse every REST endpoint and try calls against your session.",
    view: "api"
  },
  {
    // A section, not a monolithic page: the old single mcp.md split into per-concern child topics.
    // Unlike Quickstart and Reference it does NOT land on the children's select nudge: /mcp is the
    // published address of the MCP docs (the MCP host's root redirects a browser here, as do three
    // `/docs/mcp` redirects), so arriving there must read as documentation, not as a menu. The
    // `landingChildId` auto-selects Overview — the reader lands on prose with the siblings beside it.
    id: "mcp",
    label: "MCP",
    slug: "mcp",
    description: "Connect an agent to the hub over the Model Context Protocol.",
    landingChildId: "mcp-overview",
    children: [
      { id: "mcp-overview", label: "Overview", slug: "mcp/overview", description: "What the MCP server is, and how it relates to the REST API.", contentKey: "mcp-overview" },
      { id: "mcp-connect", label: "Connect a client", slug: "mcp/connect", description: "Point Claude Desktop, Claude Code, Cursor, or the Inspector at the server.", contentKey: "mcp-connect" },
      { id: "mcp-tools", label: "Tools", slug: "mcp/tools", description: "Every tool the server exposes, grouped by area.", contentKey: "mcp-tools" },
      { id: "mcp-details", label: "Details", slug: "mcp/details", description: "Transport, auth, session, and data-scope facts.", contentKey: "mcp-details" }
    ]
  },
  {
    // Same split as MCP: the old hub-features.md's H2 sections are now child topics, one per
    // feature area, so /hub lands on the children level's select nudge with those children in the
    // rail beside it — the same landing Quickstart, Reference and MCP get.
    id: "hub",
    label: "Hub Features",
    slug: "hub",
    description: "What you can do across the Agentic Developer Hub.",
    children: [
      { id: "hub-overview", label: "Overview", slug: "hub/overview", description: "How workspaces scope everything you do in the Hub.", contentKey: "hub-overview" },
      { id: "hub-workspaces", label: "Workspaces & account", slug: "hub/workspaces", description: "Workspaces, settings, members, and API tokens.", contentKey: "hub-workspaces" },
      { id: "hub-personas", label: "Personas", slug: "hub/personas", description: "Design, register, and run AI personas.", contentKey: "hub-personas" },
      { id: "hub-products", label: "Products", slug: "hub/products", description: "Ecosystems: apps, tokens, customers, flags, and gamification.", contentKey: "hub-products" },
      { id: "hub-storage", label: "Storage & data", slug: "hub/storage", description: "Buckets, files, access, and data integrations.", contentKey: "hub-storage" },
      { id: "hub-plan", label: "Plan", slug: "hub/plan", description: "Projects, narratives, and research.", contentKey: "hub-plan" },
      { id: "hub-teams", label: "Teams", slug: "hub/teams", description: "Member teams, the team registry, and the team builder.", contentKey: "hub-teams" },
      { id: "hub-community", label: "Community & support", slug: "hub/community", description: "Discussions, support, news, and messaging.", contentKey: "hub-community" },
      { id: "hub-monitoring", label: "Monitoring", slug: "hub/monitoring", description: "Dashboards that watch your sites and endpoints.", contentKey: "hub-monitoring" },
      { id: "hub-apis", label: "APIs & agents", slug: "hub/apis", description: "The REST API, MCP, OAuth, and reusable tools.", contentKey: "hub-apis" }
    ]
  }
];
function flattenTopics(topics = HELP_TOPICS) {
  return topics.flatMap((t) => [t, ...t.children ? flattenTopics(t.children) : []]);
}
function topicBySlug(slug) {
  return flattenTopics().find((t) => t.slug === slug);
}
function buildTopicLevels(path) {
  const levels = [];
  let siblings = HELP_TOPICS;
  let title = "Help";
  let parentId = null;
  let landing;
  let activeTopic = null;
  for (let depth = 0; ; depth++) {
    const selId = path[depth] ?? (landing != null && siblings.some((t) => t.id === landing) ? landing : null);
    levels.push({
      parentId,
      title,
      items: siblings.map((t) => ({ id: t.id, label: t.label, description: t.description, slug: t.slug })),
      selectedId: selId
    });
    if (selId == null) break;
    const node = siblings.find((t) => t.id === selId) ?? null;
    if (!node) break;
    activeTopic = node;
    if (node.children && node.children.length > 0) {
      siblings = node.children;
      title = node.label;
      parentId = node.id;
      landing = node.landingChildId;
      continue;
    }
    break;
  }
  return { levels, activeTopic };
}

// src/help/topic-icons.tsx
import {
  AppWindow,
  ArrowLeftRight,
  Bot,
  Braces,
  FileText,
  Handshake,
  History,
  LayoutGrid,
  Library,
  Plug,
  RefreshCw,
  Rocket,
  Route,
  TriangleAlert,
  UserCheck,
  Webhook
} from "lucide-react";
import { jsx } from "react/jsx-runtime";
var TOPIC_ICON = {
  chat: /* @__PURE__ */ jsx(Bot, { size: 16, "aria-hidden": true }),
  quickstart: /* @__PURE__ */ jsx(Rocket, { size: 16, "aria-hidden": true }),
  oauth: /* @__PURE__ */ jsx(Handshake, { size: 16, "aria-hidden": true }),
  "oauth-overview": /* @__PURE__ */ jsx(Route, { size: 16, "aria-hidden": true }),
  "oauth-register-app": /* @__PURE__ */ jsx(AppWindow, { size: 16, "aria-hidden": true }),
  "oauth-authorize": /* @__PURE__ */ jsx(UserCheck, { size: 16, "aria-hidden": true }),
  "oauth-token-exchange": /* @__PURE__ */ jsx(ArrowLeftRight, { size: 16, "aria-hidden": true }),
  "oauth-refresh": /* @__PURE__ */ jsx(RefreshCw, { size: 16, "aria-hidden": true }),
  reference: /* @__PURE__ */ jsx(Library, { size: 16, "aria-hidden": true }),
  errors: /* @__PURE__ */ jsx(TriangleAlert, { size: 16, "aria-hidden": true }),
  webhooks: /* @__PURE__ */ jsx(Webhook, { size: 16, "aria-hidden": true }),
  changelog: /* @__PURE__ */ jsx(History, { size: 16, "aria-hidden": true }),
  "rest-api": /* @__PURE__ */ jsx(Braces, { size: 16, "aria-hidden": true }),
  mcp: /* @__PURE__ */ jsx(Plug, { size: 16, "aria-hidden": true }),
  hub: /* @__PURE__ */ jsx(LayoutGrid, { size: 16, "aria-hidden": true })
};
function topicIcon(id) {
  return TOPIC_ICON[id] ?? /* @__PURE__ */ jsx(FileText, { size: 16, "aria-hidden": true });
}

// src/help/views/MarkdownTopic.tsx
import { isModifiedClick } from "@agenticdevelopertoolkit/ui/lib/navigation-guard";
import { useHelp } from "@agentic-toolkit/adh/help";

// src/docs/MarkdownHtml.tsx
import { jsx as jsx2 } from "react/jsx-runtime";
function MarkdownHtml({ html, className }) {
  return /* @__PURE__ */ jsx2(
    "div",
    {
      className: className ? `adh-mv-prose ${className}` : "adh-mv-prose",
      dangerouslySetInnerHTML: { __html: html }
    }
  );
}

// src/help/content.generated.ts
var HELP_CONTENT_HTML = {
  "changelog": `<h1 id="changelog"><a href="#changelog">Changelog</a></h1>
<p>This page lists user-visible changes to the Agentic Developer Hub API.
Internal refactors that don't affect callers are omitted.</p>
<h2 id="unreleased"><a href="#unreleased">Unreleased</a></h2>
<p><em>The public API is pre-1.0. Breaking changes will be called out here as they
land. Endpoint schemas are the source of truth \u2014 see the
<a href="https://api.agenticdeveloperhub.com">API reference</a>.</em></p>`,
  "errors": `<h1 id="errors"><a href="#errors">Errors</a></h1>
<p>The API returns JSON error responses with a consistent shape. The HTTP
status code is the primary signal; the body provides a machine-readable
<code>code</code> and a human-readable <code>message</code>.</p>
<h2 id="response-shape"><a href="#response-shape">Response shape</a></h2>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">{</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "code"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"validation_error"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "message"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"redirect_uri must be one of the URIs registered for this client"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "field"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"redirect_uri"</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<table>
<thead>
<tr>
<th>Field</th>
<th>Type</th>
<th>Notes</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>code</code></td>
<td><code>string</code></td>
<td>Stable machine-readable identifier (snake_case)</td>
</tr>
<tr>
<td><code>message</code></td>
<td><code>string</code></td>
<td>Human-readable explanation, may change between versions</td>
</tr>
<tr>
<td><code>field</code></td>
<td><code>string?</code></td>
<td>Set on <code>400</code> validation errors; identifies the offending field</td>
</tr>
</tbody>
</table>
<p>Always switch on <code>code</code>, not <code>message</code>.</p>
<h2 id="common-status-codes"><a href="#common-status-codes">Common status codes</a></h2>
<table>
<thead>
<tr>
<th>HTTP</th>
<th>Meaning</th>
<th>What to do</th>
</tr>
</thead>
<tbody>
<tr>
<td>400</td>
<td>Validation / bad request</td>
<td>Fix the request and retry</td>
</tr>
<tr>
<td>401</td>
<td>Missing / invalid auth</td>
<td>Refresh the token, or re-authorize</td>
</tr>
<tr>
<td>403</td>
<td>Authenticated but no permission</td>
<td>Don't retry; user needs the right scope or role</td>
</tr>
<tr>
<td>404</td>
<td>Resource not found</td>
<td>Confirm the ID; don't retry</td>
</tr>
<tr>
<td>409</td>
<td>Conflict (e.g., duplicate)</td>
<td>Inspect the error and adapt</td>
</tr>
<tr>
<td>429</td>
<td>Rate limited</td>
<td>Back off; check <code>Retry-After</code></td>
</tr>
<tr>
<td>500</td>
<td>Server error</td>
<td>Retry with exponential backoff; if persistent, report it</td>
</tr>
</tbody>
</table>
<h2 id="retry-guidance"><a href="#retry-guidance">Retry guidance</a></h2>
<ul>
<li><strong>Idempotent verbs</strong> (<code>GET</code>, <code>PUT</code>, <code>DELETE</code>) \u2014 retry safely on 5xx and
network errors.</li>
<li><strong><code>POST</code></strong> \u2014 retry only if you set <code>Idempotency-Key</code> (see the
<a href="https://api.agenticdeveloperhub.com">API reference</a>) or you can otherwise
guarantee the operation is idempotent.</li>
<li><strong>Rate limits</strong> \u2014 honour <code>Retry-After</code> (seconds). Don't retry faster than
the server tells you to.</li>
</ul>
<h2 id="reporting-bugs"><a href="#reporting-bugs">Reporting bugs</a></h2>
<p>If the response looks like a server-side bug (5xx without a clear cause,
unexpected <code>400</code>), include the <code>code</code>, the request ID from the
<code>X-Request-Id</code> response header, and a minimal repro in your report.</p>`,
  "hub-apis": `<h1 id="apis--agents"><a href="#apis--agents">APIs &#x26; agents</a></h1>
<p>Everything you configured by clicking has to be reachable by something that
does not click. Your product's code needs to talk to it at runtime, and \u2014 more
often now \u2014 so does the coding agent you are building it with. A control panel
that is the only way in is a control panel you will end up scripting badly.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<p>Every screen in the Hub is a resource, and there are two ways to reach it:</p>
<ul>
<li><strong><a href="/rest-api">REST API</a></strong> \u2014 an OpenAPI 3.1 surface covering every resource,
described well enough to generate a client from.</li>
<li><strong><a href="/mcp">MCP server</a></strong> \u2014 the same platform over the Model Context Protocol,
as a curated tool set an AI agent can be handed. Not a mechanical mirror of
the REST surface: the tools are chosen so an agent can accomplish something
rather than enumerate everything.</li>
<li><strong><a href="/quickstart/oauth/overview">OAuth</a></strong> \u2014 authorize on behalf of a user, for
when your code is acting for someone rather than as itself.</li>
<li><strong>Application tokens</strong> \u2014 a bearer credential minted against one application,
reaching one product's project and nothing beyond it.</li>
<li><strong>Tools</strong> \u2014 reusable, typed capabilities you define once and expose to any
persona, over both REST and MCP.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A token plus an <a href="/hub/products">application</a> plus a <a href="/hub/plan">project</a> is
the whole access story, in that order.</strong> The token belongs to the application,
the application belongs to the product, and the project is what it reaches. Each
link narrows the last, which is why a leaked token is a bad afternoon rather
than a bad quarter \u2014 it reaches one project, and nothing else you own.</p>
<p><strong>MCP plus your coding agent is how the setup happens without you.</strong> Creating a
<a href="/hub/personas">persona</a>, wiring its service, minting a token, binding a
project: all of it is a tool call. The Hub is built to be operated by an agent,
which is a claim it has to make good on for its own configuration first.</p>
<p><strong>A tool plus a persona is how an agent does something rather than says
something.</strong> Define the capability once with its types, expose it to the persona,
and it is available in chat, on the public profile, and to anything calling the
API \u2014 the same four surfaces the persona itself reaches.</p>
<p><strong>OAuth plus a <a href="/hub/products">sign-in app</a> is how you act for your customer.</strong>
Your product signs its own users in through the Hub, then calls on their behalf
with their consent \u2014 rather than with a token that can reach everything.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>Dognamr has two applications, and each holds its own token. The scope column is
the point of the screenshot: each one names exactly one project, so the token in
Casey's CLI cannot read what the public site's token reads, and neither can see
Shelterly at all:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/tokens.png" alt="Each token&#x27;s scope naming exactly one project"></p>
<p>Everything else in this documentation \u2014 Bob, his service, both stores, the
project binding them \u2014 is a REST resource Casey could have created without
opening a single screen.</p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/rest-api">REST API</a> \u2014 the full resource surface.</li>
<li><a href="/mcp">MCP server</a> \u2014 the curated tool set for agents.</li>
<li><a href="/hub/products">Products</a> \u2014 the application a token belongs to.</li>
<li><a href="/hub/plan">Plan</a> \u2014 the project a token reaches.</li>
</ul>`,
  "hub-community": `<h1 id="community--support"><a href="#community--support">Community &#x26; support</a></h1>
<p>Two audiences want to talk to you, and they are not the same people. You have
questions about the platform you are building on; the people using what you
built have questions about <em>that</em>, and somewhere to argue about it. Sending both
to the same inbox loses one of them.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<ul>
<li><strong>Discussions</strong> \u2014 the Agentic Developer Community forum: topics, threads, and
a member directory. This is where builders talk to each other.</li>
<li><strong>Communities</strong> \u2014 a forum belonging to <em>your</em> product, with its own
categories and its own members, for the people using what you shipped.</li>
<li><strong>Support</strong> \u2014 searchable answers first, then a ticket tied to your account
when the answer is not there.</li>
<li><strong>News</strong> \u2014 releases and stories, subscribable by RSS or email.</li>
<li><strong>Messaging</strong> \u2014 direct messages and a notification inbox, enabled per
ecosystem, so a product can reach its own users without you sending email.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A community plus a <a href="/hub/products">product</a> is where its users end up.</strong> The
community belongs to the ecosystem, so its members are your customers rather
than Hub accounts \u2014 the same distinction that separates a
<a href="/hub/workspaces">member</a> from a customer everywhere else in the Hub.</p>
<p><strong>Messaging plus a <a href="/hub/products">feature flag</a> is how a rollout gets
announced.</strong> The flag decides who has the new thing; a notification tells them
it is there. Either alone is half of a launch.</p>
<p><strong>A <a href="/hub/personas">persona</a> plus a community is how a forum gets answered
overnight.</strong> A persona can hold an account in the community the same way it
holds a seat on a <a href="/hub/teams">team</a> \u2014 so the agent that knows the product is
the one replying in it.</p>
<p><strong>Discussions plus Support is the escalation path.</strong> Search the answers, ask the
forum, open a ticket. The order matters because the first two are free and
faster, and a ticket that skipped them usually gets an answer that was already
written down.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p><strong>The Dognamr Pack</strong> is Dognamr's own community, with real discussion in it \u2014
visitors arguing about names. Its members are Casey's end users, not Hub
accounts, which is the distinction this screen exists to make concrete:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/communities.png" alt="The Dognamr Pack community, with discussion threads in it"></p>
<p>And when Casey ships something, the notification goes to those same end users
through the product's own inbox rather than an email list kept somewhere else:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/messaging.png" alt="A notification addressed to Dognamr&#x27;s end users"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/products">Products</a> \u2014 the boundary a community belongs to.</li>
<li><a href="/hub/workspaces">Workspaces &#x26; account</a> \u2014 members versus customers.</li>
<li><a href="/hub/personas">Personas</a> \u2014 the agent that can answer in a thread.</li>
</ul>`,
  "hub-monitoring": `<h1 id="monitoring"><a href="#monitoring">Monitoring</a></h1>
<p>At 2am something is wrong and the only question worth answering is <em>which
layer</em>. A status page that watches only your own site tells you it is down \u2014
which you knew, because that is why you are awake. What you need is your site,
the service it calls, and the platform underneath both, on one page, so the
answer is a glance rather than an investigation.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<ul>
<li><strong>Dashboards</strong> \u2014 register the sites and endpoints you want watched, and see
uptime and current status in one view.</li>
<li><strong>Status groups</strong> \u2014 group what you registered, so a page reads as layers
rather than as an unsorted list of URLs.</li>
<li><strong>Metrics</strong> \u2014 the numbers a shipped product produces: usage, engagement, and
what your agents are spending.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A status group plus a <a href="/hub/plan">project</a> is what scopes the page.</strong> The
project names which group belongs to it, so the status view is about one product
instead of everything you own. A workspace with two products gets two pages, not
one long one.</p>
<p><strong>Your endpoints plus the Hub's own services is what makes the page answer the
question.</strong> Register the service your product calls alongside your site, and the
Hub's status for the APIs your <a href="/hub/personas">persona</a> depends on appears in
the same view. Three layers, one page \u2014 that is the difference between knowing
something is broken and knowing where.</p>
<p><strong>A dashboard plus <a href="/hub/products">billing</a> is how usage becomes a decision.</strong>
Suggestions served, conversion, and token spend against subscribers tells you
whether the paid tier is worth what it costs to run.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>Dognamr's dashboard carries the numbers Casey actually checks: how many names
were suggested, how many got pinned, and what Bob cost to run:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/dashboards.png" alt="The Dognamr dashboard \u2014 daily suggestions, pin rate, and Bob&#x27;s token spend"></p>
<p>And the status view has three groups, deliberately: the Dognamr site itself, the
breed-classifier endpoint it calls, and the Hub APIs Bob depends on. When one is
red, Casey knows which one before opening anything else:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/monitoring-status.png" alt="Three status groups on one page \u2014 the site, the classifier endpoint, and the Hub APIs"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/plan">Plan</a> \u2014 the project that names a status group.</li>
<li><a href="/hub/products">Products</a> \u2014 the product a dashboard is about.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 reading status from your own code.</li>
</ul>`,
  "hub-overview": `<h1 id="hub-features"><a href="#hub-features">Hub Features</a></h1>
<p>You are building something that has an agent in it, and the agent needs a place
to live. Not a folder in your repo \u2014 a place with an address, a version history,
credentials it can use, data it can read, and a way for your code to reach it
that is not a secret pasted into an environment variable. That place has to be
separate from your product, because your product will be rewritten and the agent
should survive it.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<p>The Hub is that place, and everything in it hangs off one idea: a <strong>workspace</strong>.</p>
<ul>
<li><strong>A workspace is who the work belongs to.</strong> Your personal one, or an
organization you own or belong to. You are always inside exactly one, and the
switcher at the top-left is how you move.</li>
<li><strong>Everything else is scoped to a workspace</strong> \u2014 personas, products, storage,
projects, teams, tokens. Nothing floats loose. Two organizations can both have
a persona called Bob and never collide.</li>
<li><strong>A product inside a workspace scopes it further.</strong> Applications, tokens,
buckets, flags, and dashboards all belong to one product, so a token minted for
one cannot read another's data.</li>
<li><strong>Members are people in the workspace; customers are people in your product.</strong>
These are different populations with different sign-in flows, and confusing
them is the single most common mistake new readers make.</li>
</ul>
<div class="adh-mv-alert adh-mv-alert--note">
<p class="adh-mv-alert-title">Note</p>
<p>New here? Start with the <a href="/quickstart">Quickstart</a> to register an app, mint a
token, and make your first call.</p>
</div>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A workspace plus an organization is what makes it shared.</strong> A personal
workspace is a workspace with one member. Create an organization and the same
surfaces gain a <a href="/hub/workspaces">member roster</a>, invitations, and teams \u2014 the
features do not change, only who can reach them.</p>
<p><strong>A workspace plus a <a href="/hub/products">product</a> is what gives your work a
boundary.</strong> Without a product, everything you create sits at workspace level and
every token you mint reaches all of it. A product is how you say <em>this
application may read this data and nothing else</em>.</p>
<p><strong>A workspace plus a <a href="/hub/plan">project</a> is what binds the pieces together.</strong> A
persona, the store it reads, the store your users write to, and a status group
are four unrelated objects until a project names them as one thing. The project
is what an application points at.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company. It exists so every screen in these pages has
something real on it.</em></p>
<p>Casey Rowan has two workspaces: a personal one, and the organization Casey owns.
The switcher shows both, which is the clearest statement of what an organization
is \u2014 a place you go, not a setting you toggle:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/workspace-switcher.png" alt="The workspace switcher open, showing Casey&#x27;s personal workspace above Longtail Labs"></p>
<p>Inside Longtail Labs, the workspace home is a summary of what the studio is
building \u2014 two products at opposite ends of their lives, Dognamr live and
Shelterly in early access:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/workspace-home.png" alt="The Longtail Labs workspace home, listing Dognamr and Shelterly"></p>
<p>Every page that follows is a screen inside this workspace, signed in as Casey.</p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/workspaces">Workspaces &#x26; account</a> \u2014 settings, members, invitations, and
the tokens that reach your data.</li>
<li><a href="/hub/personas">Personas</a> \u2014 the agent itself. Most people start here.</li>
<li><a href="/hub/products">Products</a> \u2014 the boundary everything else is scoped inside.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 every screen in this section, reachable from code.</li>
</ul>`,
  "hub-personas": `<h1 id="personas"><a href="#personas">Personas</a></h1>
<p>You want an agent that behaves the same way every time \u2014 same voice, same
knowledge, same limits \u2014 whether someone meets it inside your product, on a page
you can send a link to, or through an API call your own code makes. Writing that
behaviour into each of those places separately means three copies to keep in
step, and they will not stay in step.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<p>A persona is that behaviour, written down once and versioned:</p>
<ul>
<li><strong>Identity</strong> \u2014 name, bio, avatar, and the slug that becomes a public address.</li>
<li><strong>Character and voice</strong> \u2014 the traits, stances, and special interests that go
verbatim into the system prompt, so the prompt is something you edit rather
than something you assemble by hand.</li>
<li><strong>Worked examples and canned exchanges</strong> \u2014 sample conversations that show a
visitor how the agent behaves before they type anything.</li>
<li><strong>Model preferences</strong> \u2014 which model this persona runs on, chosen from what its
service actually offers rather than typed from memory.</li>
<li><strong>Visibility</strong> \u2014 <code>private</code> to your workspace, <code>hub</code> to signed-in Hub users, or
<code>public</code> to anyone with the link.</li>
<li><strong>Version history</strong> \u2014 every revision inspectable, diffable, and pinnable.</li>
</ul>
<p><strong>Persona Services</strong> are the other half of the page: one service is one
connection to one provider account. It holds the credentials, reports whether the
connection is live, and publishes the list of models that provider actually
offers. Services are created from <strong>LLM provider templates</strong> \u2014 the catalogue of
providers the Hub knows how to talk to \u2014 so connecting an account is filling in a
form, not writing a client.</p>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A persona plus a service is what makes it able to talk.</strong> This is the one
combination nothing else works without. The persona holds the behaviour; the
service holds the provider connection and the credentials. On its own a persona
is a specification nobody has run \u2014 it renders, it diffs, and it cannot answer a
question. Point it at a service and the same wiring serves four surfaces at once:
chat inside your product, the persona's public profile on the Persona Registry,
the <a href="/hub/apis">REST API</a>, and the <a href="/mcp">MCP server</a>. You configure the provider
once, in one place, and all four follow. Change the model on the persona and all
four change together.</p>
<p><strong>A persona plus a <a href="/hub/storage">Persona Data Store</a> is what makes it
informed.</strong> The store holds the prompts, reference material, and memory the agent
reasons from, scoped to one project. Without it the agent knows only what its
character fields say; with it, it knows what you have given it.</p>
<p><strong>A persona plus a <a href="/hub/storage">Knowledge Base</a> is what makes it citable.</strong> A
knowledge base is documents ingested into a searchable store the agent can ground
an answer in and point back at. Character makes an agent sound right; a knowledge
base makes it <em>be</em> right.</p>
<p><strong>A persona plus a <a href="/hub/teams">team</a> is what makes it a colleague.</strong> Team
membership is not restricted to humans \u2014 a persona joins a team the same way a
person does, appears in the member list beside them, and inherits the team's
access.</p>
<p><strong>A persona plus a <a href="/hub/plan">project</a> is what your application points at.</strong> An
application does not name a persona directly; it names a project, and the project
names the persona, its store, and everything else that ships together.</p>
<p><strong>A <code>public</code> persona plus a slug is a place people can go.</strong> Publishing puts the
agent at <code>agenticpersonaregistry.com/&#x3C;slug></code>, where its character fields stop
being configuration and become the page \u2014 bio, worked examples, and a chat box
that talks to it through the service you configured. This is why the character
fields are worth writing properly: on a public persona, they are the product.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>The studio runs three personas, one per visibility tier:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/personas-list.png" alt="Three personas in the Longtail Labs workspace \u2014 Bob public, Scout hub, Margo private"></p>
<p><strong>Bob</strong> is <code>public</code>. He suggests names for dogs and cannot do it without
explaining where the name came from \u2014 which is a character trait Casey wrote, not
a behaviour that emerged. His three worked examples and his canned opening
exchange are authored in the editor, not captured from a session:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/persona-bob-editor.png" alt="Bob&#x27;s persona editor on the character tab, showing his traits and worked examples"></p>
<p><strong>Scout</strong> is <code>hub</code> \u2014 internal only. Scout writes the studio's release notes and
posts status updates, and never meets a customer. A workspace with exactly one
persona in it teaches the wrong lesson: personas are not only for the
customer-facing agent.</p>
<p><strong>Margo</strong> is <code>private</code>, drafts adoption listings for Shelterly, and runs on the
studio's second provider \u2014 which is a fact about her service, not about her.</p>
<p>Casey created one service per provider. Both report a live connection, and each
carries its own credentials:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/persona-services.png" alt="Two persona services \u2014 an Anthropic connection and an OpenAI connection, both live"></p>
<p>Both were instantiated from the provider catalogue rather than configured from
scratch:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/llm-providers.png" alt="The LLM provider templates the two connections were created from"></p>
<p>Because Bob points at the Anthropic service, his model picker lists the models
that service actually offers. The list is fetched from the connection, so a model
that provider has retired cannot be selected here:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/persona-bob-model.png" alt="Bob&#x27;s model picker, listing models fetched from his service"></p>
<p>And that is the whole chain, ending somewhere a stranger can reach. Bob is
public, so the same persona and the same service produce a profile page with a
usable chat box on it \u2014 no additional configuration, and no second copy of his
character to maintain:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/persona-bob-profile.png" alt="Bob&#x27;s public profile on the Persona Registry, with his bio, examples, and a chat box"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/storage">Storage &#x26; data</a> \u2014 the two kinds of store a persona uses, and why
they are different things.</li>
<li><a href="/hub/plan">Plan</a> \u2014 the project that binds a persona to its data, and the
narratives feature where authored exchanges live.</li>
<li><a href="/hub/teams">Teams</a> \u2014 putting a persona in a member list beside people.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 reaching a persona from your own code, and over
MCP.</li>
</ul>`,
  "hub-plan": `<h1 id="plan"><a href="#plan">Plan</a></h1>
<p>You have an agent, a couple of stores, a status group, and a piece of software
that has to point at all of them. Naming each one individually in your
application's configuration means the configuration is where the wiring lives \u2014
and the wiring is then something you redeploy to change, and something no
teammate can read.</p>
<p>You also have the work itself: what is being built, what was decided, and why.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<ul>
<li><strong>Projects</strong> \u2014 the binding. A project names a persona, the data stores it
uses, and a status group, as one thing with a name. It is also where the work
lives, with <strong>Plans</strong> and <strong>Tasks</strong>; agents read and update those work items
over the <a href="/rest-api">REST API</a> and <a href="/mcp">MCP</a>.</li>
<li><strong>Statuses</strong> \u2014 every project starts with a default set, so a task has
somewhere to be before you have configured anything.</li>
<li><strong>Narratives</strong> \u2014 a shareable story synthesized from your git history, docs,
and notes. It is also where a persona's authored exchanges live: the canned
opening a first-time visitor sees before typing.</li>
<li><strong>Research</strong> \u2014 a shared, searchable notebook of markdown documents, versioned
the way the rest of the Hub versions things.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A project plus an <a href="/hub/products">application</a> is what your code points at.</strong>
An application never names a persona directly. It names a project, and the
project names everything that ships together \u2014 so changing which persona a
product runs is a change here rather than a redeploy there.</p>
<p><strong>A project plus a <a href="/hub/personas">persona</a> and its
<a href="/hub/storage">stores</a> is what makes the persona reachable.</strong> A bucket outside a
project is invisible to the agent that needs it; a persona outside a project has
no way for your code to find it. The project is the join.</p>
<p><strong>A project plus a status group is what makes the <a href="/hub/monitoring">status page</a>
about something.</strong> The group names which endpoints belong to this product, so
the monitoring view is scoped rather than a flat list of everything you own.</p>
<p><strong>Narratives plus a <code>public</code> <a href="/hub/personas">persona</a> is what a visitor sees
first.</strong> The canned exchange authored here renders on the persona's public
profile before the visitor types anything \u2014 so the agent demonstrates itself
rather than presenting an empty box.</p>
<p><strong>Research plus a <a href="/hub/storage">knowledge base</a> is how a note becomes something
an agent can cite.</strong> Research is where you write; a knowledge base is where an
agent reads. Documents move from one to the other when they are ready to be
answered from.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p><strong>Dognamr Production</strong> is the project that makes the rest of the workspace
composable: it names Bob, both data stores, and the status group, and it is what
the Dognamr Web application points at. Shelterly's project sits beside it,
deliberately thinner \u2014 an early-access product has less wired up, and that is
what an early-access product looks like:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/projects.png" alt="Dognamr Production binding Bob, both stores and the status group, with Shelterly&#x27;s thinner project beside it"></p>
<p>Bob's opening exchange is authored, not captured from a session. It is what a
stranger arriving at his profile reads before deciding whether to type:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/narratives.png" alt="Bob&#x27;s canned opening exchange, as authored"></p>
<p>Casey's working notes on naming heuristics live in Research \u2014 searchable, shared
with Priya, and the raw material the Breed Encyclopedia was built from:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/research.png" alt="Casey&#x27;s research notes on naming heuristics"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/personas">Personas</a> \u2014 the agent a project binds.</li>
<li><a href="/hub/storage">Storage &#x26; data</a> \u2014 the stores a project binds.</li>
<li><a href="/hub/products">Products</a> \u2014 the application that points at a project.</li>
<li><a href="/hub/monitoring">Monitoring</a> \u2014 the status group a project names.</li>
</ul>`,
  "hub-products": `<h1 id="products"><a href="#products">Products</a></h1>
<p>The thing you are building has its own users, its own data, and its own
credentials \u2014 and none of that should be reachable by the next thing you build.
You also need somewhere to put the parts of a shipped product that are not code:
who has signed up, who is paying, which features are switched on for whom, and
the configuration you would otherwise redeploy to change.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<p>A product is an <strong>ecosystem</strong>: a boundary with its own settings, its own project,
and its own data. Inside one you manage:</p>
<ul>
<li><strong>Applications</strong> \u2014 one per thing that talks to the Hub. Each carries API tokens
scoped to this product and nothing else.</li>
<li><strong>Sign-in apps</strong> \u2014 let your own site sign <em>its</em> customers in through the Hub.
OAuth you do not have to build.</li>
<li><strong>Users</strong> \u2014 your product's customers: invitations, access requests, and pending
members. These are not Hub users.</li>
<li><strong>Email signup</strong> \u2014 a waitlist or launch-notification capture, with the list
behind it.</li>
<li><strong>Billing</strong> \u2014 offers your customers subscribe to, and who is on each one.</li>
<li><strong>Feature flags</strong> \u2014 runtime on/off toggles your app reads, targetable at a
subset of customers.</li>
<li><strong>Server bags</strong> \u2014 key\u2192JSON configuration your app reads at runtime, per
ecosystem.</li>
<li><strong>Gamification</strong> \u2014 the character-sheet system: levels, badges, seasons, and
leaderboards for your personas and your users.</li>
<li><strong>Storage</strong>, <strong>integrations</strong>, and <strong>dashboards</strong>, all scoped here.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A product plus an <a href="/hub/products">application</a> plus a token is what your code
uses to get in.</strong> The chain matters in that order: the token belongs to the
application, the application belongs to the product, and the product is what
bounds what the token can reach. A leaked token is a bad day, not a catastrophe,
because of the last link.</p>
<p><strong>A product plus a <a href="/hub/plan">project</a> is what points an application at
something.</strong> The project names the persona, the stores, and the status group that
ship together. Without it, an application is a credential with nothing on the
other end.</p>
<p><strong>Sign-in apps plus <a href="/hub/workspaces">members</a> is the distinction to get right.</strong>
Members are people in <em>your workspace</em> \u2014 colleagues. Sign-in apps serve people in
<em>your product</em> \u2014 customers. They sign in through different flows, appear in
different lists, and a customer never gains reach into your workspace.</p>
<p><strong>Feature flags plus billing is how a rollout usually actually looks.</strong> A flag
targeted at an offer means paying customers get the new thing first. Either
feature alone gives you a switch or a subscriber list; together they give you a
release plan.</p>
<p><strong>Gamification plus a <a href="/hub/personas">persona</a> is what turns a profile into a
character sheet.</strong> Levels and badges attach to the persona you already
published, so the public profile gains a progression without you building one.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>The studio ships two products, at deliberately different stages \u2014 Dognamr is
live, Shelterly is in early access with a handful of invited shelters:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/products-list.png" alt="Dognamr and Shelterly side by side, their stages visibly different"></p>
<p>Opening Dognamr shows what a product actually contains \u2014 its applications, its
customers, and its flags on one screen:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/product-dognamr.png" alt="The Dognamr product, showing its applications, customers, and flags"></p>
<p>Two applications reach it, and they are different kinds of thing. <strong>Dognamr Web</strong>
is the customer-facing site; <strong>Dognamr CLI</strong> is Casey's own tool. Both are
applications, and neither can read Shelterly:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/applications.png" alt="The Dognamr applications \u2014 Dognamr Web and Dognamr CLI, their consumer kinds differing"></p>
<p>Dognamr's visitors sign in through the product's own sign-in app. These are
Casey's customers, not Hub users \u2014 the distinction most readers get wrong the
first time:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/signin-apps.png" alt="Dognamr&#x27;s sign-in apps"></p>
<p><img src="https://agenticdeveloperhub.com/screenshots/auth.png" alt="Dognamr&#x27;s end-user sign-in settings"></p>
<p>Shelterly is not open yet, so its front page captures interest instead of
accounts:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/email-signup.png" alt="Dognamr&#x27;s email signup capture, with signups against it"></p>
<p>Dognamr Plus is the paid tier, with customers on it:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/billing.png" alt="The Dognamr Plus offer with paying customers against it"></p>
<p>Casey's newest feature \u2014 uploading a photo to guess the breed \u2014 rolls out to
those subscribers first. That is the flag and the offer working together:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/feature-flags.png" alt="A feature flag rolling out to Dognamr Plus subscribers first"></p>
<p>Everything else Dognamr needs at runtime and does not want to redeploy for lives
in its server bag, which differs from Shelterly's:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/server-bags.png" alt="Per-ecosystem server bag configuration for Dognamr and Shelterly"></p>
<p>And Dognamr's visitors earn badges for naming dogs, which puts a leaderboard on a
product that is otherwise a text box:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/gamification.png" alt="The Dognamr badge set and leaderboard"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/storage">Storage &#x26; data</a> \u2014 where a product's data actually sits.</li>
<li><a href="/hub/plan">Plan</a> \u2014 the project an application points at.</li>
<li><a href="/hub/monitoring">Monitoring</a> \u2014 watching a shipped product from one page.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 the token, and what it reaches.</li>
</ul>`,
  "hub-storage": `<h1 id="storage--data"><a href="#storage--data">Storage &#x26; data</a></h1>
<p>Your agent needs to read something, and your users need their choices to still
be there next week. Those are two different problems, and solving them with one
pile of rows is the mistake that is cheap to make and expensive to undo \u2014 the
reference material you curate and the per-visitor state you must never leak into
a prompt end up in the same place, permissioned the same way.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<p>Storage is a set of named, permissioned collections and a browser over what is
in them:</p>
<ul>
<li><strong>Buckets</strong> \u2014 named collections that expose selected tables and rows. Every
ecosystem gets a default one, and buckets nest, so a product's data can have
structure without a second database.</li>
<li><strong>Bucket kinds</strong> \u2014 what a bucket is <em>for</em>. A <strong>persona data store</strong> holds what
the agent knows; a <strong>user data store</strong> holds what each of your end users
chose. The difference is who has read access, not a naming convention.</li>
<li><strong>Files</strong> \u2014 upload, browse, and serve files, with signed reads so a URL you
hand out expires.</li>
<li><strong>Knowledge bases</strong> \u2014 documents ingested into a searchable store an agent can
ground an answer in and cite back at.</li>
<li><strong>Access &#x26; usage</strong> \u2014 the permission list for each bucket, and what has been
reading it.</li>
<li><strong>All Data</strong> \u2014 a cross-schema browser that reads and edits the underlying
records directly, for when you need to see the row rather than the feature.</li>
<li><strong>Integrations</strong> \u2014 third-party accounts (OAuth or Plaid) that sync data into
your workspace on a schedule.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A persona data store plus a <a href="/hub/personas">persona</a> is what makes the agent
informed.</strong> Character fields tell an agent how to sound; the store tells it what
is true. Grant the persona read access to a bucket and everything in that bucket
is material it can reason from \u2014 the same for every visitor, and yours to
curate.</p>
<p><strong>A user data store plus your own end users is what makes your product
remember.</strong> Keyed by the customer who signed in through your
<a href="/hub/products">product's</a> sign-in app, so the pins, preferences, and progress
follow that person across devices. You get per-user persistence without running
a database, and \u2014 because the grant is on the user, not the persona \u2014 nothing in
it is visible to the agent unless you deliberately hand it over.</p>
<p><strong>A bucket plus a <a href="/hub/plan">project</a> is what makes it reachable.</strong> A bucket
outside a project is invisible to the application that needs it. The project is
what names which stores ship together with which persona, and an
<a href="/hub/apis">application's token</a> reaches the project rather than the bucket.</p>
<p><strong>A knowledge base plus a persona is what makes an answer citable.</strong> Ingested
documents are chunked and embedded, so the agent retrieves the passage rather
than being handed the whole corpus. Character makes an agent sound right; a
knowledge base makes it <em>be</em> right.</p>
<p><strong>Integrations plus a bucket is how outside data arrives.</strong> A connected GitHub
or Stripe account syncs into a bucket you already permissioned, so the agent
reading that bucket picks it up without you writing an importer.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>Dognamr has both kinds of store, and the pair is the clearest thing on this
page. <code>bob-context</code> is Bob's \u2014 breed dictionaries and naming guardrails.
<code>visitor-favorites</code> is the visitors' \u2014 the names each of them pinned:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/storage-buckets.png" alt="bob-context and visitor-favorites side by side, their kinds visibly different"></p>
<p>Opening <code>bob-context</code> shows material Casey wrote and Bob reads. None of it is
per-visitor, and it is identical for everyone who talks to him:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/storage-bob-context.png" alt="Inside bob-context \u2014 breed dictionaries and naming guardrails"></p>
<p>Both stores, and the rows inside them, in one cross-schema view \u2014 this is the
screen for when the feature UI is not showing you what you need:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/all-data.png" alt="Both stores and their contents in the All Data browser"></p>
<p>The Breed Encyclopedia is a knowledge base rather than a bucket of loose rows,
and it names the persona consuming it. That column is the point: a knowledge
base nothing reads is a document dump:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/knowledgebases.png" alt="The Breed Encyclopedia knowledge base, showing Bob as its consumer"></p>
<p>Longtail Labs has GitHub and Stripe connected, so release activity and payment
records arrive in the workspace rather than being copied in by hand:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/integrations.png" alt="GitHub and Stripe, both connected"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/personas">Personas</a> \u2014 the agent that reads the store.</li>
<li><a href="/hub/plan">Plan</a> \u2014 the project that binds stores to a persona.</li>
<li><a href="/hub/products">Products</a> \u2014 the boundary the data sits inside.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 reading and writing a bucket from your own code.</li>
</ul>`,
  "hub-teams": `<h1 id="teams"><a href="#teams">Teams</a></h1>
<p>Access granted person by person stops working at about the fourth person. The
usual fix is groups \u2014 but the moment some of the work is done by agents, a
group that only accepts humans has a hole in it, and you are back to
special-casing the agents everywhere.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<ul>
<li><strong>Teams</strong> \u2014 named groups inside a workspace, each with its own members and
roles. Access is granted to the team, and members inherit it.</li>
<li><strong>Members of two kinds</strong> \u2014 a team member is a person <em>or</em> a persona. Both
appear in the same list, both carry a role, and both inherit the same access.</li>
<li><strong>Team Registry</strong> \u2014 a public, claimable profile for a registered agentic team,
so a team can be something you point at from outside.</li>
<li><strong>Team Builder</strong> \u2014 compose a team from existing personas, define their roles
and hand-offs, and publish it.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A team plus a <a href="/hub/personas">persona</a> is what makes the agent a colleague.</strong>
Team membership is not restricted to humans. A persona joins the same way a
person does, sits in the member list beside them, and inherits the team's
access \u2014 which means an agent gets to the data it needs through the same
mechanism everything else does, rather than through a credential you wired by
hand. A persona must be permitted to act as a team member before it can be
added; that grant is deliberate and per-persona.</p>
<p><strong>A team plus a <a href="/hub/workspaces">workspace</a> is how an org actually operates.</strong>
An organization has no credentials and never signs in. Everything it does, it
does through teams \u2014 which is the whole reason the object exists, and why
membership rather than ownership is what you manage day to day.</p>
<p><strong>A team plus a <a href="/hub/storage">bucket</a> is permission that survives the next
hire.</strong> Grant the team, not the person. Someone joining gets what the team has;
someone leaving loses it, in one place.</p>
<p><strong>Team Builder plus the <a href="/hub/personas">registry</a> is how a group of agents
becomes something you can hand to someone.</strong> Roles and hand-offs defined once,
published as a unit, reachable by a name rather than reassembled from three
persona slugs.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p><strong>Dognamr Core</strong> has three members, and one of them is not a person. Casey and
Priya are humans; Bob is a persona, in the same list, with a role, inheriting
the same access as the two of them:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/teams.png" alt="The Dognamr Core team \u2014 Casey, Priya and Bob together in one member list"></p>
<p>That is the most surprising thing on this page and it is not a trick of the
display. Bob reaches <code>bob-context</code> because the team he belongs to can reach it \u2014
the same route Priya's access takes.</p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/workspaces">Workspaces &#x26; account</a> \u2014 members, roles, and what an org is.</li>
<li><a href="/hub/personas">Personas</a> \u2014 the agent that stands in the member list.</li>
<li><a href="/hub/storage">Storage &#x26; data</a> \u2014 what a team's access actually reaches.</li>
</ul>`,
  "hub-workspaces": `<h1 id="workspaces--account"><a href="#workspaces--account">Workspaces &#x26; account</a></h1>
<p>Work that matters stops being one person's fairly quickly. Someone else needs to
see the agent's configuration, change a prompt, or keep shipping while you are
away \u2014 and the answer cannot be sharing your password. You need a place the work
belongs to rather than a place you own, with people in it who have their own
accounts and their own level of reach.</p>
<h2 id="what-it-does"><a href="#what-it-does">What it does</a></h2>
<ul>
<li><strong>Switch workspaces</strong> \u2014 your personal workspace and every organization you
belong to, from one control. Create a new organization from Home.</li>
<li><strong>Members</strong> \u2014 the roster of people in an organization, and what each one may
do. An owner can change billing and remove people; a member cannot.</li>
<li><strong>Invitations</strong> \u2014 invite by email, see who has not accepted yet, and withdraw
an invitation that was sent in error.</li>
<li><strong>Settings</strong> \u2014 appearance, account, security, subscription, your public
profile, and notifications, plus the organization's own name and description.</li>
<li><strong>API tokens</strong> \u2014 mint, list, and revoke tokens that reach your data. Each one
can reach the workspace's storage buckets.</li>
</ul>
<h2 id="what-you-use-it-with"><a href="#what-you-use-it-with">What you use it with</a></h2>
<p><strong>A workspace plus <a href="/hub/workspaces">members</a> is what makes a persona
survivable.</strong> A persona configured in a personal workspace is configured by one
person who may leave. Moved into an organization, the same persona has a roster
behind it, and the prompt that runs your product is not hostage to one account.</p>
<p><strong>Members plus <a href="/hub/teams">teams</a> is what makes access legible.</strong> Roles say what
someone may do; teams say what they are working on. A ten-person organization
with no teams is ten people who all see everything, which stops being useful long
before it stops being safe.</p>
<p><strong>A token plus an <a href="/hub/products">application</a> is what makes your code able to
reach any of this.</strong> A token minted here is scoped, and the thing it is scoped to
is the application inside a product. That is the difference between a credential
your code carries and a credential that would be a problem if it leaked.</p>
<p><strong>Your account plus a <a href="/hub/teams">public profile</a> is how you appear elsewhere.</strong>
The profile in Settings is what other Hub users see in a member directory, a
discussion thread, or beside a team you helped build.</p>
<h2 id="in-the-demo"><a href="#in-the-demo">In the demo</a></h2>
<p><em>Longtail Labs is the Agentic Developer Hub's documentation demo \u2014 a fictional
studio, not a real company.</em></p>
<p>Longtail Labs has two people in it, and deliberately not two owners. Casey Rowan
owns the organization; Priya Anand is a member:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/members.png" alt="The Longtail Labs member roster \u2014 Casey as owner, Priya as member"></p>
<p>That difference is the whole reason the roster exists. Priya can edit personas,
write to storage, and ship; Priya cannot change the subscription or remove Casey.</p>
<p>A third invitation is outstanding. Tomas Ferreira was invited and has not
accepted, which is what a pending row looks like \u2014 not an error, just a person
who has not clicked the link yet:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/invitations.png" alt="The invitations screen showing Tomas Ferreira, pending"></p>
<p>The organization's own settings carry its name, description, and the line
identifying it as this documentation's demo:</p>
<p><img src="https://agenticdeveloperhub.com/screenshots/settings.png" alt="Longtail Labs workspace settings"></p>
<h2 id="where-to-go-next"><a href="#where-to-go-next">Where to go next</a></h2>
<ul>
<li><a href="/hub/teams">Teams</a> \u2014 grouping the people on this roster, and the personas that
stand among them.</li>
<li><a href="/hub/products">Products</a> \u2014 the boundary that tokens are scoped to.</li>
<li><a href="/hub/apis">APIs &#x26; agents</a> \u2014 what a token can actually reach.</li>
</ul>`,
  "mcp-connect": `<h1 id="connect-your-client"><a href="#connect-your-client">Connect your client</a></h1>
<div class="adh-mv-alert adh-mv-alert--note">
<p class="adh-mv-alert-title">Note</p>
<p>Mint an API token first: <code>POST /auth/tokens</code> with your JWT (or via the web
app's API-tokens screen). The raw value is shown <strong>once</strong>.</p>
</div>
<h2 id="claude-desktop"><a href="#claude-desktop">Claude Desktop</a></h2>
<p>Edit <code>~/Library/Application Support/Claude/claude_desktop_config.json</code> (macOS)
or <code>%APPDATA%\\Claude\\claude_desktop_config.json</code> (Windows). Restart Claude
Desktop.</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">{</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "mcpServers"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">    "agentic-developer-hub"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">      "type"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"streamable-http"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">      "url"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"https://mcp.agenticdeveloperhub.com/mcp"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">      "headers"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">        "Authorization"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"Bearer &#x3C;paste-token>"</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<h2 id="claude-code"><a href="#claude-code">Claude Code</a></h2>
<p>From the command line:</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">claude</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> mcp</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> add</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> --transport</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> http</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> agentic-developer-hub</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">  https://mcp.agenticdeveloperhub.com/mcp</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  --header</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "Authorization: Bearer &#x3C;paste-token>"</span></span></code></pre>
<h2 id="cursor"><a href="#cursor">Cursor</a></h2>
<p>Edit <code>~/.cursor/mcp.json</code> (or Cursor Settings \u2192 MCP). Restart Cursor.</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">{</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "mcpServers"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">    "agentic-developer-hub"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">      "url"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"https://mcp.agenticdeveloperhub.com/mcp"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">      "headers"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: {</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">        "Authorization"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"Bearer &#x3C;paste-token>"</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  }</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<h2 id="mcp-inspector"><a href="#mcp-inspector">MCP Inspector</a></h2>
<p>For debugging \u2014 a web UI that lets you call tools by hand:</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">npx</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> -y</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> @modelcontextprotocol/inspector</span></span></code></pre>
<p>Then connect with transport <code>streamable-http</code>, URL
<code>https://mcp.agenticdeveloperhub.com/mcp</code>, and an <code>Authorization: Bearer \u2026</code>
header.</p>`,
  "mcp-details": '<h1 id="details"><a href="#details">Details</a></h1>\n<table>\n<thead>\n<tr>\n<th></th>\n<th></th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><strong>Transport</strong></td>\n<td>Streamable HTTP (stateless)</td>\n</tr>\n<tr>\n<td><strong>Endpoint</strong></td>\n<td><code>POST https://mcp.agenticdeveloperhub.com/mcp</code></td>\n</tr>\n<tr>\n<td><strong>Auth</strong></td>\n<td><code>Authorization: Bearer &#x3C;api-token></code></td>\n</tr>\n<tr>\n<td><strong>Session</strong></td>\n<td>Stateless \u2014 each request re-validates the token</td>\n</tr>\n<tr>\n<td><strong>Data scope</strong></td>\n<td>Limited to the user the token belongs to</td>\n</tr>\n</tbody>\n</table>',
  "mcp-overview": `<h1 id="mcp-server"><a href="#mcp-server">MCP Server</a></h1>
<p>A Model Context Protocol endpoint. Your AI agent connects here over Streamable
HTTP and gets a curated set of tools to call against your authenticated data.</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>POST https://mcp.agenticdeveloperhub.com/mcp</span></span></code></pre>
<h2 id="what-this-is"><a href="#what-this-is">What this is</a></h2>
<p>MCP is a protocol for AI agents to discover and call tools on a server. It's a
sibling of the REST API, not a replacement.</p>
<h3 id="mcp--this-server"><a href="#mcp--this-server">MCP \u2014 this server</a></h3>
<ul>
<li>For LLM agents, not browsers</li>
<li>Single endpoint (<code>POST /mcp</code>)</li>
<li>JSON-RPC over HTTP</li>
<li>Tool discovery built in (<code>tools/list</code>)</li>
<li>Auth: <code>Authorization: Bearer &#x3C;api-token></code></li>
</ul>
<h3 id="rest-api"><a href="#rest-api">REST API</a></h3>
<ul>
<li>For humans and traditional clients</li>
<li>Resource-oriented (<code>/\u2026</code>)</li>
<li>OpenAPI 3.1 spec \u2014 see the <a href="/rest-api">API reference</a></li>
<li>Auth: JWT (email/password or OAuth)</li>
</ul>`,
  "mcp-tools": `<h1 id="tool-surface"><a href="#tool-surface">Tool surface</a></h1>
<p>54 tools, scoped to the user behind the API token. Revoke a token
to cut access immediately. Profile tools return only rows the acting agent has
been granted read access to via the data bucket ACL.</p>
<h2 id="persona-storage--19-tools"><a href="#persona-storage--19-tools">Persona Storage \xB7 19 tools</a></h2>
<p>Key/value, lists, counters, memory, events, queues, and keyword tags \u2014 agent-managed structured state.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>dataKvGet</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>dataKvSet</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataKvDelete</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataCounterGet</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>dataCounterIncr</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataListGet</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>dataListAppend</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataListRemove</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataMemoryGet</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>dataMemorySet</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataEventAppend</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataEventQuery</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>dataQueueEnqueue</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataQueueDequeue</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataQueueAck</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataQueueNack</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataKeywordTag</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataKeywordUntag</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>dataKeywordSearch</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="discussions--4-tools"><a href="#discussions--4-tools">Discussions \xB7 4 tools</a></h2>
<p>Search and browse the community forum.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>searchThreads</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>listCategories</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyBookmarks</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getRecentNotifications</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="profile--12-tools"><a href="#profile--12-tools">Profile \xB7 12 tools</a></h2>
<p>Your structured profile \u2014 jobs, education, locations, contacts, relationships, dates, tags, notes \u2014 plus categories and keyword lookups. Returns only rows the acting agent has been granted read access to via the data bucket ACL.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>getMyProfile</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyJobs</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyEducation</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyLocations</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyContacts</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyRelationships</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyTags</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getMyDates</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>searchMyNotes</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>searchMyData</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getCategoryContents</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>getKeywordsFor</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="personas--2-tools"><a href="#personas--2-tools">Personas \xB7 2 tools</a></h2>
<p>Discover personas visible to you.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>personasPersonaList</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>personasPersonaGet</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="teams--3-tools"><a href="#teams--3-tools">Teams \xB7 3 tools</a></h2>
<p>Administer the rosters of teams you manage \u2014 for an organization persona, the org-owned teams (list, add by email, remove).</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>teamMemberList</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>teamMemberAdd</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>teamMemberRemove</code></td>
<td>Write</td>
</tr>
</tbody>
</table>
<h2 id="monitored-sites--7-tools"><a href="#monitored-sites--7-tools">Monitored Sites \xB7 7 tools</a></h2>
<p>Manage uptime monitors for your sites and HTTP endpoints.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>monitoredSiteList</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>monitoredSiteAdd</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>monitoredSiteRemove</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>monitoredEndpointList</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>monitoredEndpointAdd</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>monitoredEndpointRemove</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>monitoredEndpointStatus</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="projects--6-tools"><a href="#projects--6-tools">Projects \xB7 6 tools</a></h2>
<p>List projects, their iterations and their work items, update a work item \u2014 including committing it to an iteration and sizing it \u2014 and post a comment: the agent write surface for the Projects feature (acts as the token subject).</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>projectListProjects</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>projectListIterations</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>projectListWorkItems</code></td>
<td>Read</td>
</tr>
<tr>
<td><code>projectUpdateWorkItem</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>projectAddComment</code></td>
<td>Write</td>
</tr>
<tr>
<td><code>projectListComments</code></td>
<td>Read</td>
</tr>
</tbody>
</table>
<h2 id="persona-knowledge--1-tools"><a href="#persona-knowledge--1-tools">Persona Knowledge \xB7 1 tools</a></h2>
<p>Full-text search over the acting persona's OWN knowledge corpus \u2014 the markdown rows referenced by a row-mode bucket type it has been granted read access to. Returns keyword-centred excerpts, never whole documents.</p>
<table>
<thead>
<tr>
<th>Tool</th>
<th>Access</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>searchPersonaKnowledge</code></td>
<td>Read</td>
</tr>
</tbody>
</table>`,
  "oauth-authorize": `<h1 id="2-send-the-user-to-authorize"><a href="#2-send-the-user-to-authorize">2. Send the user to authorize</a></h1>
<p>In this step your app redirects the user to the Agentic Developer Hub
authorization endpoint. The user signs in, sees a consent screen listing the
scopes you requested, and clicks <strong>Approve</strong>. We send them back to your
<code>redirect_uri</code> with a one-time <code>code</code> you'll exchange for tokens in
<a href="/quickstart/oauth/token-exchange">Step 3</a>.</p>
<h2 id="generate-a-pkce-pair"><a href="#generate-a-pkce-pair">Generate a PKCE pair</a></h2>
<p>PKCE protects against intercepted authorization codes. Generate a
<strong>verifier</strong> (random string you keep) and a <strong>challenge</strong> (SHA-256 of the
verifier, base64url-encoded) for every authorization request.</p>
<h3 id="typescript"><a href="#typescript">TypeScript</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">function</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> base64url</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">buf</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> ArrayBuffer</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">)</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> {</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  return</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> btoa</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(String.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">fromCharCode</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">...new</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> Uint8Array</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(buf)))</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    .</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">replace</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#032F62;--shiki-dark:#DBEDFF">=</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">g</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">''</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">).</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">replace</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#22863A;--shiki-light-font-weight:bold;--shiki-dark:#85E89D;--shiki-dark-font-weight:bold">\\+</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">g</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'-'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">).</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">replace</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#22863A;--shiki-light-font-weight:bold;--shiki-dark:#85E89D;--shiki-dark-font-weight:bold">\\/</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">/</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">g</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'_'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span>
<span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">async</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> function</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> generatePKCE</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">() {</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> bytes</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> crypto.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">getRandomValues</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">new</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> Uint8Array</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">32</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">));</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> verifier</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> base64url</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(bytes.buffer);</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> challenge</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> base64url</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">    await</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> crypto.subtle.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">digest</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'SHA-256'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">new</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> TextEncoder</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">().</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">encode</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(verifier))</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  );</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  return</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> { verifier, challenge };</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<h3 id="swift"><a href="#swift">Swift</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>import CryptoKit</span></span>
<span><span></span></span>
<span><span>extension Data {</span></span>
<span><span>    func base64URLEncoded() -> String {</span></span>
<span><span>        base64EncodedString()</span></span>
<span><span>            .replacingOccurrences(of: "+", with: "-")</span></span>
<span><span>            .replacingOccurrences(of: "/", with: "_")</span></span>
<span><span>            .replacingOccurrences(of: "=", with: "")</span></span>
<span><span>    }</span></span>
<span><span>}</span></span>
<span><span></span></span>
<span><span>func generatePKCE() -> (verifier: String, challenge: String) {</span></span>
<span><span>    var bytes = [UInt8](repeating: 0, count: 32)</span></span>
<span><span>    _ = SecRandomCopyBytes(kSecRandomDefault, 32, &#x26;bytes)</span></span>
<span><span>    let verifier = Data(bytes).base64URLEncoded()</span></span>
<span><span>    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()</span></span>
<span><span>    return (verifier, challenge)</span></span>
<span><span>}</span></span></code></pre>
<h3 id="kotlin"><a href="#kotlin">Kotlin</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>import java.security.MessageDigest</span></span>
<span><span>import java.security.SecureRandom</span></span>
<span><span>import java.util.Base64</span></span>
<span><span></span></span>
<span><span>fun generatePKCE(): Pair&#x3C;String, String> {</span></span>
<span><span>    val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }</span></span>
<span><span>    val verifier = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)</span></span>
<span><span>    val challenge = Base64.getUrlEncoder().withoutPadding().encodeToString(</span></span>
<span><span>        MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())</span></span>
<span><span>    )</span></span>
<span><span>    return verifier to challenge</span></span>
<span><span>}</span></span></code></pre>
<p>Store the <code>verifier</code> in the user's session \u2014 you'll need it for the token
exchange.</p>
<h2 id="redirect-the-user"><a href="#redirect-the-user">Redirect the user</a></h2>
<p>Build a URL with the <code>client_id</code>, the <code>redirect_uri</code>, the requested
<code>scope</code>s, a <code>state</code> parameter (random, anti-CSRF), and the PKCE
<code>code_challenge</code>.</p>
<h3 id="curl"><a href="#curl">curl</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">open</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "https://api.agenticdeveloperhub.com/api/oauth/signin/start</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">?client_id=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_ID</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;redirect_uri=https%3A%2F%2Fyour.app%2Fcallback</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;response_type=code</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;scope=profile%3Aread%20discussions%3Aread</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;state=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$RANDOM_STATE</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;code_challenge=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$PKCE_CHALLENGE</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">\\</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">&#x26;code_challenge_method=S256"</span></span></code></pre>
<h3 id="typescript-1"><a href="#typescript-1">TypeScript</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> url</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> new</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> URL</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'https://api.agenticdeveloperhub.com/api/oauth/signin/start'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'client_id'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, clientId);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'redirect_uri'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'https://your.app/callback'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'response_type'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'code'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'scope'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'profile:read discussions:read'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'state'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, state);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'code_challenge'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, challenge);</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">url.searchParams.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">set</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'code_challenge_method'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">, </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'S256'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">window.location.href </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">=</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> url.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">toString</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">();</span></span></code></pre>
<div class="adh-mv-alert adh-mv-alert--warning">
<p class="adh-mv-alert-title">Warning</p>
<p>The <code>state</code> parameter prevents CSRF attacks on the redirect. Generate a
fresh random string per request, store it in the user's session, and
<strong>reject</strong> the callback if the returned <code>state</code> doesn't match.</p>
</div>
<h2 id="handle-the-redirect"><a href="#handle-the-redirect">Handle the redirect</a></h2>
<p>After the user approves, we send them back to your <code>redirect_uri</code> with
<code>?code=\u2026&#x26;state=\u2026</code> query parameters.</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>https://your.app/callback?code=AUTH_CODE_HERE&#x26;state=SAME_STATE</span></span></code></pre>
<p>Verify the <code>state</code> matches what you stored, then exchange the <code>code</code> for
tokens in the next step.</p>
<h2 id="next"><a href="#next">Next</a></h2>
<p>\u2192 <a href="/quickstart/oauth/token-exchange">Step 3: Exchange the code for tokens</a></p>`,
  "oauth-overview": `<h1 id="oauth-overview"><a href="#oauth-overview">OAuth overview</a></h1>
<p>Use OAuth when your application acts <strong>on behalf of a user</strong> \u2014 reading their
data, posting on their behalf, or otherwise needing their explicit consent.</p>
<p>If you only need to authenticate your own server-to-server traffic, use a
personal <a href="/quickstart">API token</a> instead.</p>
<h2 id="the-flow-at-a-glance"><a href="#the-flow-at-a-glance">The flow at a glance</a></h2>
<p>The Agentic Developer Hub uses the standard OAuth 2.0 <strong>Authorization Code</strong>
flow with <strong>PKCE</strong>. Four steps:</p>
<ol>
<li><strong><a href="/quickstart/oauth/register-app">Register your app</a></strong> \u2014 get a <code>client_id</code>
and configure a <code>redirect_uri</code>.</li>
<li><strong><a href="/quickstart/oauth/authorize">Send the user to authorize</a></strong> \u2014 redirect the
user to <code>/api/oauth/signin/start</code>. They sign in and approve scopes.</li>
<li><strong><a href="/quickstart/oauth/token-exchange">Exchange the code for tokens</a></strong> \u2014 your
server POSTs the returned code to <code>/api/oauth/signin/exchange</code> and receives an
access token + refresh token.</li>
<li><strong><a href="/quickstart/oauth/refresh">Refresh when the token expires</a></strong> \u2014 exchange a
refresh token for a new access token at <code>/api/auth/refresh</code>.</li>
</ol>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>\u250C\u2500\u2500\u2500\u2500\u2500\u2500\u2510                \u250C\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510               \u250C\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510</span></span>
<span><span>\u2502 User \u2502                \u2502 Your    \u2502               \u2502 Agentic      \u2502</span></span>
<span><span>\u2502      \u2502                \u2502 App     \u2502               \u2502 Developer    \u2502</span></span>
<span><span>\u2502      \u2502                \u2502         \u2502               \u2502 Hub          \u2502</span></span>
<span><span>\u2514\u2500\u2500\u252C\u2500\u2500\u2500\u2518                \u2514\u2500\u2500\u2500\u2500\u252C\u2500\u2500\u2500\u2500\u2518               \u2514\u2500\u2500\u2500\u2500\u2500\u2500\u252C\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518</span></span>
<span><span>   \u2502                         \u2502                            \u2502</span></span>
<span><span>   \u2502  1. Click "Connect"     \u2502                            \u2502</span></span>
<span><span>   \u2502 \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u25BA\u2502                            \u2502</span></span>
<span><span>   \u2502                         \u2502                            \u2502</span></span>
<span><span>   \u2502                         \u2502 2. Redirect to /auth/start \u2502</span></span>
<span><span>   \u2502 \u25C4\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2524                            \u2502</span></span>
<span><span>   \u2502                                                      \u2502</span></span>
<span><span>   \u2502  3. Sign in &#x26; approve scopes                         \u2502</span></span>
<span><span>   \u2502 \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u25BA\u2502</span></span>
<span><span>   \u2502                                                      \u2502</span></span>
<span><span>   \u2502  4. Redirect back to your redirect_uri with ?code=\u2026  \u2502</span></span>
<span><span>   \u2502 \u25C4\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2502</span></span>
<span><span>   \u2502                         \u2502                            \u2502</span></span>
<span><span>   \u2502                         \u2502 5. POST /auth/exchange     \u2502</span></span>
<span><span>   \u2502                         \u2502     {code, code_verifier}  \u2502</span></span>
<span><span>   \u2502                         \u2502 \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u25BA\u2502</span></span>
<span><span>   \u2502                         \u2502                            \u2502</span></span>
<span><span>   \u2502                         \u2502 6. {access_token,          \u2502</span></span>
<span><span>   \u2502                         \u2502     refresh_token,         \u2502</span></span>
<span><span>   \u2502                         \u2502     expires_in}            \u2502</span></span>
<span><span>   \u2502                         \u2502 \u25C4\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2502</span></span>
<span><span>   \u2502                         \u2502                            \u2502</span></span></code></pre>
<h2 id="what-youll-need-before-you-start"><a href="#what-youll-need-before-you-start">What you'll need before you start</a></h2>
<ul>
<li>A registered application with a <code>client_id</code>. See
<a href="/quickstart/oauth/register-app">Register an app</a>.</li>
<li>A <code>redirect_uri</code> you control (an HTTPS URL on your domain, or
<code>http://localhost:&#x3C;port>/callback</code> during development).</li>
<li>A backend that can keep your <code>client_secret</code> server-side. The OAuth flow
itself uses PKCE so the secret never travels through the user's browser,
but anything you do post-token (refresh, revoke) must run server-side.</li>
</ul>
<h2 id="common-pitfalls"><a href="#common-pitfalls">Common pitfalls</a></h2>
<ul>
<li><strong>The redirect_uri must match exactly.</strong> Including the trailing slash, the
port, the scheme. The mismatch is the #1 reason <code>/auth/exchange</code> returns
<code>400</code>.</li>
<li><strong>PKCE <code>code_verifier</code> is required.</strong> This API rejects non-PKCE flows. See
<a href="/quickstart/oauth/authorize">Step 2</a> for how to generate the verifier and
challenge.</li>
<li><strong>Access tokens expire.</strong> Always handle the
<code>401 token_expired</code> response by refreshing \u2014 see
<a href="/quickstart/oauth/refresh">Step 4</a>.</li>
</ul>`,
  "oauth-refresh": `<h1 id="4-refresh-when-the-token-expires"><a href="#4-refresh-when-the-token-expires">4. Refresh when the token expires</a></h1>
<p>Access tokens expire after <code>expires_in</code> seconds (typically one hour). Use
the <code>refresh_token</code> from <a href="/quickstart/oauth/token-exchange">Step 3</a> to get a new
access token <strong>without</strong> redirecting the user again.</p>
<h2 id="when-to-refresh"><a href="#when-to-refresh">When to refresh</a></h2>
<p>Pick <strong>one</strong> strategy and stick to it:</p>
<ol>
<li><strong>Proactively</strong> \u2014 schedule a refresh ~60 seconds before <code>expires_in</code>.
Lower latency on the next call, but you must persist the expiry.</li>
<li><strong>Reactively</strong> \u2014 call the API normally, refresh on the first <code>401 token_expired</code>, and retry once.</li>
</ol>
<p>Reactive is simpler and good enough for most apps. Proactive is worth it
for latency-sensitive paths.</p>
<div class="adh-mv-alert adh-mv-alert--warning">
<p class="adh-mv-alert-title">Warning</p>
<p>The refresh endpoint is single-use: each refresh returns a <strong>new</strong>
<code>refresh_token</code> and invalidates the previous one. Persist the new token
atomically before using it.</p>
</div>
<h2 id="request"><a href="#request">Request</a></h2>
<h3 id="curl"><a href="#curl">curl</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">curl</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> -X</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> POST</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> https://api.agenticdeveloperhub.com/api/auth/refresh</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -H</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "Content-Type: application/json"</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -d</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> '{</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "grant_type": "refresh_token",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "refresh_token": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$REFRESH_TOKEN</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_id": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_ID</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_secret": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_SECRET</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'"</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">  }'</span></span></code></pre>
<h3 id="typescript"><a href="#typescript">TypeScript</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">async</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> function</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> refresh</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">refreshToken</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">) {</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> res</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> await</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> fetch</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    'https://api.agenticdeveloperhub.com/api/auth/refresh'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    {</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      method: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'POST'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      headers: { </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'Content-Type'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'application/json'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> },</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      body: </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">JSON</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">stringify</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">({</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">        grant_type: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'refresh_token'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">        refresh_token: refreshToken,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">        client_id: process.env.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">ADH_CLIENT_ID</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">        client_secret: process.env.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">ADH_CLIENT_SECRET</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      }),</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    },</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  );</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  if</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> (</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">res.ok) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">throw</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> new</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> Error</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'refresh failed \u2014 user must re-authorize'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">  return</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> (</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">await</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> res.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">json</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">()) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">as</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> {</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">    access_token</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">    refresh_token</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">    expires_in</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> number</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  };</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<h3 id="swift"><a href="#swift">Swift</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>struct RefreshRequest: Encodable {</span></span>
<span><span>    let grant_type = "refresh_token"</span></span>
<span><span>    let refresh_token: String</span></span>
<span><span>    let client_id: String</span></span>
<span><span>    let client_secret: String</span></span>
<span><span>}</span></span>
<span><span>// POST /api/auth/refresh \u2014 same shape as exchange, see Step 3.</span></span></code></pre>
<h3 id="kotlin"><a href="#kotlin">Kotlin</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>@Serializable</span></span>
<span><span>data class RefreshRequest(</span></span>
<span><span>    val grant_type: String = "refresh_token",</span></span>
<span><span>    val refresh_token: String,</span></span>
<span><span>    val client_id: String,</span></span>
<span><span>    val client_secret: String,</span></span>
<span><span>)</span></span>
<span><span>// POST /api/auth/refresh \u2014 same shape as exchange, see Step 3.</span></span></code></pre>
<h2 id="response"><a href="#response">Response</a></h2>
<p>Identical shape to <a href="/quickstart/oauth/token-exchange">Step 3</a>:</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">{</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "access_token"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"adh_eyJhbGciOi..."</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "refresh_token"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"adh_rt_NEW..."</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "expires_in"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">3600</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "token_type"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"Bearer"</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<p><strong>Replace</strong> both stored tokens with the values from this response.</p>
<h2 id="when-refresh-fails"><a href="#when-refresh-fails">When refresh fails</a></h2>
<p>A <code>400 invalid_grant</code> from <code>/api/auth/refresh</code> means the refresh token is
no longer valid \u2014 either revoked, expired, or already used. There's no
silent recovery: send the user through the authorization flow again,
starting from <a href="/quickstart/oauth/authorize">Step 2</a>.</p>
<h2 id="revoking-tokens"><a href="#revoking-tokens">Revoking tokens</a></h2>
<p>To proactively log a user out (e.g., they uninstalled your app), POST the
refresh token to <code>/api/auth/revoke</code>:</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">curl</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> -X</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> POST</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> https://api.agenticdeveloperhub.com/api/auth/revoke</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -H</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "Content-Type: application/json"</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -d</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> '{</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "token": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$REFRESH_TOKEN</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_id": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_ID</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_secret": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_SECRET</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'"</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">  }'</span></span></code></pre>
<h2 id="youre-done"><a href="#youre-done">You're done</a></h2>
<p>That's the full OAuth flow. Verify your integration end-to-end:</p>
<ol>
<li>Start the flow \u2192 user approves \u2192 you receive <code>code</code>.</li>
<li>Exchange <code>code</code> \u2192 you get tokens \u2192 call <code>/api/auth/me</code> to confirm.</li>
<li>Wait for expiry (or force one for testing) \u2192 refresh \u2192 call <code>/api/auth/me</code>
again with the new token.</li>
</ol>
<p>If you hit a snag, the <a href="https://api.agenticdeveloperhub.com">API reference</a>
has every endpoint's exact request/response schema.</p>`,
  "oauth-register-app": `<h1 id="1-register-your-app"><a href="#1-register-your-app">1. Register your app</a></h1>
<p>Before you can run the OAuth flow you need a registered application. The
app's <code>client_id</code> identifies you to the authorization server; its registered
<code>redirect_uri</code> is the only URL we'll send users back to after they approve.</p>
<h2 id="steps"><a href="#steps">Steps</a></h2>
<ol>
<li>Sign in at <a href="https://temporal.today">temporal.today</a>.</li>
<li>Open <strong>Settings \u2192 Developer \u2192 OAuth apps</strong>.</li>
<li>Click <strong>New OAuth app</strong> and fill in:
<ul>
<li><strong>Name</strong> \u2014 shown to users on the consent screen.</li>
<li><strong>Homepage URL</strong> \u2014 your product's marketing or app URL.</li>
<li><strong>Redirect URIs</strong> \u2014 every URL the authorization server may redirect to
after approval. Add one per environment (production, staging, local
development).</li>
</ul>
</li>
<li>After saving you'll see:
<ul>
<li><code>client_id</code> \u2014 public, safe to embed in your client.</li>
<li><code>client_secret</code> \u2014 keep server-side. <strong>Shown once</strong> \u2014 copy it to your
secret store immediately.</li>
</ul>
</li>
</ol>
<div class="adh-mv-alert adh-mv-alert--warning">
<p class="adh-mv-alert-title">Warning</p>
<p>If you lose the <code>client_secret</code>, you can rotate it from the same screen.
Rotation invalidates the previous secret immediately.</p>
</div>
<h2 id="local-development"><a href="#local-development">Local development</a></h2>
<p>Add <code>http://localhost:&#x3C;port>/callback</code> (whatever your local server uses) as
an allowed redirect URI. The authorization server allows <code>http://localhost</code>
URIs as a special case; HTTPS is required for every other host.</p>
<h2 id="scopes"><a href="#scopes">Scopes</a></h2>
<p>When you initiate the authorization request, you'll ask for one or more
<strong>scopes</strong>. Request the narrowest set of scopes your app actually needs.</p>
<p>Common scopes (full catalogue lives on the consent screen):</p>
<table>
<thead>
<tr>
<th>Scope</th>
<th>What it grants</th>
</tr>
</thead>
<tbody>
<tr>
<td><code>profile:read</code></td>
<td>Read the authenticated user's profile</td>
</tr>
<tr>
<td><code>discussions:read</code></td>
<td>Read forum threads / replies / DMs</td>
</tr>
<tr>
<td><code>discussions:write</code></td>
<td>Post replies, react, send DMs</td>
</tr>
<tr>
<td><code>integrations:manage</code></td>
<td>Connect third-party providers</td>
</tr>
</tbody>
</table>
<div class="adh-mv-alert adh-mv-alert--note">
<p class="adh-mv-alert-title">Note</p>
<p>The exact scope list is still evolving \u2014 confirm against the consent screen
shown during <a href="/quickstart/oauth/authorize">Step 2</a> when you build your
integration.</p>
</div>
<h2 id="next"><a href="#next">Next</a></h2>
<p>You've got a <code>client_id</code> and a <code>client_secret</code>.
\u2192 <a href="/quickstart/oauth/authorize">Step 2: Send the user to authorize</a></p>`,
  "oauth-token-exchange": `<h1 id="3-exchange-the-code-for-tokens"><a href="#3-exchange-the-code-for-tokens">3. Exchange the code for tokens</a></h1>
<p>You have an authorization <code>code</code> and a PKCE <code>verifier</code> from
<a href="/quickstart/oauth/authorize">Step 2</a>. Exchange them for an access token and
refresh token by POSTing to <code>/api/oauth/signin/exchange</code>.</p>
<div class="adh-mv-alert adh-mv-alert--warning">
<p class="adh-mv-alert-title">Warning</p>
<p>This call must happen on your <strong>server</strong>, not in the user's browser. The
<code>client_secret</code> is included in the request and must never leak to the
client.</p>
</div>
<h2 id="request"><a href="#request">Request</a></h2>
<h3 id="curl"><a href="#curl">curl</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">curl</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> -X</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> POST</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> https://api.agenticdeveloperhub.com/api/oauth/signin/exchange</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -H</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "Content-Type: application/json"</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -d</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> '{</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "grant_type": "authorization_code",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "code": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$AUTH_CODE</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "redirect_uri": "https://your.app/callback",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_id": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_ID</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "client_secret": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ADH_CLIENT_SECRET</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'",</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">    "code_verifier": "'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$PKCE_VERIFIER</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'"</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">  }'</span></span></code></pre>
<h3 id="typescript"><a href="#typescript">TypeScript</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> res</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> await</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0"> fetch</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">(</span></span>
<span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">  'https://api.agenticdeveloperhub.com/api/oauth/signin/exchange'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  {</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    method: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'POST'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    headers: { </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'Content-Type'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'application/json'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> },</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    body: </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">JSON</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">stringify</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">({</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      grant_type: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'authorization_code'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      code,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      redirect_uri: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">'https://your.app/callback'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      client_id: process.env.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">ADH_CLIENT_ID</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      client_secret: process.env.</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">ADH_CLIENT_SECRET</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">!</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">      code_verifier: verifier,</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">    }),</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">  },</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">);</span></span>
<span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">const</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> tokens</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583"> =</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> (</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">await</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> res.</span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">json</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">()) </span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">as</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8"> {</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">  access_token</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">  refresh_token</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> string</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">  expires_in</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> number</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#E36209;--shiki-dark:#FFAB70">  token_type</span><span style="--shiki-light:#D73A49;--shiki-dark:#F97583">:</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> 'Bearer'</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">;</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">};</span></span></code></pre>
<h3 id="swift"><a href="#swift">Swift</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>struct ExchangeRequest: Encodable {</span></span>
<span><span>    let grant_type = "authorization_code"</span></span>
<span><span>    let code: String</span></span>
<span><span>    let redirect_uri: String</span></span>
<span><span>    let client_id: String</span></span>
<span><span>    let client_secret: String</span></span>
<span><span>    let code_verifier: String</span></span>
<span><span>}</span></span>
<span><span>struct TokenResponse: Decodable {</span></span>
<span><span>    let access_token: String</span></span>
<span><span>    let refresh_token: String</span></span>
<span><span>    let expires_in: Int</span></span>
<span><span>    let token_type: String</span></span>
<span><span>}</span></span>
<span><span></span></span>
<span><span>let payload = ExchangeRequest(</span></span>
<span><span>    code: code,</span></span>
<span><span>    redirect_uri: "myapp://oauth/callback",</span></span>
<span><span>    client_id: "your-client-id",</span></span>
<span><span>    client_secret: "your-client-secret",</span></span>
<span><span>    code_verifier: codeVerifier</span></span>
<span><span>)</span></span>
<span><span>var req = URLRequest(url: URL(string: "https://api.agenticdeveloperhub.com/api/oauth/signin/exchange")!)</span></span>
<span><span>req.httpMethod = "POST"</span></span>
<span><span>req.setValue("application/json", forHTTPHeaderField: "Content-Type")</span></span>
<span><span>req.httpBody = try JSONEncoder().encode(payload)</span></span>
<span><span>let (data, _) = try await URLSession.shared.data(for: req)</span></span>
<span><span>let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)</span></span></code></pre>
<h3 id="kotlin"><a href="#kotlin">Kotlin</a></h3>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span>@Serializable</span></span>
<span><span>data class ExchangeRequest(</span></span>
<span><span>    val grant_type: String = "authorization_code",</span></span>
<span><span>    val code: String,</span></span>
<span><span>    val redirect_uri: String,</span></span>
<span><span>    val client_id: String,</span></span>
<span><span>    val client_secret: String,</span></span>
<span><span>    val code_verifier: String,</span></span>
<span><span>)</span></span>
<span><span>@Serializable</span></span>
<span><span>data class TokenResponse(</span></span>
<span><span>    val access_token: String,</span></span>
<span><span>    val refresh_token: String,</span></span>
<span><span>    val expires_in: Int,</span></span>
<span><span>    val token_type: String,</span></span>
<span><span>)</span></span>
<span><span></span></span>
<span><span>val request = ExchangeRequest(</span></span>
<span><span>    code = code,</span></span>
<span><span>    redirect_uri = "https://your.app/callback",</span></span>
<span><span>    client_id = "your-client-id",</span></span>
<span><span>    client_secret = "your-client-secret",</span></span>
<span><span>    code_verifier = codeVerifier,</span></span>
<span><span>)</span></span>
<span><span>val tokens: TokenResponse = client.post("https://api.agenticdeveloperhub.com/api/oauth/signin/exchange") {</span></span>
<span><span>    contentType(ContentType.Application.Json)</span></span>
<span><span>    setBody(request)</span></span>
<span><span>}.body()</span></span></code></pre>
<h2 id="response"><a href="#response">Response</a></h2>
<p>A successful exchange returns:</p>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">{</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "access_token"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"adh_eyJhbGciOi..."</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "refresh_token"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"adh_rt_8f1a2..."</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "expires_in"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">3600</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "token_type"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"Bearer"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">,</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  "scope"</span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">: </span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"profile:read discussions:read"</span></span>
<span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">}</span></span></code></pre>
<ul>
<li><code>access_token</code> \u2014 use as <code>Authorization: Bearer &#x3C;token></code> on every API
request. Treat as sensitive; do not log it.</li>
<li><code>refresh_token</code> \u2014 store <strong>server-side, encrypted</strong>. Used to get a new
access token without re-prompting the user.</li>
<li><code>expires_in</code> \u2014 seconds until the access token expires (typically one
hour). Refresh <strong>before</strong> it expires to avoid races.</li>
</ul>
<h2 id="errors"><a href="#errors">Errors</a></h2>
<table>
<thead>
<tr>
<th>HTTP</th>
<th><code>error</code></th>
<th>Cause</th>
</tr>
</thead>
<tbody>
<tr>
<td>400</td>
<td><code>invalid_grant</code></td>
<td>Code already used, expired (60s TTL), or wrong <code>redirect_uri</code></td>
</tr>
<tr>
<td>400</td>
<td><code>invalid_request</code></td>
<td>Missing or malformed parameter</td>
</tr>
<tr>
<td>401</td>
<td><code>invalid_client</code></td>
<td>Wrong <code>client_id</code> / <code>client_secret</code></td>
</tr>
<tr>
<td>401</td>
<td><code>invalid_verifier</code></td>
<td>PKCE <code>code_verifier</code> doesn't match the original challenge</td>
</tr>
</tbody>
</table>
<p>See <a href="/reference/errors">Errors</a> for the response body shape.</p>
<h2 id="use-the-access-token"><a href="#use-the-access-token">Use the access token</a></h2>
<pre style="--shiki-light:#24292e;--shiki-dark:#e1e4e8;--shiki-light-bg:#fff;--shiki-dark-bg:#24292e"><code><span><span style="--shiki-light:#6F42C1;--shiki-dark:#B392F0">curl</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> https://api.agenticdeveloperhub.com/api/auth/me</span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF"> \\</span></span>
<span><span style="--shiki-light:#005CC5;--shiki-dark:#79B8FF">  -H</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF"> "Authorization: Bearer </span><span style="--shiki-light:#24292E;--shiki-dark:#E1E4E8">$ACCESS_TOKEN</span><span style="--shiki-light:#032F62;--shiki-dark:#9ECBFF">"</span></span></code></pre>
<h2 id="next"><a href="#next">Next</a></h2>
<p>\u2192 <a href="/quickstart/oauth/refresh">Step 4: Refresh when the token expires</a></p>`,
  "webhooks": `<h1 id="webhooks"><a href="#webhooks">Webhooks</a></h1>
<div class="adh-mv-alert adh-mv-alert--note">
<p class="adh-mv-alert-title">Note</p>
<p>The public webhooks API is on the roadmap. The backend already serves
internal webhook receivers at <code>/api/webhooks/*</code> (Postmark, Stripe, etc.) \u2014
those are intentionally hidden from the public API reference because the
sender is the third party, not your application.</p>
</div>
<h2 id="what-will-be-available"><a href="#what-will-be-available">What will be available</a></h2>
<p>When the outbound webhooks ship, you'll be able to:</p>
<ul>
<li>Register webhook subscriptions per OAuth app (one or more URLs).</li>
<li>Filter events by type (e.g., <code>discussion.thread.created</code>,
<code>integration.connected</code>).</li>
<li>Verify deliveries with an HMAC signature in the
<code>X-AgenticDeveloperHub-Signature</code> header.</li>
<li>Replay recent deliveries from the dashboard.</li>
</ul>
<h2 id="until-then"><a href="#until-then">Until then</a></h2>
<p>If your use case needs realtime updates, the WebSocket endpoint at
<code>/ws/discussions</code> already broadcasts most user-facing events (replies,
reactions, notifications, DMs, presence). It is documented in the
description block of the <a href="https://api.agenticdeveloperhub.com">API reference</a>.</p>`
};

// src/help/views/MarkdownTopic.tsx
import { jsx as jsx3 } from "react/jsx-runtime";
function MarkdownTopic({ contentKey }) {
  const { open } = useHelp();
  const html = HELP_CONTENT_HTML[contentKey];
  function onDocLinkClick(e) {
    if (e.defaultPrevented || isModifiedClick(e)) return;
    const anchor = e.target.closest("a");
    if (!anchor || anchor.target === "_blank") return;
    const href = anchor.getAttribute("href") ?? "";
    if (!href.startsWith("/")) return;
    const slug = href.replace(/^\//, "").replace(/[?#].*$/, "");
    const topic = topicBySlug(slug);
    if (!topic) return;
    e.preventDefault();
    open(topic.id);
  }
  return /* @__PURE__ */ jsx3("div", { className: "adh-help-topic adh-help-topic--markdown", onClick: onDocLinkClick, children: html == null ? /* @__PURE__ */ jsx3("p", { className: "adh-help-topic__missing", children: "This topic has no content yet." }) : /* @__PURE__ */ jsx3(MarkdownHtml, { html }) });
}

// src/help/views/ApiTopic.tsx
import { ApiBrowser } from "@agentic-toolkit/api-explorer";
import { jsx as jsx4 } from "react/jsx-runtime";
function ApiTopic() {
  return /* @__PURE__ */ jsx4("div", { className: "adh-help-topic adh-help-topic--api", children: /* @__PURE__ */ jsx4(ApiBrowser, {}) });
}

// src/help/views/ChatTopic.tsx
import { jsx as jsx5, jsxs } from "react/jsx-runtime";
var HELP_CHAT_URL = "https://help.agenticdeveloperhub.com/chat";
function ChatTopic() {
  return /* @__PURE__ */ jsx5("div", { className: "adh-help-topic adh-help-topic--chat", children: /* @__PURE__ */ jsx5(EmptyChatCta, {}) });
}
function EmptyChatCta() {
  return /* @__PURE__ */ jsxs("div", { className: "flex flex-col items-center gap-2 text-center", children: [
    /* @__PURE__ */ jsx5("p", { children: "Chat with bitbag, the Agentic Developer Hub assistant." }),
    /* @__PURE__ */ jsx5("a", { href: HELP_CHAT_URL, target: "_blank", rel: "noreferrer", className: "adh-help-topic__link", children: "Open the chat \u2192" })
  ] });
}

// src/help/HelpWindow.tsx
import { jsx as jsx6 } from "react/jsx-runtime";
function topicView(topic) {
  if (!topic) {
    return /* @__PURE__ */ jsx6(EmptyState, { className: "m-4", title: "No topic selected", description: "Choose a help topic to get started." });
  }
  if (topic.view === "api") return /* @__PURE__ */ jsx6(ApiTopic, {});
  if (topic.view === "chat") return /* @__PURE__ */ jsx6(ChatTopic, {});
  if (topic.contentKey) return /* @__PURE__ */ jsx6(MarkdownTopic, { contentKey: topic.contentKey });
  return /* @__PURE__ */ jsx6(EmptyState, { className: "m-4", title: topic.label, description: topic.description ?? "Choose a subtopic." });
}
function HelpWindow({
  open,
  onClose,
  path,
  onPathChange
}) {
  const { levels, leaf } = useMemo(() => {
    const { levels: data, activeTopic } = buildTopicLevels(path);
    const tlevels = data.map((level, depth) => ({
      id: level.parentId == null ? "help-root" : `help:${level.parentId}`,
      title: level.title,
      // Same topic glyphs as the SSR site rail (topicIcon by topic id), so the modal and the
      // standalone help site stay in lockstep down to the row icons — never HMDV's neutral ring.
      items: level.items.map((it) => ({
        id: it.id,
        label: it.label,
        description: it.description,
        icon: topicIcon(it.id)
      })),
      selectedId: level.selectedId,
      // Select at this depth → replace this level's choice and clear everything deeper.
      onSelect: (id) => onPathChange([...path.slice(0, depth), id]),
      // Clear this level and below (re-click, breadcrumb up, Back).
      onClear: () => onPathChange(path.slice(0, depth))
    }));
    return { levels: tlevels, leaf: topicView(activeTopic) };
  }, [path, onPathChange]);
  return /* @__PURE__ */ jsx6(FloatingWindow, { open, onClose, title: "Help", children: /* @__PURE__ */ jsx6("div", { className: "flex min-h-0 min-w-0 flex-1 flex-col", children: /* @__PURE__ */ jsx6(
    HierarchicalDetailView,
    {
      levels,
      rootLabel: "Help",
      disclosureStyle: "cascading",
      autoHideTopics: true,
      exitGuard: null,
      children: leaf
    }
  ) }) });
}
export {
  HelpWindow
};
//# sourceMappingURL=HelpWindow.js.map