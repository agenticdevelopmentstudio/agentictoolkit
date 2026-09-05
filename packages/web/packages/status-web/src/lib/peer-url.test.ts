// The peer base-URL rules the editor enforces client-side. They exist to match the
// backend exactly, so the cases below are the backend's cases: a stored URL is trimmed
// and slash-free, and only an absolute http(s) URL is accepted.
import { describe, expect, it } from "vitest";
import { isValidPeerBaseUrl, normalizePeerBaseUrl } from "./peer-url";

describe("normalizePeerBaseUrl", () => {
  it("trims surrounding whitespace and every trailing slash", () => {
    expect(normalizePeerBaseUrl("  https://b.example.com/// ")).toBe("https://b.example.com");
  });

  it("leaves an already-canonical URL alone", () => {
    expect(normalizePeerBaseUrl("https://b.example.com")).toBe("https://b.example.com");
  });

  it("keeps a path but drops its trailing slash", () => {
    expect(normalizePeerBaseUrl("https://b.example.com/status/")).toBe("https://b.example.com/status");
  });

  // The unique index on base_url is byte-exact, so anything that varies without
  // changing WHICH monitor is meant has to fold away here, or the same peer is
  // pollable — and drawable on the fleet board — twice.
  it("folds case, the default port, and query/fragment into one canonical form", () => {
    const canonical = "https://b.example.com";
    expect(normalizePeerBaseUrl("HTTPS://B.Example.COM")).toBe(canonical);
    expect(normalizePeerBaseUrl("https://b.example.com:443")).toBe(canonical);
    expect(normalizePeerBaseUrl("https://b.example.com/?x=1#frag")).toBe(canonical);
    expect(normalizePeerBaseUrl("http://b.example.com:80")).toBe("http://b.example.com");
  });

  it("keeps a NON-default port — it names a different monitor", () => {
    expect(normalizePeerBaseUrl("http://localhost:3000/")).toBe("http://localhost:3000");
  });

  it("leaves an unparseable string trimmed rather than throwing", () => {
    // The editor normalizes every keystroke, so this runs on half-typed input.
    expect(normalizePeerBaseUrl("  b.example.com/ ")).toBe("b.example.com");
  });
});

describe("isValidPeerBaseUrl", () => {
  it("accepts absolute http and https URLs", () => {
    expect(isValidPeerBaseUrl("https://b.example.com")).toBe(true);
    expect(isValidPeerBaseUrl("http://localhost:3000")).toBe(true);
    // Normalization runs first, so an un-canonical-but-valid URL still passes.
    expect(isValidPeerBaseUrl("  https://b.example.com/ ")).toBe(true);
  });

  it("rejects a bare host, a relative path, and the empty string", () => {
    expect(isValidPeerBaseUrl("b.example.com")).toBe(false);
    expect(isValidPeerBaseUrl("/relative")).toBe(false);
    expect(isValidPeerBaseUrl("")).toBe(false);
  });

  it("rejects non-http(s) schemes — a peer is polled over HTTP, nothing else", () => {
    expect(isValidPeerBaseUrl("ftp://b.example.com")).toBe(false);
    expect(isValidPeerBaseUrl("javascript:alert(1)")).toBe(false);
    expect(isValidPeerBaseUrl("file:///etc/passwd")).toBe(false);
  });
});
