<!-- leaf: implement-status-server/routes--part-5 · source: status-server-routes.md -->

# Status Server Routes — continued (part 5)

## Platform Notes

- **TypeScript / Node (source)**: the routes are `Hono`/`OpenAPIHono`
  sub-apps composed by factory functions taking `storage`/`config`/
  `scheduler` as explicit parameters (dependency injection over module-level
  singletons), validated with Zod, and returning either a JSON body, an SSE
  `ReadableStream`, or an SVG string.
- **Swift (SwiftUI/AppKit/UIKit hosts)**: a client consuming this contract
  polls `/live`, `/snapshot`, or `/status` on a timer or subscribes to
  `/live/stream` via `URLSession`'s bytes-streaming API to parse SSE frames
  incrementally; the device-authorization flow (`/auth/device` →
  `/auth/device/token` polling) maps naturally onto an `AsyncSequence`-driven
  poll loop with the same `slow_down`/`authorization_pending` back-off
  handling the route itself expects.
- **Kotlin (Jetpack Compose hosts)**: the same SSE stream is consumed via
  OkHttp's `EventSource` (or a manual chunked-response reader) feeding a
  `StateFlow`; the device-flow poll loop is a `Flow` emitting on
  `POLL_INTERVAL_SEC` with the same three-state RFC 8628 error handling.
- **C# / WinUI 3**: a WinUI 3 host is a *client* of this contract, not a
  reimplementation of the server — it would use `HttpClient` for the
  JSON endpoints, `System.Text.Json` for (de)serializing the same DTOs this
  file returns, and a background `Task` looping on `HttpClient.GetAsync`
  against `/live/stream`'s chunked response (or a `System.Net.Http`
  SSE-parsing helper) to feed an `ObservableCollection`/`INotifyPropertyChanged`-
  backed view model, mirroring the subscribe-then-render-opening-frame
  ordering this route enforces server-side. A minted device-flow or API
  token would be persisted client-side via `Windows.Storage`'s credential
  vault, never in a plain settings file. If this route layer itself were
  ever reimplemented on .NET (not just consumed), the Hono
  route-factory/middleware-chain shape maps onto ASP.NET Core minimal APIs
  or controllers for routing, `System.Text.Json` + `FluentValidation` (or
  `DataAnnotations`) in place of Zod, `IHostedService`/`HttpResponse`
  streaming in place of the SSE `ReadableStream`, `HMACSHA1` from
  `System.Security.Cryptography` for the Vercel webhook signature, ASP.NET
  Core's rate-limiting middleware in place of `rateLimit`, and ASP.NET Core
  Identity plus a custom bearer-token `AuthenticationHandler` in place of the
  cookie/session/token middleware chain.
- **Web client**: the dashboard's own frontend is the reference client —
  it opens `EventSource`/`fetch`-based SSE against `/live/stream`, polls
  `/auth/device/token` during device-flow sign-in, and treats every
  `HTTPException` response's `{ error: { message } }` envelope uniformly.

## Design Decisions

- **Decision**: keep the auto-configure matching/creation engine
  (`@agentic-toolkit/deploy-platform/engine`) HTTP-agnostic; the route
  talks to it only through the in-process `statusAdapter`.
  **Rationale**: the engine is reused outside the HTTP layer and stays
  independently testable against a fake `StatusAddApi` without spinning up
  a server.
  **Approved**: pending

- **Decision**: model webhook ownership as a three-state result
  (`owned`/`not-owned`/`unknown`) with `unknown` failing closed to 503,
  rather than a boolean.
  **Rationale**: collapsing "the roster read failed" into "not owned" would
  silently drop a legitimate deploy event during a storage outage; 503
  tells the provider to retry once storage recovers.
  **Approved**: pending

- **Decision**: coalesce concurrent reconcile passes in `hooksRoutes` with a
  single-flight-plus-queued-flag gate rather than letting each webhook
  trigger its own independent reconcile.
  **Rationale**: a burst of webhooks (a multi-service deploy) would
  otherwise fan out into redundant, overlapping board derivations; the
  queued-flag pattern still guarantees every arrival is covered by some
  pass.
  **Approved**: pending

- **Decision**: exclude error-type Problems from `/status/snapshot`'s
  public/anonymous-reachable response.
  **Rationale**: an error Problem's `name`/`detail` carry internal GlitchTip
  project identifiers and raw exception titles that should not be
  disclosed to anonymous or peer callers; this is treated as a decision to
  make deliberately, not an accident of omission.
  **Approved**: pending

- **Decision**: gate `auto-configure.ts` and `board.ts`'s reconcile route
  with `requireAdmin` per-route, while `config.ts`, `users.ts`, and
  `cron.ts` apply it blanket via `app.use('*', ...)`.
  **Rationale**: the former two sub-apps are mounted alongside other,
  non-admin routes at a shared base path; the latter three are entirely
  admin-only sub-apps, so a blanket gate is both correct and simpler there.
  **Approved**: pending

- **Decision**: let `DELETE /tokens/:id` bypass the `requireAdmin`
  middleware in favor of a hand-rolled `isAdmin || isSelf` check.
  **Rationale**: a token must be able to revoke itself as a kill switch
  regardless of its own role; `requireAdmin` alone cannot express "or is the
  target of the call," so the route intentionally does not use it here.
  **Approved**: pending

- **Decision**: leave `/hooks/cloudflare` unimplemented.
  **Rationale**: Cloudflare has no per-deploy webhook to receive, so a route
  would have nothing to verify or dispatch; the existing poll cycle already
  covers Cloudflare deploy status. Documented in source as approved by the
  project owner on 2026-06-26.
  **Approved**: pending

- **Decision**: let `POST /cron/refresh` await its triggered cycle while
  `POST /live/check` triggers its cycle detached (`runNowDetached`).
  **Rationale**: the cron endpoint is called by an external scheduler that
  wants confirmation the cycle ran; the manual "check now" button is
  called from a request a human is actively waiting on and should return
  immediately, with the scheduler's own single-flight covering overlap.
  **Approved**: pending
