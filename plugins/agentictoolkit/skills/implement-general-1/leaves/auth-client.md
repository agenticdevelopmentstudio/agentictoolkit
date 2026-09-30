<!-- leaf: implement-general-1/auth-client · source: auth-client.md -->

# Auth Client

## Overview

The `auth-client` ingredient is the web SPA's headless authentication layer:
eleven dependency-free TypeScript modules under
`packages/web/packages/auth/src/` (`account-security.ts`, `asBase.ts`,
`client.ts`, `config.ts`, `labels.ts`, `mfa.ts`, `refresh.ts`, `report.ts`,
`sso.ts`, `tokens.ts`, `types.ts`) that together give a brand site a
Bearer-token session backed by an HttpOnly refresh cookie, cross-site single
sign-on against a shared authorization server (the AS), MFA/WebAuthn
completion (both at login time and in self-serve account security), and a
Bearer-authed fetch wrapper the rest of the app builds on. It has no visual
surface of its own — every UI component in the auth family (login forms,
callback pages, account-security screens) is a consumer of this contract, not
part of it.

