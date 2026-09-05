// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { ErrorsCard, TrafficCard } from "./TelemetrySections";
import { StatusHostProvider } from "./StatusHost";

// The cards' deep links come from the HOST (StatusHostProvider), never from an
// environment variable or a built-in hostname — the package must not know where a
// deployment's GlitchTip or PostHog live. Both cards, both directions.

vi.mock("../hooks/use-telemetry", () => ({
  useTelemetry: () => ({ errors: [], analytics: [], stale: false, offline: false }),
}));

afterEach(cleanup);

describe("telemetry card deep links", () => {
  it("link to the host-supplied GlitchTip and PostHog URLs", () => {
    render(
      <StatusHostProvider settings={{ glitchtipUrl: "https://errors.example.test/org", posthogUrl: "https://analytics.example.test" }}>
        <ErrorsCard />
        <TrafficCard />
      </StatusHostProvider>,
    );
    expect(screen.getByRole("link", { name: /GlitchTip/ }).getAttribute("href")).toBe("https://errors.example.test/org");
    expect(screen.getByRole("link", { name: /PostHog/ }).getAttribute("href")).toBe("https://analytics.example.test");
  });

  it("render no deep link when the host supplies none", () => {
    render(
      <>
        <ErrorsCard />
        <TrafficCard />
      </>,
    );
    expect(screen.queryByRole("link")).toBeNull();
    // The cards themselves still render — a missing link never hides the data.
    expect(screen.queryByText("Errors")).not.toBeNull();
    expect(screen.queryByText("Traffic")).not.toBeNull();
  });
});
