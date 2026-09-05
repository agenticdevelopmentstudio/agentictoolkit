// @vitest-environment jsdom
import { describe, it, expect, afterEach } from "vitest";
import { render, screen, cleanup, fireEvent } from "@testing-library/react";
import { ActivityDetails } from "./ActivityDetails";
import type { RowDetail } from "../lib/row-detail";

afterEach(cleanup);

function detail(o: Partial<RowDetail>): RowDetail {
  return {
    title: "adh", titleUrl: null, environment: null, platformText: null, platformLink: null,
    problem: null, problemLink: null, statusCode: null, responseTime: null, branch: null,
    since: null, lastChecked: null, sha: null, commitSubject: null, commitUrl: null, commitBody: null,
    errorText: null, deployOutcome: null, ...o,
  };
}

describe("ActivityDetails", () => {
  it("shows the shared top area: endpoint, platform link, env badge, git commit line", () => {
    render(<ActivityDetails detail={detail({
      title: "adh", titleUrl: "https://adh.app", environment: "production",
      platformText: "built on vercel", platformLink: "https://vercel.com/dpl",
      sha: "abc1234", commitSubject: "fix login", commitUrl: "https://gh/c",
    })} />);
    expect(screen.getByText("endpoint")).toBeTruthy();
    expect(screen.getByText("built on vercel")).toBeTruthy();
    expect(screen.getByText("PROD")).toBeTruthy(); // uppercase env badge
    expect(screen.getByText("git commit")).toBeTruthy();
    expect(screen.getByText("fix login")).toBeTruthy();
  });

  it("hides fields that have no data (and the tab bar when there is no git detail)", () => {
    render(<ActivityDetails detail={detail({ title: "adh" })} />);
    expect(screen.queryByText("problem")).toBeNull();
    expect(screen.queryByText("git info")).toBeNull();
    expect(screen.queryByText("branch")).toBeNull();
    expect(screen.queryByText("http status")).toBeNull();
    expect(screen.queryByRole("tab")).toBeNull();
  });

  it("a FAILED deploy: red headline linking to the platform, reason line with the copy button, scrollable logs", () => {
    render(<ActivityDetails detail={detail({
      title: "olylo.ai-production", deployOutcome: "failed",
      platformText: "build failed on vercel", platformLink: "https://vercel.com/dpl123",
      problem: "Command exited with 1",
      errorText: "[buildStep] Command \"next build\" exited with 1\n  ./app/page.tsx type error",
      commitBody: "restructure repo\n\nlonger detail",
    })} />);
    const headline = screen.getByText(/build \/ deploy FAILED/);
    expect(headline.closest("a")?.getAttribute("href")).toBe("https://vercel.com/dpl123");
    expect(screen.getByText("reason")).toBeTruthy();
    expect(screen.getByText("Command exited with 1")).toBeTruthy();
    expect(screen.getByLabelText("copy problem details")).toBeTruthy();
    expect(screen.getByText("logs")).toBeTruthy();
    expect(screen.getByText(/next build" exited with 1/)).toBeTruthy();
  });

  it("a successful deploy: green headline, no reason/logs/copy", () => {
    render(<ActivityDetails detail={detail({
      title: "adh", deployOutcome: "success", platformText: "deployed on railway",
    })} />);
    expect(screen.getByText(/build \/ deploy successful/)).toBeTruthy();
    expect(screen.queryByText("reason")).toBeNull();
    expect(screen.queryByText("logs")).toBeNull();
    expect(screen.queryByLabelText("copy problem details")).toBeNull();
  });

  it("an endpoint problem: summary line with the copy button + diagnostics rows", () => {
    render(<ActivityDetails detail={detail({
      title: "x.example.com", problem: "Timeout after 10000ms", problemLink: "https://x.example.com/health",
      statusCode: 503, responseTime: "1200ms",
      since: "2026-06-04T17:00:00.000Z", lastChecked: "2026-06-04T18:05:00.000Z",
    })} />);
    expect(screen.getByText("Timeout after 10000ms")).toBeTruthy();
    expect(screen.getByLabelText("copy problem details")).toBeTruthy();
    expect(screen.getByText("http status")).toBeTruthy();
    expect(screen.getByText("503")).toBeTruthy();
    expect(screen.getByText("response")).toBeTruthy();
    expect(screen.getByText("1200ms")).toBeTruthy();
    expect(screen.getByText("last check")).toBeTruthy();
  });

  it("the git tab reveals branch + the full commit body", () => {
    render(<ActivityDetails detail={detail({
      title: "adh", deployOutcome: "failed", platformText: "build failed on vercel",
      branch: "production", commitBody: "restructure repo\n\nlonger detail",
    })} />);
    // Two tabs render; overview is active, the body is not yet visible.
    expect(screen.getAllByRole("tab")).toHaveLength(2);
    expect(screen.queryByText(/longer detail/)).toBeNull();
    fireEvent.click(screen.getByRole("tab", { name: "git info" }));
    expect(screen.getByText("branch")).toBeTruthy();
    expect(screen.getByText("production")).toBeTruthy();
    expect(screen.getByText(/longer detail/)).toBeTruthy();
  });
});
