// @vitest-environment jsdom
//
// The Save button is the whole contract of an edit pane: editing a field must enable it. This
// pins that for the team settings pane, which shipped with it staying greyed out.
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";

vi.mock("@agentic-toolkit/data/teams", async (orig) => ({
  ...(await orig<typeof import("@agentic-toolkit/data/teams")>()),
  teamsApi: { create: vi.fn(), update: vi.fn() },
}));

import { TeamSettingsPane } from "./TeamSettingsPane";
import type { Team } from "@agentic-toolkit/data/teams";

const TEAM = {
  id: "t1",
  identifier: "team.acme.core",
  displayName: "Core Team",
} as Team;

afterEach(cleanup);

describe("TeamSettingsPane", () => {
  it("enables Save once a field is edited", async () => {
    render(<TeamSettingsPane teamId="t1" items={[TEAM]} refresh={() => {}} />);
    const name = await screen.findByLabelText("Display name");
    const save = screen.getByRole("button", { name: /save/i });
    expect(save).toBeDisabled();
    fireEvent.change(name, { target: { value: "Core Team 2" } });
    await waitFor(() => expect(save).toBeEnabled());
  });

  // The backend provisions every workspace's `participants` and `admins` teams with plain slugs,
  // which the client's reverse-domain rule rejects. Save must still enable on an edit that does
  // not touch the identifier — this is the case the pane actually shipped broken on.
  it("enables Save on a backend-provisioned team whose identifier is not reverse-domain", async () => {
    const provisioned = { ...TEAM, identifier: "participants" } as Team;
    render(<TeamSettingsPane teamId="t1" items={[provisioned]} refresh={() => {}} />);
    const name = await screen.findByLabelText("Display name");
    const save = screen.getByRole("button", { name: /save/i });
    fireEvent.change(name, { target: { value: "Participants" } });
    await waitFor(() => expect(save).toBeEnabled());
  });

  it("still holds a CHANGED identifier to the reverse-domain form", async () => {
    render(<TeamSettingsPane teamId="t1" items={[TEAM]} refresh={() => {}} />);
    const id = await screen.findByLabelText("Identifier");
    const save = screen.getByRole("button", { name: /save/i });
    fireEvent.change(id, { target: { value: "not-reverse-domain" } });
    await waitFor(() => expect(save).toBeDisabled());
  });

  // "Untouched" is decided by the shared `unchangedFromStored`, which trims BOTH sides. This
  // validator used to compare the stored slug raw, so a stored slug carrying whitespace never
  // counted as untouched and Save stayed dark on it exactly as on `participants` before the fix.
  it("counts a stored slug carrying whitespace as untouched", async () => {
    const provisioned = { ...TEAM, identifier: " participants " } as Team;
    render(<TeamSettingsPane teamId="t1" items={[provisioned]} refresh={() => {}} />);
    const name = await screen.findByLabelText("Display name");
    const save = screen.getByRole("button", { name: /save/i });
    fireEvent.change(name, { target: { value: "Participants" } });
    await waitFor(() => expect(save).toBeEnabled());
  });

  // Only the FORMAT is grandfathered. `validateTeamIdentifier` also holds the required rule, and
  // clearing a provisioned team's slug must still be refused as required, not waved through.
  it("still requires an identifier on a provisioned team", async () => {
    const provisioned = { ...TEAM, identifier: "participants" } as Team;
    render(<TeamSettingsPane teamId="t1" items={[provisioned]} refresh={() => {}} />);
    const id = await screen.findByLabelText("Identifier");
    const save = screen.getByRole("button", { name: /save/i });
    fireEvent.change(id, { target: { value: "" } });
    await waitFor(() => expect(save).toBeDisabled());
    expect(screen.getByText("Identifier is required.")).toBeTruthy();
  });
});
