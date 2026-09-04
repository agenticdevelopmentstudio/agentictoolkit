// @vitest-environment jsdom
import { useState } from "react";
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import type { MaskedProviderConfig, ProviderCatalogEntry } from "@agentic-toolkit/data/integrations";

/**
 * The GitHub App path through the integrations feature, end to end as the operator walks
 * it: save the APP (its id and private key) on the ecosystem — and that is the whole walk,
 * because saving it is also what connects it.
 *
 * THE SECOND STEP USED TO BE A REDIRECT, and its removal is what most of this file is now
 * about. "Connect account" → "Continue to GitHub App" existed to let a person choose which
 * account to install on; but by the time an app id and a private key have been typed here,
 * that choice was already made on github.com, and the backend can read it back from those
 * two values alone. A dialog that asks a question whose answer it already holds is not a
 * safeguard, it is a step that can be skipped — and every operator who did not know to take
 * it was left with a saved integration connected to nothing.
 *
 * So the assertions below are mostly ABSENCES, and absences are what regress quietly: no
 * Connect-account button, no Continue-to-GitHub dialog, no second integration row when a
 * refused key is corrected and re-submitted.
 *
 * The credentials form's own hazard is unchanged: it is chosen by shape, not by name — a
 * provider that declares any `configFields` gets the api_key editor instead — so one
 * plausible-looking line in the catalog is enough to make the app id and private key have
 * no surface anywhere, which is exactly what happened once.
 *
 * shipr's pushes are the server's, made with an installation token minted from that private
 * key, so "GitHub is connected" is the load-bearing precondition of every run.
 */

// PARTIAL: a factory returning a bare object replaces the whole module, and this package reads
// `currentReturnTo` and `safeReturnTo` from it too — both on the path this file exercises, since
// stashing a pending connect captures the address to come back to. Stubbing the module flat left
// those undefined, which surfaced as an empty stash rather than as a missing mock.
vi.mock("@agentic-toolkit/auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@agentic-toolkit/auth")>();
  return { ...actual, reportUnexpectedAuthError: vi.fn() };
});

const {
  getInstallUrl,
  updateProviderConfig,
  createProviderConfig,
  adoptInstallations,
  listConnections,
} = vi.hoisted(() => ({
  getInstallUrl: vi.fn(),
  updateProviderConfig: vi.fn(),
  createProviderConfig: vi.fn(),
  adoptInstallations: vi.fn(),
  listConnections: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    getInstallUrl,
    updateProviderConfig,
    createProviderConfig,
    adoptInstallations,
    listConnections,
  },
  oauthCallbackUrl: () => "https://app.example.test/integrations/oauth-callback",
}));

import { ConnectAccountDialog } from "./ConnectAccountDialog";
import { IntegrationDetailView } from "./IntegrationDetailView";
import { intBlank, intToInput, type IntegrationInput } from "./IntegrationDetail";

// The hub vitest config has no global afterEach; tear each render (+ its portalled dialog)
// down explicitly so it doesn't leak into the next test.
afterEach(cleanup);
beforeEach(() => {
  getInstallUrl.mockReset();
  updateProviderConfig.mockReset();
  createProviderConfig.mockReset();
  adoptInstallations.mockReset();
  listConnections.mockReset();
  // The default for the tests that are about the FORM: nothing installed, nothing connected.
  // Each connect test states its own.
  adoptInstallations.mockResolvedValue({ connected: [], skipped: [] });
  listConnections.mockResolvedValue([]);
  sessionStorage.clear();
});

/**
 * The catalog's own entry for `github-app`, trimmed to what these components read.
 *
 * `configFields` is ABSENT, and that absence is the fixture's whole point: an installation
 * id is a fact about a connection, not about the ecosystem's config, and declaring one here
 * flips `hasConfigFields` and hands the whole form to the api_key editor.
 */
const GITHUB_APP: ProviderCatalogEntry = {
  providerId: "github-app",
  displayName: "GitHub App",
  subtitle: "Code",
  description: "",
  links: [],
  authMethod: "github_app",
  serviceTypes: ["code"],
  capabilities: ["read", "write"],
  defaultPollIntervalMs: 3_600_000,
};

const SAVED: MaskedProviderConfig = {
  id: "cfg-1",
  ecosystemId: "eco-1",
  providerId: "github-app",
  name: "ADH deploys",
  rdid: "integration.github-app.cfg-1",
  config: { clientId: "123456" },
  hasSecret: true,
};

/** Mirrors how IntegrationsPane wires the shared view in mode='saved'. */
function SavedForm({
  provider = GITHUB_APP,
  config = SAVED,
}: {
  provider?: ProviderCatalogEntry;
  config?: MaskedProviderConfig;
}) {
  const [draft, setDraft] = useState<IntegrationInput>(() => intToInput(config, provider));
  return (
    <IntegrationDetailView
      provider={provider}
      ecosystemId="eco-1"
      mode="saved"
      config={config}
      draft={draft}
      onChange={setDraft}
      onSaved={(row) => setDraft(intToInput(row, provider))}
    />
  );
}

describe("the ecosystem credentials form for a GitHub App", () => {
  it("asks for an app id and a private key, in those words", () => {
    render(<SavedForm />);
    // "Client ID" and "Client secret" are the OAuth pair. An operator handed those labels
    // has no way to tell whether the thing they are holding is the right credential.
    expect(screen.getByLabelText("App ID")).toBeTruthy();
    expect(screen.getByLabelText("Private key")).toBeTruthy();
    expect(screen.queryByLabelText("Client ID")).toBeNull();
    expect(screen.queryByLabelText("Client secret")).toBeNull();
  });

  it("gives the private key a field a PEM actually fits in", () => {
    render(<SavedForm />);
    const key = screen.getByLabelText("Private key");
    // A one-line password input visibly refuses the newlines in a 25-line .pem, and the
    // paste that half-works is unverifiable afterwards — nothing is ever shown back.
    expect(key.tagName).toBe("TEXTAREA");
    // Still write-only: what is stored comes back as `hasSecret`, never as the key.
    expect(key.getAttribute("value")).toBeNull();
    expect((key as HTMLTextAreaElement).value).toBe("");
  });

  it("offers neither scopes nor the endpoint overrides", () => {
    render(<SavedForm />);
    // An app's permissions live ON the app, chosen when it was registered; the endpoint
    // overrides only mean something to an OAuth token exchange. Both would be controls
    // whose value is silently discarded.
    expect(screen.queryByLabelText("Scopes")).toBeNull();
    expect(screen.queryByText("Advanced")).toBeNull();
  });

  it("names the field that is on the screen when it is empty", async () => {
    // The refusal has to be actionable. "Client ID is required" over an empty box labelled
    // "App ID" reads as a form complaining about a field that isn't there.
    render(<SavedForm config={{ ...SAVED, config: {} }} />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "ADH deploys 2" } });
    expect(await screen.findByText("App ID is required.")).toBeTruthy();
  });

  it("would lose both fields if the catalog declared a config field", () => {
    // The regression, stated as the mechanism rather than as a memory: `hasConfigFields`
    // takes precedence over the auth method, so ONE declared field replaces the whole
    // credentials form with the spec-driven editor — and the app id and private key then
    // have no surface anywhere in the product.
    render(
      <SavedForm
        provider={{
          ...GITHUB_APP,
          configFields: [{ key: "installationId", label: "Installation ID", secret: false }],
        }}
      />,
    );
    expect(screen.getByLabelText("Installation ID")).toBeTruthy();
    expect(screen.queryByLabelText("App ID")).toBeNull();
    expect(screen.queryByLabelText("Private key")).toBeNull();
  });
});

/** Mirrors how the Add dialog wires the shared view in mode='add'. */
function AddForm({ onSaved = () => {} }: { onSaved?: (row: MaskedProviderConfig) => void }) {
  const [draft, setDraft] = useState<IntegrationInput>(() => intBlank("github-app"));
  return (
    <IntegrationDetailView
      provider={GITHUB_APP}
      ecosystemId="eco-1"
      mode="add"
      config={null}
      draft={draft}
      onChange={setDraft}
      onSaved={onSaved}
    />
  );
}

/** Fill the three fields the app needs, in the state the operator leaves them in. */
function fillTheApp(): void {
  fireEvent.change(screen.getByLabelText("Name"), { target: { value: "ADH deploys" } });
  fireEvent.change(screen.getByLabelText("App ID"), { target: { value: "123456" } });
  fireEvent.change(screen.getByLabelText("Private key"), {
    target: { value: "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----" },
  });
}

describe("adding the app IS connecting it", () => {
  it("connects every installation the app can already see, with nothing in between", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockResolvedValue({
      connected: [
        { installationId: "99", accountLogin: "acme", targetType: "Organization" },
        { installationId: "100", accountLogin: "someone", targetType: "User" },
      ],
      skipped: [],
    });
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    await waitFor(() => expect(saved).toHaveBeenCalledWith(SAVED));
    // The config row is named EXPLICITLY. The backend must not resolve the app itself: its
    // resolver falls through to the platform-global app, whose installations belong to other
    // tenants, and enumerating those here would connect this ecosystem to someone else's org.
    expect(adoptInstallations).toHaveBeenCalledWith("github-app", {
      ecosystemId: "eco-1",
      providerConfigId: "cfg-1",
    });
    expect(await screen.findByText(/Connected acme, someone\./)).toBeTruthy();
  });

  it("says what was already connected instead of reporting it as new", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockResolvedValue({
      connected: [],
      // A skip that carries a connectionId is one THIS ecosystem already holds — re-saving a
      // working integration has to read as a no-op, not as a failure to connect.
      skipped: [
        {
          installationId: "99",
          accountLogin: "acme",
          targetType: "Organization",
          connectionId: "conn-1",
          skipped: "already connected",
        },
      ],
    });
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    await waitFor(() => expect(saved).toHaveBeenCalled());
    expect(screen.getByText(/acme was already connected\./)).toBeTruthy();
  });

  it("stays open on GitHub's own words when the key is refused", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    // The enumeration IS the credential test — this is the only moment a bad app id or an
    // unimportable private key can be caught while the operator is still looking at it.
    adoptInstallations.mockRejectedValue(new Error("401 A JSON web token could not be decoded"));
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    expect(
      await screen.findByText(/GitHub refused these credentials: 401 A JSON web token/),
    ).toBeTruthy();
    // The dialog must NOT close: closing would land on a connections list that is empty for a
    // reason nothing on that screen can state.
    expect(saved).not.toHaveBeenCalled();
  });

  it("corrects the saved row on a retry rather than adding a second integration", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    updateProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockRejectedValueOnce(new Error("401 bad key")).mockResolvedValue({
      connected: [{ installationId: "99", accountLogin: "acme", targetType: "Organization" }],
      skipped: [],
    });
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));
    await screen.findByText(/GitHub refused these credentials/);

    // The operator pastes the right key and presses OK again. The row from the first attempt
    // is already saved, so a second create would leave two integrations behind — one of them
    // permanently broken, and both named the same thing.
    fireEvent.change(screen.getByLabelText("Private key"), {
      target: { value: "-----BEGIN RSA PRIVATE KEY-----\nright\n-----END RSA PRIVATE KEY-----" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    await waitFor(() => expect(saved).toHaveBeenCalledWith(SAVED));
    expect(createProviderConfig).toHaveBeenCalledTimes(1);
    expect(updateProviderConfig).toHaveBeenCalledTimes(1);
    expect(updateProviderConfig.mock.calls[0]?.[1]).toBe("cfg-1");
  });

  it("does not claim success for an app that is installed nowhere", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    // Valid credentials, no installations: the credentials proved themselves by answering at
    // all, but there is nothing to connect, and "integration added" would be the lie the empty
    // connections list is then left to explain.
    adoptInstallations.mockResolvedValue({ connected: [], skipped: [] });
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    expect(await screen.findByText(/isn't installed on any account yet/)).toBeTruthy();
    expect(saved).not.toHaveBeenCalled();
  });
});

describe("the connect step that is no longer there", () => {
  it("offers no Connect-account button on a saved GitHub App", async () => {
    render(<SavedForm />);
    // The button, and the "Continue to GitHub App" dialog behind it, are the intermediate step
    // this whole path removed. Nothing may put them back for this auth method.
    await waitFor(() => expect(adoptInstallations).toHaveBeenCalled());
    expect(screen.queryByRole("button", { name: "Connect account" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Continue to GitHub App" })).toBeNull();
  });

  it("picks up an installation added since the app was saved, on its own", async () => {
    // The save-time connect only ever sees what existed then. An app installed on a SECOND
    // organization afterwards has to be picked up by something, and with no button to press
    // that something is opening the integration.
    render(<SavedForm />);
    await waitFor(() =>
      expect(adoptInstallations).toHaveBeenCalledWith("github-app", {
        ecosystemId: "eco-1",
        providerConfigId: "cfg-1",
      }),
    );
  });

  it("explains an empty list instead of pointing at a button that does not exist", async () => {
    render(<SavedForm />);
    expect(await screen.findByText(/isn't installed on any account yet/)).toBeTruthy();
    expect(screen.queryByText("No account connected.")).toBeNull();
  });

  it("carries GitHub's refusal into the connections section", async () => {
    adoptInstallations.mockRejectedValue(new Error("401 A JSON web token could not be decoded"));
    render(<SavedForm />);
    expect(await screen.findByText(/401 A JSON web token could not be decoded/)).toBeTruthy();
  });

  it("opens no dialog for a github_app, whatever asks it to", () => {
    // ConnectAccountDialog has no `github_app` case at all now — mounted with one it falls to
    // the "can't be connected here" default rather than growing a second, divergent way in.
    render(
      <ConnectAccountDialog
        provider={GITHUB_APP}
        ecosystemId="eco-1"
        providerConfig={SAVED}
        open
        onOpenChange={() => {}}
        onConnected={() => {}}
      />,
    );
    expect(screen.queryByRole("button", { name: "Continue to GitHub App" })).toBeNull();
    expect(getInstallUrl).not.toHaveBeenCalled();
  });
});
