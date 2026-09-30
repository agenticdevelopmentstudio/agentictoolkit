// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";

import type { ApplicationPlatform } from "@agentic-toolkit/data/ecosystem-config";
import type { PrototypeApplication } from "../api/applications-prototype";
import { ApplicationDetail, appBlank } from "./ApplicationDetail";

// The data-backed sections stand in as markers: what is under test is which ones a platform gets.
vi.mock("./AccessTokensSection", () => ({ AccessTokensSection: () => <div>access tokens</div> }));
vi.mock("./SchemaPermissionsSection", () => ({ SchemaPermissionsSection: () => <div>schema permissions</div> }));

function app(platform: ApplicationPlatform): PrototypeApplication {
  return {
    id: "app.acme.one",
    identifier: "app.acme.one",
    name: "One",
    platform,
    schemaGrants: [],
  } as unknown as PrototypeApplication;
}

function renderDetail(platform: ApplicationPlatform, onDelete?: () => Promise<void>) {
  const a = app(platform);
  render(
    <ApplicationDetail
      draft={{ ...appBlank(platform), identifier: a.identifier, name: a.name }}
      onChange={() => {}}
      app={a}
      scopePrefix="app.acme."
      clientAuth={<div>client auth</div>}
      onDelete={onDelete}
    />,
  );
}

afterEach(cleanup);

describe("ApplicationDetail", () => {
  it("has no platform field — the creator that made the app fixed it", () => {
    renderDetail("web");
    expect(screen.queryByLabelText("Platform")).toBeNull();
    expect(screen.queryByLabelText("Consumer kind")).toBeNull();
  });

  it("gives a website access tokens and heads it Website", () => {
    renderDetail("web");
    expect(screen.queryByText("Website")).not.toBeNull();
    expect(screen.queryByText("access tokens")).not.toBeNull();
    expect(screen.queryByText("client auth")).not.toBeNull();
  });

  it("gives a native app no access tokens — a secret on a device is no secret", () => {
    renderDetail("native");
    expect(screen.queryByText("App")).not.toBeNull();
    expect(screen.queryByText("access tokens")).toBeNull();
    expect(screen.queryByText("client auth")).not.toBeNull();
  });

  it("puts delete in a danger zone, only when the pane can delete", () => {
    renderDetail("web");
    expect(screen.queryByRole("region", { name: "Danger Zone" })).toBeNull();
    cleanup();
    renderDetail("native", async () => {});
    expect(screen.queryByRole("region", { name: "Danger Zone" })).not.toBeNull();
  });

  it("starts a blank draft on the platform it is asked for", () => {
    expect(appBlank().platform).toBe("web");
    expect(appBlank("native").platform).toBe("native");
  });
});
