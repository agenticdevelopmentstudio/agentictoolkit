import { describe, it, expect } from "vitest";
import { createHmac } from "node:crypto";
import { verifyVercelSignature, verifySharedSecret } from "../src/monitor/webhook-verify";

describe("verifyVercelSignature", () => {
  it("accepts a correct HMAC-SHA1 signature", () => {
    const secret = "s3cr3t";
    const body = '{"type":"deployment.succeeded"}';
    const sig = createHmac("sha1", secret).update(body).digest("hex");
    expect(verifyVercelSignature(body, sig, secret)).toBe(true);
  });

  it("rejects a wrong signature", () => {
    const secret = "s3cr3t";
    const body = '{"type":"deployment.succeeded"}';
    expect(verifyVercelSignature(body, "deadbeef", secret)).toBe(false);
  });

  it("rejects a null signature", () => {
    expect(verifyVercelSignature("body", null, "secret")).toBe(false);
  });

  it("rejects an empty secret", () => {
    const body = "body";
    const sig = createHmac("sha1", "s").update(body).digest("hex");
    expect(verifyVercelSignature(body, sig, "")).toBe(false);
  });
});

describe("verifySharedSecret", () => {
  it("accepts a matching secret", () => {
    expect(verifySharedSecret("my-secret", "my-secret")).toBe(true);
  });

  it("rejects a wrong secret", () => {
    expect(verifySharedSecret("wrong", "my-secret")).toBe(false);
  });

  it("rejects null provided", () => {
    expect(verifySharedSecret(null, "my-secret")).toBe(false);
  });

  it("rejects empty configured secret (fails closed)", () => {
    expect(verifySharedSecret("anything", "")).toBe(false);
  });
});
