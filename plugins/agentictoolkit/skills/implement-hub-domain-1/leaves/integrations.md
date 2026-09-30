<!-- leaf: implement-hub-domain-1/integrations · source: hub-domain-integrations.md -->

# Hub Domain: Integrations

## Overview

`integrations.ts` and `wire.ts`, re-exported by `index.ts`, are the client for the `/api/integrations`
surface, per the module's own top-of-file comment. It covers three things: the provider CATALOG
(`listProviders`, every provider the platform can integrate, with its `authMethod` and capabilities);
an ecosystem's own, owner-scoped provider CONFIGS (OAuth client credentials or a GitHub App's identity,
plus optional endpoint overrides, addressed two different ways — by `providerId` and by the config's own
`id`/`rdid`); and an ecosystem's CONNECTIONS (linked accounts) — list, connect (all six `ConnectRequestBody`
auth methods), disconnect, sync-now, per-connection sync settings, plus the OAuth/app-install/self-hosted-
instance/Plaid-Link start endpoints and a local, non-authoritative decoder for the signed OAuth `state`
round-trip value. `wire.ts` holds the wire shapes; `integrations.ts` holds the `integrationsApi` object of
twenty request-builder methods plus the standalone `OAUTH_CALLBACK_PATH`/`oauthCallbackUrl`/
`decodeOAuthStateClaims`/`isOAuthStateFresh` exports, all built on the shared `authedJson`/`authedRequest`
helpers from `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc`
(`encodeURIComponent`, from `./client-helpers`). It is a headless **logic** module — no visual surface — so
this recipe marks Appearance, States, and Accessibility not applicable and carries the runtime contract
entirely in Behavioral Requirements, per the non-UI component guidance this recipe was authored under.

