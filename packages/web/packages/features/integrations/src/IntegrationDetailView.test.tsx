// @vitest-environment jsdom
import { useState } from "react";
import { describe, it, expect, afterEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import type { MaskedProviderConfig, ProviderCatalogEntry } from "@agentic-toolkit/data/integrations";

// Stub the integrations client so no real network happens.
const { updateProviderConfig, createProviderConfig } = vi.hoisted(() => ({
  updateProviderConfig: vi.fn(),
  createProviderConfig: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: { updateProviderConfig, createProviderConfig },
}));

import { IntegrationDetailView } from "./IntegrationDetailView";
import { intToInput, type IntegrationInput } from "./IntegrationDetail";

// The hub vitest config has no global afterEach; tear each render (+ its portalled
// dialog) down explicitly so it doesn't leak into the next test.
afterEach(cleanup);

const PROVIDER: ProviderCatalogEntry = {
  providerId: "acme",
  displayName: "Acme",
  subtitle: "",
  description: "",
  links: [],
  authMethod: "api_key",
  serviceTypes: [],
  capabilities: ["write"],
  defaultPollIntervalMs: 0,
  testable: false,
  configFields: [{ key: "token", label: "Token", secret: false, required: true }],
};

const EXISTING: MaskedProviderConfig = {
  id: "cfg-1",
  ecosystemId: "eco-1",
  providerId: "acme",
  name: "My Acme",
  rdid: "integration.acme.cfg-1",
  config: { token: "abc123", enabled: true },
  hasSecret: false,
};

function saveButton() {
  return screen.getByRole("button", { name: "Save" }) as HTMLButtonElement;
}

/** Mirrors how IntegrationsPane wires the shared view in mode='saved': it lifts the
 *  draft, and re-hydrates it from the just-saved row on `onSaved` (see IntegrationsPane's
 *  own onSaved comment for why — a bare-config-refetch re-derive would race the secret
 *  masking and leave the form stuck dirty). */
function SavedHarness({ config }: { config: MaskedProviderConfig }) {
  const [draft, setDraft] = useState<IntegrationInput>(() => intToInput(config, PROVIDER));
  return (
    <IntegrationDetailView
      provider={PROVIDER}
      ecosystemId="eco-1"
      mode="saved"
      config={config}
      draft={draft}
      onChange={setDraft}
      onSaved={(row) => setDraft(intToInput(row, PROVIDER))}
    />
  );
}

describe("IntegrationDetailView (mode='saved') — Save is disabled at mount, enabled after a dirty+valid edit", () => {
  it("is disabled at mount (loaded, unedited)", () => {
    render(<SavedHarness config={EXISTING} />);
    expect(saveButton().disabled).toBe(true);
  });

  it("enables on a name-only change (Save's own gate is name-inclusive, unlike the exit guard)", () => {
    render(<SavedHarness config={EXISTING} />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "My Acme Renamed" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("disables again once the name is reverted back to the loaded value", () => {
    render(<SavedHarness config={EXISTING} />);
    const name = screen.getByLabelText("Name");
    fireEvent.change(name, { target: { value: "My Acme Renamed" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(name, { target: { value: "My Acme" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once a config field is edited, and stays disabled if cleared to blank (required field)", () => {
    render(<SavedHarness config={EXISTING} />);
    const token = screen.getByLabelText("Token");
    fireEvent.change(token, { target: { value: "xyz789" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(token, { target: { value: "" } });
    expect(saveButton().disabled).toBe(true);
  });

  // The gate disables Save, so `intValidate`'s sentence never reaches the user through a click.
  // It has to be rendered, or clearing a required field reads as a broken button.
  it("says WHY Save is blocked when a required config field is cleared", () => {
    render(<SavedHarness config={EXISTING} />);
    fireEvent.change(screen.getByLabelText("Token"), { target: { value: "" } });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText("Token is required.")).toBeTruthy();
  });

  it("says WHY Save is blocked when the name is cleared", () => {
    render(<SavedHarness config={EXISTING} />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "  " } });
    expect(saveButton().disabled).toBe(true);
    expect(screen.getByText("A name is required.")).toBeTruthy();
  });

  // The other half. The loaded row arrives ALREADY invalid (blank name), so the reason really is
  // non-null at mount and only `dirty` keeps it quiet — a valid row would pass this test even with
  // the dirty term deleted.
  it("stays silent about an already-invalid loaded instance the user hasn't touched", () => {
    render(<SavedHarness config={{ ...EXISTING, name: "" }} />);
    expect(saveButton().disabled).toBe(true);
    expect(screen.queryByText("A name is required.")).toBeNull();
  });

  it("clicking Save while enabled persists, then goes back to disabled (re-baselined, not waiting on a config refetch)", async () => {
    updateProviderConfig.mockResolvedValue({
      ...EXISTING,
      config: { token: "xyz789", enabled: true },
    });
    render(<SavedHarness config={EXISTING} />);
    fireEvent.change(screen.getByLabelText("Token"), { target: { value: "xyz789" } });
    expect(saveButton().disabled).toBe(false);

    fireEvent.click(saveButton());
    await waitFor(() => expect(updateProviderConfig).toHaveBeenCalledTimes(1));
    expect(updateProviderConfig).toHaveBeenCalledWith(
      "eco-1",
      "cfg-1",
      expect.objectContaining({ name: "My Acme", fields: { token: "xyz789" } }),
    );
    await waitFor(() => expect(saveButton().disabled).toBe(true));
  });
});

/** mode='add' lifts its draft the same way the Add-integration modal does. */
function AddHarness() {
  const [draft, setDraft] = useState<IntegrationInput>(() =>
    intToInput({ ...EXISTING, name: "", config: { enabled: true } }, PROVIDER),
  );
  return (
    <IntegrationDetailView
      provider={PROVIDER}
      ecosystemId="eco-1"
      mode="add"
      config={null}
      draft={draft}
      onChange={setDraft}
    />
  );
}

describe("IntegrationDetailView (mode='add') — the blocked reason waits until the user has typed", () => {
  // 'add' hard-codes `dirty` true (any valid draft is submittable), so `dirty` can't double as
  // "the user has given us something to complain about" — an empty Add form must open silently.
  it("stays silent on a blank Add form", () => {
    render(<AddHarness />);
    expect(screen.getByRole("button", { name: "Add Integration" })).toHaveProperty("disabled", true);
    expect(screen.queryByText("A name is required.")).toBeNull();
    expect(screen.queryByText("Token is required.")).toBeNull();
  });

  it("says WHY once the user has typed something but a required field is still missing", () => {
    render(<AddHarness />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "My Acme" } });
    expect(screen.getByRole("button", { name: "Add Integration" })).toHaveProperty("disabled", true);
    expect(screen.getByText("Token is required.")).toBeTruthy();
  });
});
