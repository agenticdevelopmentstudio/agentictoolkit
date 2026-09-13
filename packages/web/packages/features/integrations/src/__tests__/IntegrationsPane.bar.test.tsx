import { beforeEach, describe, expect, it, vi } from "vitest";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { RailHostBoundary } from "@agentic-toolkit/resource";

const listProviderConfigs = vi.fn();
const listProviders = vi.fn();
const getProviderConfigById = vi.fn(async () => null as unknown);
const deleteProviderConfigById = vi.fn(async () => undefined);
const createProviderConfig = vi.fn(async (..._a: unknown[]) => ({}) as unknown);
const testProviderConfig = vi.fn();
const transferProviderConfig = vi.fn();

vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    listProviderConfigs: (...a: unknown[]) => listProviderConfigs(...a),
    listProviders: (...a: unknown[]) => listProviders(...a),
    getProviderConfigById: (...a: unknown[]) => getProviderConfigById(...(a as [])),
    deleteProviderConfigById: (...a: unknown[]) => deleteProviderConfigById(...(a as [])),
    createProviderConfig: (...a: unknown[]) => createProviderConfig(...a),
    testProviderConfig: (...a: unknown[]) => testProviderConfig(...a),
    transferProviderConfig: (...a: unknown[]) => transferProviderConfig(...a),
  },
}));

// The file picker and the download, stubbed at the shared seam rather than at the DOM: what this
// file is about is WHAT the bar hands them, and `showSaveFilePicker` does not exist in jsdom.
const saveTextFile = vi.fn(async () => true);
const readTextFile = vi.fn(async () => "");
vi.mock("@agenticdevelopertoolkit/ui/lib/file-exchange", () => ({
  saveTextFile: (...a: unknown[]) => saveTextFile(...(a as [])),
  readTextFile: (...a: unknown[]) => readTextFile(...(a as [])),
}));

// The credential form is stubbed — this file is about the bar. `IntegrationTestReport` is NOT,
// because the bulk Test's whole answer is a report per row and a stub would assert nothing.
vi.mock("../IntegrationDetailView", () => ({
  IntegrationDetailBody: ({ config }: { config: { name: string } }) => (
    <div data-testid="detail">{config.name}</div>
  ),
  IntegrationTestReport: ({ result }: { result: { summary: string } }) => <p>{result.summary}</p>,
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

const TARGETS = [
  { ecosystemId: "e2", label: "Acme", sublabel: "Organization", kind: "workspace" as const },
];
vi.mock("../destinations", () => ({
  useTransferTargets: () => ({ targets: TARGETS, error: null }),
}));

import { IntegrationsPane } from "../IntegrationsPane";

const CATALOG = [
  {
    providerId: "github-app",
    displayName: "GitHub",
    subtitle: "Code",
    serviceTypes: ["code"],
    authMethod: "github_app",
    testable: true,
  },
  {
    providerId: "postmark",
    displayName: "Postmark",
    subtitle: "Email",
    serviceTypes: ["email"],
    authMethod: "api_key",
    // Deliberately NOT testable: the bar must not spend a round trip per row to be told a
    // provider has no validation endpoint.
    testable: false,
  },
];

const config = (id: string, name: string, providerId = "github-app") => ({
  id,
  rdid: null,
  ecosystemId: "e1",
  providerId,
  name,
  config: {},
  hasSecret: true,
});

const CONFIGS = [config("c1", "Acme apps"), config("c2", "Beta apps"), config("c3", "Mail", "postmark")];

/** One entry of an export document, in the shape `buildExport` actually writes — a WHOLE
 *  `IntegrationInput`, blank secrets included, because that is what import reads back. */
const exported = (providerId: string, name: string) => ({
  providerId,
  name,
  input: {
    providerId,
    name,
    clientId: "",
    clientSecret: "",
    scopes: "",
    authUrl: "",
    tokenUrl: "",
    userinfoUrl: "",
    validateUrl: "",
    credentialStyle: "",
    endpoints: {},
    fields: {},
    enabled: true,
  },
  needsSecrets: ["Private key"],
});

function mount(props: Record<string, unknown> = {}) {
  return render(
    <RailHostBoundary>
      <IntegrationsPane ecosystemId="e1" workspaceSlug="acme" {...props} />
    </RailHostBoundary>,
  );
}

/** Enter Select mode and tick these rows by their labels. */
async function tick(...names: string[]) {
  await userEvent.click(screen.getByRole("button", { name: "Select" }));
  for (const name of names) {
    await userEvent.click(await screen.findByRole("checkbox", { name }));
  }
}

const bar = (name: string) => screen.getByRole("button", { name });

beforeEach(() => {
  vi.clearAllMocks();
  listProviders.mockResolvedValue(CATALOG);
  listProviderConfigs.mockResolvedValue(CONFIGS);
  saveTextFile.mockResolvedValue(true);
});

/**
 * THE PANE'S BUTTON BAR — Add · Remove · Select · Export · Import · Test · Transfer.
 *
 * It replaced three separate affordances that could each only ever act on one row: the rail's
 * bare `+`, the detail's own Save and Test, and a destructive "Remove integration" button at the
 * bottom of the credential form. Everything below is the difference between those and a bar that
 * acts on a SET.
 */
describe("the integrations button bar", () => {
  it("publishes every verb, and takes the rail's + away", async () => {
    mount();
    for (const verb of ["Add", "Remove", "Select", "Export", "Import", "Test", "Transfer"]) {
      expect(await screen.findByRole("button", { name: verb })).toBeInTheDocument();
    }
    // The rail's creator is gone: `showNew: false`. Two creators in one field of view, one of
    // them an unlabelled glyph, is one more than anybody can name.
    expect(screen.queryByRole("button", { name: "Add integration" })).toBeNull();
  });

  it("offers nothing to act on until something is selected", async () => {
    mount();
    await screen.findByRole("button", { name: "Remove" });
    for (const verb of ["Remove", "Export", "Test", "Transfer"]) {
      expect(bar(verb)).toBeDisabled();
    }
    // Add and Import need no row — one creates and the other reads a file.
    expect(bar("Add")).toBeEnabled();
    expect(bar("Import")).toBeEnabled();
  });

  it("turns Select into Done, draws the tick boxes, and arms the verbs", async () => {
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    expect(screen.queryByRole("checkbox")).toBeNull();

    await userEvent.click(bar("Select"));
    expect(screen.queryByRole("button", { name: "Select" })).toBeNull();
    expect(bar("Done")).toBeInTheDocument();
    expect(await screen.findAllByRole("checkbox")).toHaveLength(3);
    // Boxes showing but nothing ticked is still nothing to act on.
    expect(bar("Remove")).toBeDisabled();

    await userEvent.click(screen.getByRole("checkbox", { name: "Acme apps" }));
    for (const verb of ["Remove", "Export", "Test", "Transfer"]) {
      expect(bar(verb)).toBeEnabled();
    }
  });

  it("removes every ticked row, once the confirmation is answered", async () => {
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    await tick("Acme apps", "Beta apps");
    await userEvent.click(bar("Remove"));

    // The confirm names the COUNT, because this path is the only deletion path and it is as
    // likely to be holding four rows as one.
    expect(await screen.findByText(/Remove 2 integrations\?/)).toBeInTheDocument();
    expect(deleteProviderConfigById).not.toHaveBeenCalled();

    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    await waitFor(() => expect(deleteProviderConfigById).toHaveBeenCalledTimes(2));
    expect(deleteProviderConfigById.mock.calls.map((c) => c[1])).toEqual(["c1", "c2"]);
  });

  it("names one row in the confirmation when one row is what is selected", async () => {
    mount();
    await userEvent.click(await screen.findByRole("button", { name: /Acme apps/ }));
    await userEvent.click(bar("Remove"));
    expect(await screen.findByText(/Remove the "Acme apps" integration\?/)).toBeInTheDocument();
  });

  it("tests every ticked row that CAN be tested, and reports each one", async () => {
    testProviderConfig.mockImplementation(async (_e: string, id: string) => ({
      ok: id === "c1",
      summary: id === "c1" ? "Reached GitHub." : "GitHub refused the private key.",
      notes: [],
    }));
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    // "Mail" is a Postmark row, and Postmark is not testable — ticking it must not buy a request.
    await tick("Acme apps", "Beta apps", "Mail");
    await userEvent.click(bar("Test"));

    await waitFor(() => expect(testProviderConfig).toHaveBeenCalledTimes(2));
    expect(testProviderConfig.mock.calls.map((c) => c[1])).toEqual(["c1", "c2"]);
    // Per row, and one refusal does not swallow the other row's answer.
    expect(await screen.findByText("Reached GitHub.")).toBeInTheDocument();
    expect(screen.getByText("GitHub refused the private key.")).toBeInTheDocument();
  });

  it("keeps the other rows' answers when one test cannot be made at all", async () => {
    testProviderConfig.mockImplementation(async (_e: string, id: string) => {
      if (id === "c2") throw new Error("Network unreachable");
      return { ok: true, summary: "Reached GitHub.", notes: [] };
    });
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    await tick("Acme apps", "Beta apps");
    await userEvent.click(bar("Test"));

    expect(await screen.findByText("Reached GitHub.")).toBeInTheDocument();
    expect(screen.getByText("Network unreachable")).toBeInTheDocument();
  });

  it("exports the ticked rows to a file the operator chooses", async () => {
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    await tick("Acme apps");
    await userEvent.click(bar("Export"));

    await waitFor(() => expect(saveTextFile).toHaveBeenCalledTimes(1));
    const { text, filename } = saveTextFile.mock.calls[0]![0] as {
      text: string;
      filename: string;
    };
    expect(filename).toMatch(/^integrations-\d{4}-\d{2}-\d{2}\.json$/);
    const doc = JSON.parse(text) as {
      kind: string;
      integrations: { name: string; needsSecrets: string[]; input: Record<string, unknown> }[];
    };
    expect(doc.kind).toBe("adh.integrations");
    expect(doc.integrations.map((i) => i.name)).toEqual(["Acme apps"]);
    // No secret rode along. The document NAMES the credential fields, blank, and lists what has
    // to be typed back in — the API has never echoed a secret back, so a file that appeared to
    // carry one would be carrying something else.
    expect(doc.integrations[0]!.needsSecrets).toEqual(["Private key"]);
    expect(doc.integrations[0]!.input.clientSecret).toBe("");
  });

  it("imports what is new, and tells the operator what it skipped", async () => {
    readTextFile.mockResolvedValue(
      JSON.stringify({
        kind: "adh.integrations",
        version: 1,
        exportedAt: "2026-09-12T00:00:00.000Z",
        integrations: [
          // Already here by provider + name.
          exported("github-app", "Acme apps"),
          exported("github-app", "Gamma apps"),
          // A provider this console's catalog has never heard of.
          exported("bitbucket", "Legacy"),
        ],
      }),
    );
    const { container } = mount();
    await screen.findByRole("button", { name: /Acme apps/ });

    const input = container.querySelector('input[type="file"]') as HTMLInputElement;
    await userEvent.upload(input, new File(["{}"], "integrations.json", { type: "application/json" }));

    await waitFor(() => expect(createProviderConfig).toHaveBeenCalledTimes(1));
    expect(await screen.findByText(/Imported Gamma apps\./)).toBeInTheDocument();
    // The duplicate list the operator asked to be shown at the end of an import.
    const skipped = screen.getByText("Already here, skipped").parentElement!;
    expect(within(skipped).getByText("Acme apps")).toBeInTheDocument();
    const unknown = screen.getByText("No such provider in this console").parentElement!;
    expect(within(unknown).getByText(/Legacy/)).toBeInTheDocument();
  });

  it("transfers the ticked rows to the destination chosen in the confirmation", async () => {
    transferProviderConfig.mockResolvedValue({ config: {}, connections: 2, repositoryCaches: 0 });
    mount();
    await screen.findByRole("button", { name: /Acme apps/ });
    await tick("Acme apps");
    await userEvent.click(bar("Transfer"));

    // Transfer / Cancel, and the destination chooser in the body — a transfer with nowhere named
    // is not a thing to confirm. Scoped to the dialog, because the bar's own Transfer is still on
    // screen behind it and shares the word.
    const dialog = within(await screen.findByRole("dialog"));
    expect(dialog.getByRole("button", { name: "Cancel" })).toBeInTheDocument();
    expect(dialog.getByRole("combobox")).toHaveValue("e2");

    await userEvent.click(dialog.getByRole("button", { name: "Transfer" }));
    await waitFor(() => expect(transferProviderConfig).toHaveBeenCalledTimes(1));
    expect(transferProviderConfig.mock.calls[0]!.slice(1)).toEqual(["c1", { targetEcosystemId: "e2" }]);
    expect(
      await screen.findByText("Transferred 1 integration, with 2 connected accounts."),
    ).toBeInTheDocument();
  });

  it("draws no Transfer at all for a host that has not said which workspace it is in", async () => {
    mount({ workspaceSlug: undefined });
    await screen.findByRole("button", { name: "Remove" });
    // Absent rather than disabled: a greyed button with nothing behind it claims there is nowhere
    // to move these, and that is a fact about the HOST, not about the account.
    expect(screen.queryByRole("button", { name: "Transfer" })).toBeNull();
  });
});
