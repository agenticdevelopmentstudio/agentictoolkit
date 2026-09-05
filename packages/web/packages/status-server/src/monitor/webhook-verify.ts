import { createHmac, timingSafeEqual } from "node:crypto";

/** Constant-time string compare that never throws on length mismatch. */
function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

/**
 * Verify a Vercel webhook: `x-vercel-signature` is the hex HMAC-SHA1 of the RAW
 * request body keyed by the webhook secret. Pass the body EXACTLY as received
 * (do not re-serialize). Returns false on any missing piece.
 */
export function verifyVercelSignature(
  rawBody: string,
  signature: string | null | undefined,
  secret: string,
): boolean {
  if (!signature || !secret) return false;
  const expected = createHmac("sha1", secret).update(rawBody).digest("hex");
  return safeEqual(expected, signature);
}

/**
 * Verify an unsigned webhook (e.g. Railway) by comparing a caller-supplied secret
 * against the configured one, constant-time. An empty/unset configured secret
 * never matches — so a misconfigured deployment fails closed rather than open.
 */
export function verifySharedSecret(provided: string | null | undefined, secret: string): boolean {
  if (!provided || !secret) return false;
  return safeEqual(provided, secret);
}
