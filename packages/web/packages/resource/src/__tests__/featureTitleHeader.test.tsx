// @vitest-environment jsdom
/// <reference types="@testing-library/jest-dom/vitest" />
//
// Every details header: the help "?" on the far right, the API button just left of it — enabled
// when the view is about an endpoint the host can open, shown but disabled otherwise (Mike,
// 2026-09-29). The admin panes and every pane that used to draw its API button in its body now
// go through this header.
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { FeatureTitle } from "../master-detail/MasterDetailLayout";
import { RecordAffordanceContext } from "../record-affordance";

afterEach(cleanup);

const host = (p: { title?: string }) => <button type="button">{p.title}</button>;

function header(props: Parameters<typeof FeatureTitle>[0], withHost = true) {
  const tree = <FeatureTitle {...props} />;
  return render(withHost ? <RecordAffordanceContext.Provider value={host}>{tree}</RecordAffordanceContext.Provider> : tree);
}

describe("FeatureTitle — the details header", () => {
  it("draws the host's live API button for an endpoint, then help on the far right", () => {
    header({
      title: "Users",
      help: "About users",
      api: { method: "GET", path: "/customer/customers", pathValues: {}, title: "Customers API" },
    });
    const api = screen.getByRole("button", { name: "Customers API" });
    expect(api).toBeEnabled();
    const help = screen.getByRole("button", { name: "About this section" });
    // API precedes help in document order: help is last, on the far right.
    expect(api.compareDocumentPosition(help) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it("shows the API button disabled when the view is not about an endpoint", () => {
    header({ title: "Audit", help: "About audit" });
    expect(screen.getByRole("button", { name: /^API — / })).toBeDisabled();
  });

  it("shows it disabled when no host can open it", () => {
    header({ title: "Users", api: { method: "GET", path: "/x", pathValues: {}, title: "X API" } }, false);
    expect(screen.getByRole("button", { name: /^API — / })).toBeDisabled();
  });

  it("shows it disabled until the path value it needs is known", () => {
    header({ title: "Game", api: { method: "PUT", path: "/game/games/{id}", pathValues: { id: undefined }, title: "Game API" } });
    expect(screen.getByRole("button", { name: /^API — / })).toBeDisabled();
    expect(screen.queryByRole("button", { name: "Game API" })).toBeNull();
  });
});
