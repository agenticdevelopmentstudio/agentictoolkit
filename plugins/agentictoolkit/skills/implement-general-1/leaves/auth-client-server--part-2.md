<!-- leaf: implement-general-1/auth-client-server--part-2 · source: auth-client-server.md -->

# Auth Client-Server Proxy — continued (part 2)

## Design Decisions

- **Decision**: Force `redirect: 'manual'` on every backend fetch.
  **Rationale**: OpenNext-on-Cloudflare-Workers' default fetch follows a 302
  automatically and drops the `Set-Cookie` header the backend's OAuth flow
  depends on; `manual` hands the 3xx and its `Set-Cookie` to the browser
  untouched. Vercel's rewrite-based sites don't need this, but the source
  makes no distinction — it always sets `manual`.
  **Approved**: pending
- **Decision**: Force outbound `accept-encoding: identity`, discarding the
  browser's own value.
  **Rationale**: Node's `undici` fetch implementation transparently decodes a
  gzip/deflate response body but leaves the upstream `content-encoding: gzip`
  response header in place; because this module returns that response
  verbatim, forwarding the browser's real `Accept-Encoding` made the browser
  receive a body that was already decoded but still labeled compressed, and
  its own `fetch` rejected with a TypeError — the reported symptom was the
  sign-in callback page's "Could not reach the sign-in service" on every
  sign-in. Requesting `identity` upstream removes the mismatch entirely; a
  CDN in front of the browser can still compress on the way out.
  **Approved**: pending
- **Decision**: Map the `'api'` prefix to the backend root instead of a
  literal `/api/...` path, while the `'auth'` prefix keeps its segment.
  **Rationale**: the backend already dropped its own `/api` route prefix, so
  re-adding it here would 404 every request; the backend's Hydra OIDC routes
  are still mounted at `/auth/...`, so that prefix is preserved verbatim.
  **Approved**: pending
- **Decision**: implement this pass-through as a Next.js Route Handler rather
  than a `next.config` rewrite.
  **Rationale**: a rewrite can't preserve auth on every hosting tier —
  specifically OpenNext on Cloudflare Workers, per the redirect decision
  above; Vercel-hosted sites that rewrite via `next.config` don't need this
  file at all.
  **Approved**: pending
