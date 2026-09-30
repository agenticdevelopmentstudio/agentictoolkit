/// <reference types="@testing-library/jest-dom/vitest" />
// Every details header carries an API button just left of the "?" help — live when the view is
// about an endpoint and the host can open it, drawn disabled (saying why) otherwise, never absent
// (Mike, 2026-09-29).
import { render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it } from "vitest";

import { NO_API_ENDPOINT } from "@agenticdevelopertoolkit/ui/blocks";
import { ButtonBar, type MasterDetailActions } from "../master-detail/MasterDetailLayout";
import { RecordAffordanceContext, type RecordAffordanceProps } from "../record-affordance";

const actions: MasterDetailActions = {
  onCreate: () => {},
  onCancel: () => {},
  canCancel: false,
  onSave: () => {},
  canSave: false,
  onDelete: () => {},
  canDelete: false,
};

/** Stands in for the hub's RecordApiButton: a live button naming the endpoint it would open. */
const renderLive = (p: RecordAffordanceProps) => (
  <button type="button" data-testid="live-api">
    {p.path}
  </button>
);
const withHost = (ui: ReactNode) => (
  <RecordAffordanceContext.Provider value={renderLive}>{ui}</RecordAffordanceContext.Provider>
);

const disabledApi = () => screen.queryByRole("button", { name: `API — ${NO_API_ENDPOINT}` });

describe("ButtonBar — the API slot", () => {
  it("draws the host's live button for the endpoint the pane names", () => {
    render(
      withHost(
        <ButtonBar
          actions={actions}
          hoist={false}
          api={{ path: "/things/{id}", pathValues: { id: "t1" }, title: "Thing API" }}
        />,
      ),
    );
    expect(screen.getByTestId("live-api")).toHaveTextContent("/things/{id}");
    expect(disabledApi()).toBeNull();
  });

  it("draws the disabled button, with its reason, when the pane has no endpoint", () => {
    render(withHost(<ButtonBar actions={actions} hoist={false} api={null} />));
    const button = disabledApi();
    expect(button).toBeDisabled();
    expect(button!.parentElement).toHaveAttribute("title", NO_API_ENDPOINT);
    expect(screen.queryByTestId("live-api")).toBeNull();
  });

  it("draws the disabled button when the host supplies no affordance", () => {
    render(
      <ButtonBar
        actions={actions}
        hoist={false}
        api={{ path: "/things/{id}", pathValues: { id: "t1" } }}
      />,
    );
    expect(disabledApi()).toBeDisabled();
  });

  it("draws the disabled button while a path value is still unknown, never an empty slot", () => {
    render(
      withHost(
        <ButtonBar
          actions={actions}
          hoist={false}
          api={{ path: "/things/{id}", pathValues: { id: null } }}
        />,
      ),
    );
    expect(screen.queryByTestId("live-api")).toBeNull();
    expect(disabledApi()).toBeDisabled();
  });

  it("keeps the API button left of the help", () => {
    render(withHost(<ButtonBar actions={actions} hoist={false} api={null} help="Some help" />));
    // The help trigger is the bar's last button; the API button is the one just before it.
    const buttons = screen.getAllByRole("button");
    expect(buttons.at(-2)).toBe(disabledApi());
  });
});
