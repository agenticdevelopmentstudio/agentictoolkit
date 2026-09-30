<!-- leaf: implement-status-server-monitor-2/webhook-verify · source: status-server-monitor-webhook-verify.md -->

**Rules** (cite as `implement-status-server-monitor-2/webhook-verify#<slug>`):

- `length-mismatch-short-circuits` MUST
- `equal-length-constant-time-compare` MUST
- `utf8-byte-comparison` MUST
- `missing-signature-rejected` MUST
- `missing-secret-rejected` MUST
- `hmac-sha1-hex-digest` MUST
- `signature-compared-via-safe-equal` MUST
- `raw-body-precondition` MUST
- `missing-provided-rejected` MUST
- `missing-configured-secret-fails-closed` MUST
- `provided-compared-via-safe-equal` MUST
- `pure-synchronous-no-side-effects` MUST
- `no-throw-contract` MUST
- `independent-calls-no-shared-state` MUST
- `winui-3` MUST — a .NET port models verifyVercelSignature/verifySharedSecret as static bool methods (no Task/async, matching …

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rawBody` (parameter to `verifyVercelSignature`) | `string` | none — caller-supplied, required | The raw HTTP request body text, exactly as received, per the function's own doc comment. |
| `signature` (parameter to `verifyVercelSignature`) | `string \| null \| undefined` | none — caller-supplied | The `x-vercel-signature` header value. `null`, `undefined`, or `''` fails verification. |
| `secret` (parameter to `verifyVercelSignature`) | `string` | none — caller-supplied, required | The Vercel webhook secret to key the HMAC-SHA1 digest with. `hooks.ts` passes `config.webhooks.vercel`, throwing an `HTTPException(503, ...)` before calling this function when that value is unset. `''` fails verification. |
| `provided` (parameter to `verifySharedSecret`) | `string \| null \| undefined` | none — caller-supplied | The secret value presented by the caller (e.g. Railway's `?token=` query parameter or `x-webhook-secret` header, read by `hooks.ts`). `null`, `undefined`, or `''` fails verification. |
| `secret` (parameter to `verifySharedSecret`) | `string` | none — caller-supplied, required | The configured secret to compare `provided` against. `hooks.ts` passes `config.webhooks.railway`, throwing an `HTTPException(503, ...)` before calling this function when that value is unset. `''` fails verification (fails closed). |

## Privacy

- **Data collected**: none of this file's own data. Each function receives a caller-supplied credential — the webhook secret (`config.webhooks.vercel` or `config.webhooks.railway`) — plus a caller-supplied `rawBody`/`signature`/`provided` value, purely as function parameters for a single in-memory comparison.
- **Storage**: none. Neither function persists, caches, or otherwise retains the secret, signature, or body beyond the synchronous call; the module holds no variable across calls.
- **Transmission**: none. This file makes no network call and writes no output beyond its `boolean` return value; the secret and signature never leave the process through this file.
- **Retention**: not applicable — nothing outlives the synchronous call that received it; there is no history, cache, or reference to a past verification anywhere in this module.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this pattern would model both functions as free, synchronous, non-throwing functions returning `Bool`, built on CryptoKit's `HMAC<Insecure.SHA1>` for the digest and its own constant-time comparison — `Data`'s `==` operator is NOT constant-time in Swift, so a port needs an explicit fixed-time byte compare (or `CryptoKit`'s `SymmetricKey`-based helpers) to reproduce `safeEqual`'s guarantee, plus the same length-check-before-compare shape this source uses.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the two functions as plain, synchronous, non-throwing functions returning `Boolean`, computing the digest with `javax.crypto.Mac.getInstance("HmacSHA1")` and comparing with `java.security.MessageDigest.isEqual`, which the JDK documents as running in time depending only on the length of the arrays — the same constant-time guarantee `timingSafeEqual` provides here, and it likewise requires no manual length pre-check since it accepts differing lengths safely.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/webhook-verify.ts` on the Node status backend, built on `node:crypto`'s `createHmac` and `timingSafeEqual` — Node-specific APIs with no browser or Web Crypto equivalent used here. Its two callers, `hooksRoutes`' `/hooks/vercel` and `/hooks/railway` handlers in `routes/hooks.ts`, both call the relevant function synchronously before parsing the request body, and both convert a `false` result into an `HTTPException(401, ...)`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no framework-specific concern beyond what the SwiftUI bullet already covers — the comparison itself is CryptoKit-level, not view-layer; on deployment targets predating CryptoKit, `CommonCrypto`'s `CCHmac` is the equivalent HMAC-SHA1 primitive.
- **WinUI 3**: a .NET port models `verifyVercelSignature`/`verifySharedSecret` as `static bool` methods (no `Task`/`async`, matching pure-synchronous-no-side-effects), computing the digest with `System.Security.Cryptography.HMACSHA1` keyed by the UTF-8 bytes of `secret` (`System.Text.Encoding.UTF8.GetBytes`) and hashing the UTF-8 bytes of `rawBody`. The digest MUST be lowercased before comparison: `Convert.ToHexString` produces uppercase hex by default, while Node's `.digest("hex")` is always lowercase, and because this file's comparison is a literal byte/string compare (utf8-byte-comparison) rather than a decoded-hex compare, an un-lowercased .NET digest would never match a genuine signature. For the constant-time compare, `System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(ReadOnlySpan<byte>, ReadOnlySpan<byte>)` is the direct analogue of `timingSafeEqual` — and unlike `timingSafeEqual`, .NET's `FixedTimeEquals` already returns `false` safely for spans of differing length, so a WinUI 3 port needs no separate length-mismatch guard (length-mismatch-short-circuits) the way this TypeScript source does. No `HttpClient`, `Windows.Storage`, `ObservableCollection`, or `INotifyPropertyChanged` apply: this file has no network, persistence, or UI-bound state of its own.

