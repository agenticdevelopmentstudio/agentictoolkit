---
id: 2df97a02-a680-45c4-8763-f07c7f470f84
title: Status Server Monitor Webhook Verify
domain: agentictoolkit://recipes/status-server-monitor-webhook-verify
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "Constant-time verification of a Vercel HMAC-SHA1 webhook signature and a Railway shared-secret webhook header; both fail closed on any missing piece."
platforms:
- typescript
- web
tags:
- monitor
- webhook
- security
- server
depends-on:
- agenticdevelopercookbook://principles/separation-of-concerns
- agenticdevelopercookbook://principles/fail-fast
related:
- agentictoolkit://recipes/status-server-monitor-webhook-events
references:
- packages/web/packages/status-server/src/monitor/webhook-verify.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/hooks.ts (agentictoolkit)
- packages/web/packages/status-server/test/webhook-verify.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Webhook Verify

## Overview

`webhook-verify.ts` (`packages/web/packages/status-server/src/monitor/webhook-verify.ts`) exports two functions — `verifyVercelSignature` and `verifySharedSecret` — built on one module-private helper, `safeEqual`. Together they authenticate the two inbound webhook shapes the status server's `hooks.ts` routes accept before any part of the request body is parsed or trusted: Vercel's signed deploy-event webhook, whose `x-vercel-signature` header carries the hex HMAC-SHA1 digest of the raw request body, and Railway's unsigned webhook, which instead carries a caller-supplied secret to be compared against the one configured for that deployment. `hooksRoutes` calls `verifyVercelSignature` to gate `POST /hooks/vercel` and `verifySharedSecret` to gate `POST /hooks/railway`, throwing an `HTTPException(401, ...)` in the caller whenever either function returns `false`. Both exported functions are synchronous, take only primitive `string`/`string | null | undefined` parameters, and return a plain `boolean`.

## Behavioral Requirements

### Constant-Time String Comparison (`safeEqual`)

- **length-mismatch-short-circuits**: `safeEqual` MUST return `false` without invoking `timingSafeEqual` when the UTF-8 byte length of `a` differs from the UTF-8 byte length of `b`, per its own doc comment ("never throws on length mismatch") and its `if (ab.length !== bb.length) return false;` guard — `node:crypto`'s `timingSafeEqual` otherwise throws a `RangeError` on buffers of unequal length.
- **equal-length-constant-time-compare**: When `a` and `b` encode to equal-length UTF-8 byte buffers, `safeEqual` MUST compare them using `node:crypto`'s `timingSafeEqual` and MUST return exactly the boolean that call produces.
- **utf8-byte-comparison**: `safeEqual` MUST encode both `a` and `b` as UTF-8 (`Buffer.from(a, "utf8")` / `Buffer.from(b, "utf8")`) before comparing, so the comparison is case-sensitive and normalization-sensitive: two strings differing only in letter case MUST be treated as unequal.

### Vercel HMAC-SHA1 Signature Verification (`verifyVercelSignature`)

- **missing-signature-rejected**: `verifyVercelSignature` MUST return `false` without computing any digest when `signature` is `null`, `undefined`, or the empty string (the `!signature` guard).
- **missing-secret-rejected**: `verifyVercelSignature` MUST return `false` without computing any digest when `secret` is the empty string (the `!secret` guard).
- **hmac-sha1-hex-digest**: When both `signature` and `secret` are truthy, `verifyVercelSignature` MUST compute the expected value as the HMAC-SHA1 digest of `rawBody`, keyed by `secret`, hex-encoded (`createHmac("sha1", secret).update(rawBody).digest("hex")`).
- **signature-compared-via-safe-equal**: `verifyVercelSignature` MUST return the result of comparing its computed expected digest against `signature` using `safeEqual`, never a plain `===` comparison.
- **raw-body-precondition**: per the function's own doc comment, the caller MUST supply `rawBody` exactly as received on the wire, never re-serialized; the function itself performs no parsing, decoding, or re-encoding of `rawBody` before hashing it, so a caller that re-serializes the body before this call changes the computed digest and breaks verification. This is a caller precondition the function's contract states directly, not input this function validates itself.

### Shared-Secret Verification (`verifySharedSecret`)

- **missing-provided-rejected**: `verifySharedSecret` MUST return `false` without comparison when `provided` is `null`, `undefined`, or the empty string (the `!provided` guard).
- **missing-configured-secret-fails-closed**: `verifySharedSecret` MUST return `false` when `secret` is the empty string (the `!secret` guard), regardless of the value of `provided` — an unset or misconfigured secret MUST NOT be treated as a match for any input.
- **provided-compared-via-safe-equal**: When both `provided` and `secret` are truthy, `verifySharedSecret` MUST return the result of comparing `provided` against `secret` using `safeEqual`.

### Cross-Cutting Contract

- **pure-synchronous-no-side-effects**: Both `verifyVercelSignature` and `verifySharedSecret` MUST be synchronous, MUST return a plain `boolean` (never a `Promise`), and MUST perform no I/O, no logging, and no mutation of any shared or module-level state.
- **no-throw-contract**: Neither exported function MUST throw for any combination of its documented parameter types (`string`, `string | null | undefined`); every failure path returns `false` rather than raising an exception.
- **independent-calls-no-shared-state**: The module declares no module-level mutable state; concurrent or repeated calls to either exported function MUST NOT interact with, block, or influence one another's outcome, since each call reads only its own parameters.

## Appearance

Not applicable — this is a server-side webhook signature and shared-secret verification function, not a visual component.

## States

Not applicable — this is a server-side webhook signature and shared-secret verification function, not a visual component; its only outcomes (accept or reject, per input) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side webhook signature and shared-secret verification function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-webhook-verify-001 | hmac-sha1-hex-digest, signature-compared-via-safe-equal | `secret = "s3cr3t"`; `body = '{"type":"deployment.succeeded"}'`; `sig = createHmac("sha1", secret).update(body).digest("hex")`; call `verifyVercelSignature(body, sig, secret)` | Returns `true` — `webhook-verify.test.ts` › "accepts a correct HMAC-SHA1 signature" |
| status-server-monitor-webhook-verify-002 | length-mismatch-short-circuits, signature-compared-via-safe-equal | Same `secret`/`body` as above; call `verifyVercelSignature(body, "deadbeef", secret)` | Returns `false` — the 8-character literal and the 40-character sha1 hex digest differ in length, so the length-mismatch guard rejects before any `timingSafeEqual` call — `webhook-verify.test.ts` › "rejects a wrong signature" |
| status-server-monitor-webhook-verify-003 | missing-signature-rejected | Call `verifyVercelSignature("body", null, "secret")` | Returns `false` with no digest computed — `webhook-verify.test.ts` › "rejects a null signature" |
| status-server-monitor-webhook-verify-004 | missing-secret-rejected | `body = "body"`; `sig = createHmac("sha1", "s").update(body).digest("hex")`; call `verifyVercelSignature(body, sig, "")` | Returns `false` even though `sig` is a well-formed digest — the empty-secret guard rejects before any comparison — `webhook-verify.test.ts` › "rejects an empty secret" |
| status-server-monitor-webhook-verify-005 | provided-compared-via-safe-equal | Call `verifySharedSecret("my-secret", "my-secret")` | Returns `true` — `webhook-verify.test.ts` › "accepts a matching secret" |
| status-server-monitor-webhook-verify-006 | provided-compared-via-safe-equal, length-mismatch-short-circuits | Call `verifySharedSecret("wrong", "my-secret")` | Returns `false` — the two strings differ in byte length, so the length-mismatch guard rejects them before any `timingSafeEqual` call — `webhook-verify.test.ts` › "rejects a wrong secret" |
| status-server-monitor-webhook-verify-007 | missing-provided-rejected | Call `verifySharedSecret(null, "my-secret")` | Returns `false` — `webhook-verify.test.ts` › "rejects null provided" |
| status-server-monitor-webhook-verify-008 | missing-configured-secret-fails-closed | Call `verifySharedSecret("anything", "")` | Returns `false` even though `"anything"` is non-empty — an unset configured secret never matches — `webhook-verify.test.ts` › "rejects empty configured secret (fails closed)" |
| status-server-monitor-webhook-verify-009 | pure-synchronous-no-side-effects, no-throw-contract | Static read of `webhook-verify.ts`'s exported function signatures and bodies | Both `verifyVercelSignature` and `verifySharedSecret` are declared to return a plain `boolean` (not a `Promise`), take no `async`/`await`, and the file contains no `try`/`catch` of any kind — not directly asserted by `webhook-verify.test.ts`, traced to the function declarations and bodies in source |
| status-server-monitor-webhook-verify-010 | raw-body-precondition | Static read of `verifyVercelSignature`'s doc comment and body | The doc comment states the body must be "passed EXACTLY as received (do not re-serialize)"; the implementation applies `createHmac(...).update(rawBody)` directly to the `rawBody` argument with no `JSON.parse`/`JSON.stringify` round-trip — not exercised by a dedicated assertion in `webhook-verify.test.ts`, traced to the source doc comment and implementation |

## Edge Cases

- **Null and empty input**: `signature` of `null`, `undefined`, or `''` MUST be rejected with no digest computed (missing-signature-rejected) — MUST. `provided` of `null`, `undefined`, or `''` MUST be rejected with no comparison (missing-provided-rejected) — MUST. `secret` of `''` for either function MUST reject regardless of the other argument, fail-closed rather than fail-open (missing-secret-rejected, missing-configured-secret-fails-closed) — MUST. An empty `rawBody` (`''`) is not specially guarded — it simply HMACs to the fixed digest that empty input produces for the given `secret`, like any other input.
- **Boundary values**: a byte-length mismatch between the two strings any comparison handles — the computed hex digest versus the `signature` header, or `provided` versus `secret` — MUST short-circuit to `false` inside `safeEqual` before `timingSafeEqual` is ever called (length-mismatch-short-circuits), avoiding the `RangeError` that function throws on mismatched-length buffers — MUST. A case difference between the (always-lowercase) computed hex digest and a differently-cased `signature` value is also treated as unequal, since the comparison is a literal UTF-8 byte compare rather than a decoded-hex compare (utf8-byte-comparison) — MUST.
- **Concurrent access**: not applicable in the shared-mutable-state sense — the module declares no state of its own, so two or more concurrent or overlapping calls to either function simply run independent, self-contained comparisons that cannot interact (independent-calls-no-shared-state) — MUST.
- **Error states**: this file has no external dependency of its own — no network call, no database, no file system — so a dependency being unavailable is a fact about the CALLER (e.g. `hooks.ts`'s raw-body read, or the configuration lookup that produces `secret`), external to this file's own contract; within this file, every input combination resolves to a `boolean` with no error state of its own (no-throw-contract) — MUST.
- **Offline / disconnected state**: not applicable — this file makes no network call and has no connectivity of its own to lose; that concern belongs entirely to whichever caller already fetched `rawBody`, `signature`, `provided`, and `secret` before invoking these functions.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rawBody` (parameter to `verifyVercelSignature`) | `string` | none — caller-supplied, required | The raw HTTP request body text, exactly as received, per the function's own doc comment. |
| `signature` (parameter to `verifyVercelSignature`) | `string \| null \| undefined` | none — caller-supplied | The `x-vercel-signature` header value. `null`, `undefined`, or `''` fails verification. |
| `secret` (parameter to `verifyVercelSignature`) | `string` | none — caller-supplied, required | The Vercel webhook secret to key the HMAC-SHA1 digest with. `hooks.ts` passes `config.webhooks.vercel`, throwing an `HTTPException(503, ...)` before calling this function when that value is unset. `''` fails verification. |
| `provided` (parameter to `verifySharedSecret`) | `string \| null \| undefined` | none — caller-supplied | The secret value presented by the caller (e.g. Railway's `?token=` query parameter or `x-webhook-secret` header, read by `hooks.ts`). `null`, `undefined`, or `''` fails verification. |
| `secret` (parameter to `verifySharedSecret`) | `string` | none — caller-supplied, required | The configured secret to compare `provided` against. `hooks.ts` passes `config.webhooks.railway`, throwing an `HTTPException(503, ...)` before calling this function when that value is unset. `''` fails verification (fails closed). |

## Deep Linking

Not applicable: this file defines no application URL scheme, route, or deep link of its own — it only verifies a signature or secret a caller has already received over HTTP.

## Localization

Not applicable: this file has no user-facing strings — both exported functions return only a `boolean`, with no thrown error message, log line, or other text output of any kind.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system — whether verification runs at all, and which secret it checks against, is decided entirely by the caller (`hooks.ts`'s own `if (!secret) throw` gate ahead of each call).

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind — its only observable output is the `boolean` each function returns.

## Privacy

- **Data collected**: none of this file's own data. Each function receives a caller-supplied credential — the webhook secret (`config.webhooks.vercel` or `config.webhooks.railway`) — plus a caller-supplied `rawBody`/`signature`/`provided` value, purely as function parameters for a single in-memory comparison.
- **Storage**: none. Neither function persists, caches, or otherwise retains the secret, signature, or body beyond the synchronous call; the module holds no variable across calls.
- **Transmission**: none. This file makes no network call and writes no output beyond its `boolean` return value; the secret and signature never leave the process through this file.
- **Retention**: not applicable — nothing outlives the synchronous call that received it; there is no history, cache, or reference to a past verification anywhere in this module.

## Logging

Not applicable: this file contains no log call of any kind, `console.error` or otherwise. A failed verification is communicated only through the `boolean` `false` return value; the caller (`hooks.ts`) decides whether and how to log or respond to that outcome (it throws an `HTTPException(401, ...)`, which its own error handler shapes into a response, external to this file).

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern would model both functions as free, synchronous, non-throwing functions returning `Bool`, built on CryptoKit's `HMAC<Insecure.SHA1>` for the digest and its own constant-time comparison — `Data`'s `==` operator is NOT constant-time in Swift, so a port needs an explicit fixed-time byte compare (or `CryptoKit`'s `SymmetricKey`-based helpers) to reproduce `safeEqual`'s guarantee, plus the same length-check-before-compare shape this source uses.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the two functions as plain, synchronous, non-throwing functions returning `Boolean`, computing the digest with `javax.crypto.Mac.getInstance("HmacSHA1")` and comparing with `java.security.MessageDigest.isEqual`, which the JDK documents as running in time depending only on the length of the arrays — the same constant-time guarantee `timingSafeEqual` provides here, and it likewise requires no manual length pre-check since it accepts differing lengths safely.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/webhook-verify.ts` on the Node status backend, built on `node:crypto`'s `createHmac` and `timingSafeEqual` — Node-specific APIs with no browser or Web Crypto equivalent used here. Its two callers, `hooksRoutes`' `/hooks/vercel` and `/hooks/railway` handlers in `routes/hooks.ts`, both call the relevant function synchronously before parsing the request body, and both convert a `false` result into an `HTTPException(401, ...)`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no framework-specific concern beyond what the SwiftUI bullet already covers — the comparison itself is CryptoKit-level, not view-layer; on deployment targets predating CryptoKit, `CommonCrypto`'s `CCHmac` is the equivalent HMAC-SHA1 primitive.
- **WinUI 3**: a .NET port models `verifyVercelSignature`/`verifySharedSecret` as `static bool` methods (no `Task`/`async`, matching pure-synchronous-no-side-effects), computing the digest with `System.Security.Cryptography.HMACSHA1` keyed by the UTF-8 bytes of `secret` (`System.Text.Encoding.UTF8.GetBytes`) and hashing the UTF-8 bytes of `rawBody`. The digest MUST be lowercased before comparison: `Convert.ToHexString` produces uppercase hex by default, while Node's `.digest("hex")` is always lowercase, and because this file's comparison is a literal byte/string compare (utf8-byte-comparison) rather than a decoded-hex compare, an un-lowercased .NET digest would never match a genuine signature. For the constant-time compare, `System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(ReadOnlySpan<byte>, ReadOnlySpan<byte>)` is the direct analogue of `timingSafeEqual` — and unlike `timingSafeEqual`, .NET's `FixedTimeEquals` already returns `false` safely for spans of differing length, so a WinUI 3 port needs no separate length-mismatch guard (length-mismatch-short-circuits) the way this TypeScript source does. No `HttpClient`, `Windows.Storage`, `ObservableCollection`, or `INotifyPropertyChanged` apply: this file has no network, persistence, or UI-bound state of its own.

## Design Decisions

- **Decision**: guard for equal byte length before calling `node:crypto`'s `timingSafeEqual`, returning `false` immediately on a mismatch, rather than calling `timingSafeEqual` directly on both inputs.
  **Rationale**: stated in `safeEqual`'s own doc comment — "never throws on length mismatch." Node's `timingSafeEqual` throws a `RangeError` when given buffers of different lengths; guarding first turns what would otherwise be an uncaught exception into an ordinary rejected verification, so a malformed or short `x-vercel-signature` header (or shared-secret value) produces a clean `401` rather than crashing the request handler.
  **Approved**: pending
- **Decision**: `verifySharedSecret` returns `false`, never `true`, when the CONFIGURED `secret` parameter is the empty string — independent of whatever `provided` value is passed.
  **Rationale**: stated directly in the source doc comment — "An empty/unset configured secret never matches — so a misconfigured deployment fails closed rather than open." Without this guard, an operator who forgot to set `RAILWAY_WEBHOOK_SECRET` would inadvertently accept any (or no) value as valid, turning a missing-configuration bug into an open, unauthenticated webhook endpoint.
  **Approved**: pending
- **Decision**: compare the hex-encoded digest against `signature` (and `provided` against `secret`) as raw UTF-8 byte representations via `safeEqual`, not as decoded hex bytes or case-normalized values.
  **Rationale**: not stated in the source's comments; recorded here as an observed, deliberate fact. `createHmac(...).digest("hex")` always produces lowercase hex, and the comparison is a literal string/byte compare, so a signature header value in a different case would be rejected even though it decodes to the same bytes. This is the file's actual behavior, and a port MUST reproduce the case-sensitive comparison unless it also normalizes both sides identically before comparing.
  **Approved**: pending
- **Decision**: `verifyVercelSignature`'s contract checks only that the HMAC-SHA1 of the raw body matches — it carries no timestamp, nonce, or replay window of its own.
  **Rationale**: the function's own doc comment defines the complete contract — "`x-vercel-signature` is the hex HMAC-SHA1 of the RAW request body keyed by the webhook secret" — with no timestamp or nonce component described, because Vercel's own header carries none. There is nothing for this file to check that the upstream header does not itself carry; any replay protection would be a property of the provider's webhook design, not an omission in this function's stated contract.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`separation-of-concerns` passes: this file's only concern is comparing caller-supplied strings; it never fetches the raw body itself, never reads configuration or environment variables, and never decides which route or header carries the signature or secret — those decisions live entirely in `hooks.ts`, external to this file. `unit-test-coverage` passes: `webhook-verify.test.ts` exercises every branch of both exported functions — the accepting case, a rejected wrong signature/secret (which also exercises `safeEqual`'s length-mismatch guard, since the wrong values used are shorter than their correct counterparts), a `null` `signature`/`provided`, and an empty configured `secret` for both functions. `explicit-error-handling` passes: every failure path — a missing signature, a missing or empty secret, a length mismatch, or a digest/secret that does not match — returns `false` explicitly rather than throwing, resolving ambiguously, or being silently swallowed; the caller (`hooks.ts`) then throws its own `HTTPException(401, ...)` on that `false`, so the fail-closed boolean this file returns is what the caller's status code is actually built on.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
