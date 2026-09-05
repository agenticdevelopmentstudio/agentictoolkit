// @vitest-environment jsdom
import { useState } from "react";
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import type { MaskedProviderConfig, ProviderCatalogEntry } from "@agentic-toolkit/data/integrations";

/**
 * The GitHub App path through the integrations feature, end to end as the operator walks it:
 * save the APP — its id and private key — on the ecosystem, and press Test when they want to
 * know whether it works.
 *
 * TWO BUTTONS, TWO RESPONSIBILITIES, and most of this file guards the line between them.
 * Save writes fields. Test reaches github.com and says what came back. They are not the same
 * question, so one button cannot answer both: a Save that also tested could not store a
 * half-typed key without being scolded by a third party, and a Test folded into Save could not
 * be pressed at all after installing the app on a second organization, because there would be
 * nothing left to change on the form to enable it.
 *
 * What Save does do is DOWNLOAD, silently. The moment credentials land there is exactly one
 * useful thing to do with them, and doing it now is the difference between a repository picker
 * that opens full and one that opens empty. It is not awaited and its outcome is never shown —
 * a save that blocked on a network round-trip would be a test with the reporting removed.
 *
 * THE STEP BETWEEN THEM USED TO BE A REDIRECT, and its removal is the rest of this file.
 * "Connect account" → "Continue to GitHub App" existed to let a person choose which account to
 * install on; by the time an app id and a private key have been typed here that choice was made
 * on github.com, and the backend reads it back from those two values. So the assertions below
 * are largely ABSENCES, which are what regress quietly: no Connect-account button, no
 * Continue-to-GitHub dialog, no Connected-accounts section, and no status line invented to fill
 * the hole where one of them used to be.
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

describe("saving the app, and the download that rides along", () => {
  it("saves, and asks GitHub for the installations without being told to", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockResolvedValue({
      connected: [{ installationId: "99", accountLogin: "acme", targetType: "Organization" }],
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
    await waitFor(() =>
      expect(adoptInstallations).toHaveBeenCalledWith("github-app", {
        ecosystemId: "eco-1",
        providerConfigId: "cfg-1",
      }),
    );
  });

  it("says nothing about what the download found", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockResolvedValue({
      connected: [{ installationId: "99", accountLogin: "acme", targetType: "Organization" }],
      skipped: [],
    });

    render(<AddForm />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    await waitFor(() => expect(adoptInstallations).toHaveBeenCalled());
    // Save reports on the save. Reporting GitHub's answer here is how a button that stores
    // fields starts being read as a button that verifies them — which is the Test button's job,
    // and the reason there are two.
    expect(screen.getByText("integration added")).toBeTruthy();
    expect(screen.queryByText(/Connected acme/)).toBeNull();
  });

  it("saves anyway when GitHub refuses the credentials", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockRejectedValue(new Error("401 A JSON web token could not be decoded"));
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    // The optimization is best-effort by construction: most of the time it works and the lists
    // are there before anyone asks. When it does not, the operator is not stopped mid-save over
    // it — they find out when they press Test, or when the repository picker says why it is
    // empty. A save that could be blocked by github.com being down is not a save.
    await waitFor(() => expect(saved).toHaveBeenCalledWith(SAVED));
    expect(screen.getByText("integration added")).toBeTruthy();
    expect(screen.queryByText(/401 A JSON web token/)).toBeNull();
  });

  it("creates exactly one integration for one press of Add", async () => {
    createProviderConfig.mockResolvedValue(SAVED);
    adoptInstallations.mockRejectedValue(new Error("401 bad key"));
    const saved = vi.fn();

    render(<AddForm onSaved={saved} />);
    fillTheApp();
    fireEvent.click(screen.getByRole("button", { name: "Add Integration" }));

    await waitFor(() => expect(saved).toHaveBeenCalledWith(SAVED));
    // A failed download is not a failed save, so there is no half-created row to correct on a
    // retry — which is what the create/update bookkeeping this form used to carry existed for.
    expect(createProviderConfig).toHaveBeenCalledTimes(1);
    expect(updateProviderConfig).not.toHaveBeenCalled();
  });

  it("offers no Test button on a form with nothing saved yet", () => {
    render(<AddForm />);
    fillTheApp();
    // Test asks about STORED credentials. Before the first save there are none, so the button
    // would either lie about what it tested or fail on a config id that does not exist.
    expect(screen.queryByRole("button", { name: "Test" })).toBeNull();
  });
});

describe("the Test button", () => {
  it("downloads the installations and names them", async () => {
    adoptInstallations.mockResolvedValue({
      connected: [
        { installationId: "99", accountLogin: "acme", targetType: "Organization" },
        { installationId: "100", accountLogin: "someone", targetType: "User" },
      ],
      skipped: [],
    });

    render(<SavedForm />);
    // Nothing has reached GitHub yet: opening an integration is not a question anyone asked.
    expect(adoptInstallations).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/Connected acme, someone\./)).toBeTruthy();
    expect(adoptInstallations).toHaveBeenCalledWith("github-app", {
      ecosystemId: "eco-1",
      providerConfigId: "cfg-1",
    });
  });

  it("says what was already connected rather than reporting it as new", async () => {
    adoptInstallations.mockResolvedValue({
      connected: [],
      // A skip that carries a connectionId is one THIS ecosystem already holds — re-testing a
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

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/acme was already connected\./)).toBeTruthy();
  });

  it("distinguishes credentials that work from an app installed nowhere", async () => {
    // Valid credentials, no installations. GitHub answered, so this is not an error — it is a
    // true answer with its own fix, and stating it as a failure would send the operator back to
    // a private key that was never the problem.
    adoptInstallations.mockResolvedValue({ connected: [], skipped: [] });

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/isn't installed on any account yet/)).toBeTruthy();
  });

  it("carries GitHub's own words when the key is refused", async () => {
    adoptInstallations.mockRejectedValue(new Error("401 A JSON web token could not be decoded"));

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/401 A JSON web token could not be decoded/)).toBeTruthy();
  });

  it("says a connection stands even when its repository list did not come down", async () => {
    // The connection was made. Only the download behind it failed, so this is a warning on a
    // CONNECTED installation and not a skip — reporting it as a skip would send an operator to
    // fix an integration that is fine, and would make the connected count wrong.
    adoptInstallations.mockResolvedValue({
      connected: [
        {
          installationId: "99",
          accountLogin: "acme",
          targetType: "Organization",
          connectionId: "conn-1",
          warning: "GitHub refused to list the installation repositories: 503",
        },
      ],
      skipped: [],
    });

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/Connected acme\./)).toBeTruthy();
    // Said out loud HERE, because the next thing that happens is somebody opening the picker,
    // and finding out there why it is empty is finding out too late.
    expect(
      screen.getByText(/acme is connected, but its repository list could not be downloaded: GitHub refused to list the installation repositories: 503/),
    ).toBeTruthy();
  });

  it("says the same about one that was already connected", async () => {
    // Re-testing a working integration is exactly when a stale list is most likely, so the
    // warning has to survive the already-connected path too.
    adoptInstallations.mockResolvedValue({
      connected: [],
      skipped: [
        {
          installationId: "99",
          accountLogin: "acme",
          targetType: "Organization",
          connectionId: "conn-1",
          skipped: "already connected",
          warning: "GitHub refused to list the installation repositories: 503",
        },
      ],
    });

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/acme was already connected\./)).toBeTruthy();
    expect(screen.getByText(/its repository list could not be downloaded/)).toBeTruthy();
  });

  it("will not test a key the backend has never seen", async () => {
    render(<SavedForm />);
    fireEvent.change(screen.getByLabelText("Private key"), {
      target: { value: "-----BEGIN RSA PRIVATE KEY-----\nnew\n-----END RSA PRIVATE KEY-----" },
    });

    // Testing what is typed rather than what is stored would report on credentials that do not
    // exist yet, and nothing on screen would say which of the two the answer was about.
    const test = screen.getByRole("button", { name: "Test" }) as HTMLButtonElement;
    expect(test.disabled).toBe(true);
    expect(screen.getByText("Save your changes before testing them.")).toBeTruthy();
    fireEvent.click(test);
    expect(adoptInstallations).not.toHaveBeenCalled();
  });
});

describe("the connect step that is no longer there", () => {
  it("offers no Connect-account button on a saved GitHub App", () => {
    render(<SavedForm />);
    // The button, and the "Continue to GitHub App" dialog behind it, are the intermediate step
    // this whole path removed. Nothing may put them back for this auth method.
    expect(screen.queryByRole("button", { name: "Connect account" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Continue to GitHub App" })).toBeNull();
  });

  it("draws no Connected-accounts section at all", () => {
    render(<SavedForm />);
    // The section outlived its button, and a section whose only content was the button it lost
    // is a heading over a hole — which is how it came to hold a status line nobody asked for.
    // What an app can reach is a question the repository picker asks, where the answer changes
    // what the operator can do; here it changed nothing.
    expect(screen.queryByText("Connected accounts")).toBeNull();
    expect(screen.queryByText(/Checking GitHub for installations/)).toBeNull();
    expect(screen.queryByText("No account connected.")).toBeNull();
  });

  it("reaches GitHub only when asked", () => {
    render(<SavedForm />);
    // Opening an integration is not a question. Every automatic round-trip that used to happen
    // here had to render SOMETHING while it was in flight, and every one of those somethings was
    // a sentence about a state the operator had not enquired about.
    expect(adoptInstallations).not.toHaveBeenCalled();
    expect(listConnections).not.toHaveBeenCalled();
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
