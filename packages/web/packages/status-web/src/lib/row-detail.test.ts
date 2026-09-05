import { describe, it, expect } from "vitest";
import type { Row } from "./row-model";
import { rowToDetailProps, rowDetailToText } from "./row-detail";

function row(o: Partial<Row>): Row {
  return {
    key: "k", source: "vercel", platform: "vercel", name: "adh", environment: "production",
    statusWord: "deployed", tone: "good", sha: null, commitUrl: null, message: null,
    detail: null, at: "2026-06-04T18:00:00.000Z", sourceUrl: null, liveUrl: null, commitBody: null,
    ...o,
  };
}

describe("rowToDetailProps", () => {
  it("maps a deploy row to endpoint/platform/commit fields", () => {
    const d = rowToDetailProps(row({
      name: "adh", statusWord: "built", platform: "vercel", environment: "production",
      sourceUrl: "https://vercel.com/team/adh/dpl", liveUrl: "https://adh.app",
      sha: "abc1234", commitUrl: "https://github.com/o/r/commit/abc1234def",
      message: "fix login", commitBody: "fix login\n\nlonger body",
    }));
    expect(d.title).toBe("adh");
    // Deploy title links to the deployment page (sourceUrl first), matching StatusRow.
    expect(d.titleUrl).toBe("https://vercel.com/team/adh/dpl");
    expect(d.platformText).toBe("built on vercel");
    expect(d.platformLink).toBe("https://vercel.com/team/adh/dpl");
    expect(d.commitSubject).toBe("fix login");
    expect(d.commitBody).toBe("fix login\n\nlonger body");
    expect(d.problem).toBeNull();
  });

  it("uses the checked host as the title for endpoint (http) rows and exposes the problem", () => {
    const d = rowToDetailProps(row({
      platform: "http", name: "App", statusWord: "down", detail: "HTTP 503",
      liveUrl: "https://x.example.com/health", sourceUrl: "https://x.example.com/health",
    }));
    expect(d.title).toBe("x.example.com");
    expect(d.platformText).toBeNull(); // endpoints carry no "built on <platform>"
    expect(d.problem).toBe("HTTP 503");
    expect(d.problemLink).toBe("https://x.example.com/health");
  });

  it("suppresses the platform phrase for resolved issues", () => {
    const d = rowToDetailProps(row({ platform: "vercel", statusWord: "[deploy failed] resolved" }));
    expect(d.platformText).toBeNull();
  });

  it("drops the problem field when it merely repeats the commit subject", () => {
    // Deploy-status issues set detail = the commit's first line (== message).
    const d = rowToDetailProps(row({
      platform: "vercel", statusWord: "deploy failed", detail: "fix login", message: "fix login",
      sha: "abc1234", commitUrl: "https://github.com/o/r/commit/abc1234def",
    }));
    expect(d.problem).toBeNull();
    expect(d.commitSubject).toBe("fix login");
  });

  it("surfaces endpoint diagnostics: status code, response time, down-since, last check", () => {
    const d = rowToDetailProps(row({
      platform: "http", name: "App", statusWord: "down", detail: "conn refused",
      liveUrl: "https://x.example.com/health", sourceUrl: "https://x.example.com/health",
      statusCode: 503, responseTimeMs: 1200,
      downSince: "2026-06-04T17:00:00.000Z", lastCheckedAt: "2026-06-04T18:05:00.000Z",
    }));
    expect(d.statusCode).toBe(503);
    expect(d.responseTime).toBe("1200ms");
    expect(d.since).toBe("2026-06-04T17:00:00.000Z"); // server-truth down-since wins
    expect(d.lastChecked).toBe("2026-06-04T18:05:00.000Z");
  });

  it("surfaces the deploy branch", () => {
    const d = rowToDetailProps(row({ platform: "vercel", statusWord: "deploy failed", branch: "main" }));
    expect(d.branch).toBe("main");
  });

  it("falls back to the row event time for `since` and nulls absent diagnostics", () => {
    const d = rowToDetailProps(row({ at: "2026-06-04T18:00:00.000Z" }));
    expect(d.since).toBe("2026-06-04T18:00:00.000Z");
    expect(d.statusCode).toBeNull();
    expect(d.responseTime).toBeNull();
    expect(d.branch).toBeNull();
    expect(d.lastChecked).toBeNull();
    expect(d.errorText).toBeNull();
  });

  it("carries the provider failure reason (errorText) through to the detail", () => {
    const d = rowToDetailProps(row({ platform: "vercel", statusWord: "build failed", errorText: "[buildStep] next build exited 1" }));
    expect(d.errorText).toBe("[buildStep] next build exited 1");
  });

  it("derives the deploy outcome from the row tone — settled deploys only", () => {
    expect(rowToDetailProps(row({ tone: "bad", statusWord: "build failed" })).deployOutcome).toBe("failed");
    expect(rowToDetailProps(row({ tone: "good", statusWord: "deployed" })).deployOutcome).toBe("success");
    expect(rowToDetailProps(row({ tone: "progress", statusWord: "building" })).deployOutcome).toBeNull();
    // Endpoint rows and resolved issues never get a build/deploy headline.
    expect(rowToDetailProps(row({ platform: "http", statusWord: "down", tone: "bad" })).deployOutcome).toBeNull();
    expect(rowToDetailProps(row({ statusWord: "[deploy failed] resolved", tone: "good" })).deployOutcome).toBeNull();
    // Crunchy rows are DB-cluster health mapped onto deploy phases — a suspended
    // cluster must not read "build / deploy FAILED".
    expect(rowToDetailProps(row({ platform: "crunchy", source: "crunchy", statusWord: "suspended", tone: "bad" })).deployOutcome).toBeNull();
  });
});

describe("rowDetailToText", () => {
  it("serializes a deploy failure into labeled, LLM-pasteable text incl. the logs link", () => {
    const txt = rowDetailToText(
      rowToDetailProps(
        row({
          platform: "vercel", name: "olylo.ai-production", statusWord: "build failed",
          environment: "production", branch: "production",
          sourceUrl: "https://vercel.com/team/olylo/dpl123",
          sha: "9f952c9", message: "restructure repo",
          commitBody: "restructure repo\n\nlonger detail",
          at: "2026-07-09T10:37:00.000Z",
        }),
      ),
    );
    expect(txt).toContain("platform: build failed on vercel");
    expect(txt).toContain("environment: production");
    expect(txt).toContain("branch: production");
    expect(txt).toContain("commit: 9f952c9 restructure repo");
    // The inspector/dashboard page where the actual logs live.
    expect(txt).toContain("link: https://vercel.com/team/olylo/dpl123");
    expect(txt).toContain("longer detail");
  });

  it("emits only populated fields", () => {
    const txt = rowDetailToText(rowToDetailProps(row({ platform: "http", name: "App", statusWord: "down" })));
    expect(txt).not.toContain("branch:");
    expect(txt).not.toContain("http status:");
    expect(txt).not.toContain("response:");
    expect(txt).not.toContain("error:");
  });

  it("includes the build error verbatim as its own labeled block", () => {
    const txt = rowDetailToText(
      rowToDetailProps(
        row({
          platform: "vercel", name: "olylo.ai-production", statusWord: "build failed",
          errorText: "[buildStep] Command \"next build\" exited with 1\n  ./app/page.tsx type error",
        }),
      ),
    );
    expect(txt).toContain("\nerror:\n[buildStep] Command \"next build\" exited with 1");
    expect(txt).toContain("./app/page.tsx type error");
  });
});
