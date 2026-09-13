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
  testProviderConfig,
  testProviderCredentials,
} = vi.hoisted(() => ({
  getInstallUrl: vi.fn(),
  updateProviderConfig: vi.fn(),
  createProviderConfig: vi.fn(),
  adoptInstallations: vi.fn(),
  listConnections: vi.fn(),
  testProviderConfig: vi.fn(),
  testProviderCredentials: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    getInstallUrl,
    updateProviderConfig,
    createProviderConfig,
    adoptInstallations,
    listConnections,
    testProviderConfig,
    testProviderCredentials,
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
  testProviderConfig.mockReset();
  testProviderCredentials.mockReset();
  // The default for the tests that are about the FORM: nothing installed, nothing connected.
  // Each connect test states its own.
  adoptInstallations.mockResolvedValue({ connected: [], skipped: [] });
  // The prose is the BACKEND's now — these two answer with what it answered, and the assertions
  // below are about which call was made and how its answer is drawn, never about the wording.
  testProviderConfig.mockResolvedValue({ ok: true, summary: "Tested.", notes: [] });
  testProviderCredentials.mockResolvedValue({ ok: true, summary: "Tested.", notes: [] });
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
  // Published by the catalog, never re-derived here. It is the ONLY thing that decides whether a
  // Test button is drawn — see `useIntegrationTest` — so a fixture that omits it draws none.
  testable: true,
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
  onAdopted,
}: {
  provider?: ProviderCatalogEntry;
  config?: MaskedProviderConfig;
  onAdopted?: () => void;
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
      onAdopted={onAdopted}
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

  it("tests the DRAFT on a form with nothing saved yet, and writes nothing", async () => {
    render(<AddForm />);
    fillTheApp();

    // There used to be no button here at all, on the argument that Test asks about STORED
    // credentials and before the first save there are none. The argument was about the CALL, not
    // about the question: `test-credentials` probes what is typed and writes no config, no
    // connection and no cache — so the answer is about exactly the key on the screen, which is
    // the one thing the operator wants to know before committing it.
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    await waitFor(() =>
      expect(testProviderCredentials).toHaveBeenCalledWith("github-app", {
        ecosystemId: "eco-1",
        clientId: "123456",
        clientSecret: "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----",
        fields: undefined,
        providerConfigId: undefined,
      }),
    );
    // A probe, not a save: nothing was created by pressing it.
    expect(createProviderConfig).not.toHaveBeenCalled();
    expect(adoptInstallations).not.toHaveBeenCalled();
  });

  it("will not probe a draft with no credential in it", () => {
    render(<AddForm />);
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "ADH deploys" } });

    const test = screen.getByRole("button", { name: "Test" }) as HTMLButtonElement;
    expect(test.disabled).toBe(true);
    expect(screen.getByText("Enter a credential to test.")).toBeTruthy();
    fireEvent.click(test);
    expect(testProviderCredentials).not.toHaveBeenCalled();
  });
});

describe("the Test button", () => {
  it("asks the backend about the STORED credentials and shows what it said", async () => {
    testProviderConfig.mockResolvedValue({
      ok: true,
      summary: "2 accounts reachable.",
      notes: ["Connected acme.", "someone was already connected."],
    });

    render(<SavedForm />);
    // Nothing has reached the backend yet: opening an integration is not a question anyone asked.
    expect(testProviderConfig).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText("2 accounts reachable.")).toBeTruthy();
    // Every supporting line is shown too. They are the part that names the accounts, and an
    // operator who reads only the summary cannot tell WHICH four of five came back.
    expect(screen.getByText("Connected acme.")).toBeTruthy();
    expect(screen.getByText("someone was already connected.")).toBeTruthy();
    expect(testProviderConfig).toHaveBeenCalledWith("eco-1", "cfg-1");
  });

  it("says nothing of its own about what came back", async () => {
    // THE SENTENCE IS THE BACKEND'S, and this is the assertion that keeps it there. The console
    // used to assemble it from the adopt's connected/skipped rows — a second copy of a rule the
    // server already had, which then had to be kept in step with it by hand and was not.
    testProviderConfig.mockResolvedValue({
      ok: true,
      summary: "The app isn't installed on any account yet.",
      notes: [],
    });

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText("The app isn't installed on any account yet.")).toBeTruthy();
    expect(adoptInstallations).not.toHaveBeenCalled();
  });

  it("draws a refusal as a refusal, not as a neutral status line", async () => {
    // `ok: false` resolves rather than throwing, so that "Test selected" over four integrations
    // renders four results instead of one exception. That makes it easy to draw a rejected key
    // in the same grey as a successful one, which is the failure this guards.
    testProviderConfig.mockResolvedValue({
      ok: false,
      summary: "GitHub refused these credentials: 401 Bad credentials",
      notes: [],
    });

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    const said = await screen.findByText("GitHub refused these credentials: 401 Bad credentials");
    expect(said.className).toContain("text-apt-red");
  });

  it("tells the host to re-read its accounts when the test adopted some", async () => {
    // Test is not a read-only probe for a GitHub App: the call it makes is the one that CREATES
    // the connection rows. Four integrations added briskly showed two in the repository picker
    // because nothing said so. `adopted` is the backend saying it happened.
    testProviderConfig.mockResolvedValue({
      ok: true,
      summary: "1 account reachable.",
      notes: ["Connected acme."],
      adopted: { connected: [{ installationId: "99", accountLogin: "acme", targetType: "Organization" }], skipped: [] },
    });
    const adopted = vi.fn();

    render(<SavedForm onAdopted={adopted} />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    await waitFor(() => expect(adopted).toHaveBeenCalled());
  });

  it("stays quiet when there was nothing to adopt", async () => {
    // A provider whose test is a plain credential probe — Vercel's, say — writes nothing, so a
    // host that re-read its connection list on every Test would be re-reading it for nothing.
    testProviderConfig.mockResolvedValue({ ok: true, summary: "Vercel accepted these.", notes: [] });
    const adopted = vi.fn();

    render(<SavedForm onAdopted={adopted} />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText("Vercel accepted these.")).toBeTruthy();
    expect(adopted).not.toHaveBeenCalled();
  });

  it("reports a request that could not be made at all as an error", async () => {
    // The other half of the shape: a refused CREDENTIAL is a result, a broken REQUEST is not.
    testProviderConfig.mockRejectedValue(new Error("integration not found"));

    render(<SavedForm />);
    fireEvent.click(screen.getByRole("button", { name: "Test" }));

    expect(await screen.findByText(/integration not found/)).toBeTruthy();
  });

  it("will not test a key the backend has never seen", async () => {
    render(<SavedForm />);
    fireEvent.change(screen.getByLabelText("Private key"), {
      target: { value: "-----BEGIN RSA PRIVATE KEY-----\nnew\n-----END RSA PRIVATE KEY-----" },
    });

    // Testing what is typed rather than what is stored would report on credentials that do not
    // exist yet, and nothing on screen would say which of the two the answer was about. (The Add
    // dialog CAN test a draft — but it probes, and there is no stored key there to confuse it with.)
    const test = screen.getByRole("button", { name: "Test" }) as HTMLButtonElement;
    expect(test.disabled).toBe(true);
    expect(screen.getByText("Save your changes before testing them.")).toBeTruthy();
    fireEvent.click(test);
    expect(testProviderConfig).not.toHaveBeenCalled();
  });

  it("draws no Test button for a provider the catalog cannot test", () => {
    // The console keeps no list of which providers have a test. It used to — spelled
    // `authMethod === "github_app"` — and that list was wrong about Vercel, which has declared a
    // validation endpoint all along and simply had no button.
    render(<SavedForm provider={{ ...GITHUB_APP, testable: false }} />);
    expect(screen.queryByRole("button", { name: "Test" })).toBeNull();
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
