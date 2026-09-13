import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RailHostBoundary } from "@agentic-toolkit/resource";

const listProviderConfigs = vi.fn();
const listProviders = vi.fn();
const getProviderConfigById = vi.fn(async () => null as unknown);
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    listProviderConfigs: (...a: unknown[]) => listProviderConfigs(...a),
    listProviders: (...a: unknown[]) => listProviders(...a),
    getProviderConfigById: (...a: unknown[]) => getProviderConfigById(...(a as [])),
  },
}));

// The saved-instance detail is stubbed: this file is about WHICH row the pane resolves, not about
// the credential form's own fields. The stub reports the config it was handed so the assertion can
// name the row rather than settling for "something rendered".
//
// All THREE of the module's exports the pane reaches for, because the pane composes the submit
// and test hooks itself now — the button bar's Save and Test are their state, and a bar rendered
// from inside the detail could not be published above the list.
vi.mock("../IntegrationDetailView", () => ({
  IntegrationDetailBody: ({ config }: { config: { name: string } }) => (
    <div data-testid="detail">{config.name}</div>
  ),
  IntegrationTestReport: () => null,
  useIntegrationSubmit: () => ({
    run: async () => {},
    busy: false,
    added: false,
    error: null,
    canSubmit: false,
    blockedReason: null,
    touched: false,
    dirty: false,
    label: "Save",
    busyLabel: "Saving…",
  }),
  useIntegrationTest: () => ({
    available: false,
    blockedReason: null,
    run: async () => {},
    busy: false,
    result: null,
    error: null,
  }),
}));
vi.mock("../AddIntegrationModal", () => ({ AddIntegrationModal: () => null }));

import { IntegrationsPane } from "../IntegrationsPane";

const CATALOG = [
  { providerId: "stripe", displayName: "Stripe", subtitle: "Billing", serviceTypes: ["billing"] },
];
const CONFIGS = [
  {
    id: "c1",
    rdid: null,
    ecosystemId: "e1",
    providerId: "stripe",
    name: "Stripe live",
    config: {},
    hasSecret: true,
  },
];

/**
 * Selection with NO `leaf` — the mount every host that cedes no URL segment below the topic uses:
 * the hub's workspace rail and the products topic, both of which reach this pane through
 * `BillingGroup`'s Stripe member.
 *
 * The pane runs two selection mechanisms — its own derived `cfg`, and `useMasterDetailForm`'s
 * internal dual-mode state — and they used to read from different places: the derived side read
 * `leaf?.leafId`, which is permanently `null` here, while the form held the real selection. The
 * rail highlighted the clicked row (it renders `form.selectedId`) and the pane body below it
 * stayed on the select nudge. Nothing typechecked wrong and no test rendered this mount and then
 * clicked, which is how it survived a whole branch.
 */
describe("IntegrationsPane selection without a URL leaf", () => {
  it("opens a row's detail when the rail row is clicked", async () => {
    listProviders.mockResolvedValue(CATALOG);
    listProviderConfigs.mockResolvedValue(CONFIGS);

    render(
      <RailHostBoundary>
        <IntegrationsPane ecosystemId="e1" providerIds={["stripe"]} levelTitle="Stripe" />
      </RailHostBoundary>,
    );

    await userEvent.click(await screen.findByRole("button", { name: /Stripe live/ }));
    // The detail, and the Save the bar grows when a row is open — both are inside the single
    // `cfg && provider && form.draft` branch that was unreachable here.
    expect(await screen.findByTestId("detail")).toHaveTextContent("Stripe live");
    expect(screen.getByRole("button", { name: "Save" })).toBeInTheDocument();
  });

  // The other direction, so the fix cannot be "ignore the leaf": a host that DOES cede the
  // segment must still deep-link straight into a row without a click.
  it("still opens the row named by the leaf when one is given", async () => {
    listProviders.mockResolvedValue(CATALOG);
    listProviderConfigs.mockResolvedValue(CONFIGS);

    render(
      <RailHostBoundary>
        <IntegrationsPane
          ecosystemId="e1"
          providerIds={["stripe"]}
          leaf={{ leafId: "c1", onSelect: vi.fn() }}
        />
      </RailHostBoundary>,
    );

    expect(await screen.findByTestId("detail")).toHaveTextContent("Stripe live");
  });
});
