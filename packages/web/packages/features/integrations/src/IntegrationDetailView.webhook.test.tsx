// @vitest-environment jsdom
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup } from "@testing-library/react";
import type {
  DeliverabilityWebhook,
  MaskedProviderConfig,
  ProviderCatalogEntry,
} from "@agentic-toolkit/data/integrations";

// Same boundary AddIntegrationModal.test.tsx stubs: no real network, everything else real.
const { createProviderConfig, updateProviderConfig, rotateWebhookSecret } = vi.hoisted(() => ({
  createProviderConfig: vi.fn(),
  updateProviderConfig: vi.fn(),
  rotateWebhookSecret: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: { createProviderConfig, updateProviderConfig, rotateWebhookSecret },
}));

import { IntegrationDetailView } from "./IntegrationDetailView";
import { intBlank } from "./IntegrationDetail";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});
beforeEach(() => {
  createProviderConfig.mockReset();
  updateProviderConfig.mockReset();
  rotateWebhookSecret.mockReset();
});

/** jsdom has no `confirm`; calling the real one throws "not implemented". */
const stubConfirm = (answer: boolean) => {
  const spy = vi.fn().mockReturnValue(answer);
  vi.stubGlobal("confirm", spy);
  return spy;
};

const POSTMARK: ProviderCatalogEntry = {
  providerId: "postmark",
  displayName: "Postmark",
  subtitle: "Transactional email",
  description: "",
  links: [],
  authMethod: "api_key",
  serviceTypes: ["email"],
  capabilities: ["write"],
  defaultPollIntervalMs: 0,
  testable: false,
  configFields: [{ key: "serverToken", label: "Server token", secret: true, required: true }],
};

// The URL addresses the ecosystem and the SECRET authenticates it — two separate strings, and
// deliberately decorrelated here so no assertion about one can be satisfied by the other.
const WEBHOOK: DeliverabilityWebhook = {
  url: "https://api.example.com/public/webhooks/postmark/eco-1",
  secretHeader: "X-Adh-Webhook-Secret",
  secret: "whsec_ecoOneOwnCredential",
  instruction:
    "In Postmark, open Servers → your server → Webhooks → Add webhook, paste this URL, add " +
    "the custom header X-Adh-Webhook-Secret carrying the secret below, and tick " +
    "Bounce, Spam Complaint and Subscription Change.",
};

function savedConfig(patch: Partial<MaskedProviderConfig>): MaskedProviderConfig {
  return {
    id: "cfg-1",
    ecosystemId: "eco-1",
    providerId: "postmark",
    name: "Our Postmark",
    rdid: "integration.postmark.cfg-1",
    config: {},
    hasSecret: true,
    ...patch,
  };
}

function renderSaved(
  config: MaskedProviderConfig | null,
  onRotated?: (row: MaskedProviderConfig) => void,
) {
  return render(
    <IntegrationDetailView
      provider={POSTMARK}
      ecosystemId="eco-1"
      mode={config ? "saved" : "add"}
      config={config}
      draft={{ ...intBlank("postmark"), name: "Our Postmark" }}
      onChange={() => {}}
      onRotated={onRotated}
    />,
  );
}

const rotateButton = () => screen.getByRole("button", { name: /generate a( new)? secret/i });

/** Busy-agnostic handle on the same control: mid-flight the label flips to "Generating…", so
 *  matching the idle label would THROW exactly when the disabled state is what we are asserting,
 *  and a test that cannot see the button cannot prove anything about it. */
const rotateControl = () => screen.getByRole("button", { name: /generat/i }) as HTMLButtonElement;

describe("IntegrationDetailView — deliverability webhook", () => {
  it("shows the derived URL, the provider setting it belongs in, the header, and the secret", () => {
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    expect(screen.getByText("Deliverability webhook")).toBeTruthy();
    expect(screen.getByText(WEBHOOK.url)).toBeTruthy();
    // The one line naming the provider's own setting — an operator must be able to find the
    // screen in Postmark without leaving this page.
    expect(screen.getByText(/Servers → your server → Webhooks/)).toBeTruthy();
    expect(screen.getByText("X-Adh-Webhook-Secret")).toBeTruthy();
    // The credential itself. Without it the operator has a URL that 401s and no way to fix it,
    // which is exactly the state the per-ecosystem secret was introduced to make visible.
    expect(screen.getByText("whsec_ecoOneOwnCredential")).toBeTruthy();
    // Bidirectional: a config that HAS a secret must never also be showing the "none stored"
    // warning, which is the other branch of the same card.
    expect(screen.queryByText(/no secret is stored/i)).toBeNull();
    // ...and the action is worded as the destructive one, not the first-time mint.
    expect(screen.getByRole("button", { name: "Generate a new secret" })).toBeTruthy();
  });

  it("copies the exact URL — not a truncated or re-derived one", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(screen.getByRole("button", { name: /copy webhook url/i }));

    await waitFor(() => expect(writeText).toHaveBeenCalledTimes(1));
    expect(writeText.mock.calls[0]![0]).toBe(WEBHOOK.url);
  });

  // Separate control from the URL copy: an operator has to paste BOTH, and a secret shown but
  // not copyable (or copying the URL by mistake) is a webhook that silently never authenticates.
  it("copies the secret, not the URL", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, { clipboard: { writeText } });
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(screen.getByRole("button", { name: /copy webhook secret/i }));

    await waitFor(() => expect(writeText).toHaveBeenCalledTimes(1));
    expect(writeText.mock.calls[0]![0]).toBe(WEBHOOK.secret);
  });

  // A config from before the per-config secret existed: the URL is real, but every event sent
  // to it is refused. Rendering the URL alone hands the operator a registration that 401s
  // forever with nothing on screen to say why.
  it("warns when the URL exists but no secret is stored, and offers the first-time mint", () => {
    renderSaved(savedConfig({ deliverabilityWebhook: { ...WEBHOOK, secret: null } }));

    expect(screen.getByText(/no secret is stored for this integration/i)).toBeTruthy();
    expect(screen.getByText(WEBHOOK.url)).toBeTruthy();
    expect(screen.queryByRole("button", { name: /copy webhook secret/i })).toBeNull();
    // Wording follows the state: nothing is being destroyed here.
    expect(screen.getByRole("button", { name: "Generate a secret" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Generate a new secret" })).toBeNull();
  });

  // `null` means the DEPLOYMENT has no public base URL, so no working address exists to hand
  // out. Rendering nothing there is indistinguishable from "already handled", which is the
  // exact silence this whole finding is about.
  it("warns, and offers no URL, when the deployment cannot build one", () => {
    renderSaved(savedConfig({ deliverabilityWebhook: null }));

    expect(screen.getByText(/no public base URL configured/i)).toBeTruthy();
    expect(screen.getByText(/never suppressed and will be mailed again/i)).toBeTruthy();
    expect(screen.queryByRole("button", { name: /copy webhook url/i })).toBeNull();
    expect(screen.queryByText(/Servers → your server → Webhooks/)).toBeNull();
    // No address means nothing a secret could authenticate — offering the mint would be a
    // button that produces a credential for a URL that does not exist.
    expect(screen.queryByRole("button", { name: /generate a( new)? secret/i })).toBeNull();
  });

  it("rotates the secret for THIS config and hands the refreshed row back", async () => {
    const confirmSpy = stubConfirm(true);
    const rotated = savedConfig({
      deliverabilityWebhook: { ...WEBHOOK, secret: "whsec_freshlyMinted" },
    });
    rotateWebhookSecret.mockResolvedValue(rotated);
    const onRotated = vi.fn();
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }), onRotated);

    fireEvent.click(rotateButton());

    await waitFor(() => expect(rotateWebhookSecret).toHaveBeenCalledTimes(1));
    // Addressed by ecosystem AND config: a rotation that dropped either would either 404 or,
    // worse, rotate a different config's credential.
    expect(rotateWebhookSecret.mock.calls[0]).toEqual(["eco-1", "cfg-1"]);
    await waitFor(() => expect(onRotated).toHaveBeenCalledWith(rotated));
    expect(confirmSpy).toHaveBeenCalledTimes(1);
  });

  // `onRotated` is optional, and a component that only rotates when someone is listening is a
  // button that silently does nothing — `onRotated?.(await rotate(...))` reads correctly but
  // optional-call short-circuits its own arguments, so the request is never sent.
  it("rotates even when no listener is attached", async () => {
    stubConfirm(true);
    rotateWebhookSecret.mockResolvedValue(savedConfig({ deliverabilityWebhook: WEBHOOK }));
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(rotateButton());

    await waitFor(() => expect(rotateWebhookSecret).toHaveBeenCalledTimes(1));
  });

  // The confirm is the whole safety story for an action that breaks a live Postmark
  // registration the instant it succeeds. A dialog that is asked but not OBEYED is no guard.
  it("does not rotate when the confirmation is declined", () => {
    stubConfirm(false);
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(rotateButton());

    expect(rotateWebhookSecret).not.toHaveBeenCalled();
    // The old credential is still on screen — nothing was optimistically cleared.
    expect(screen.getByText("whsec_ecoOneOwnCredential")).toBeTruthy();
  });

  it("surfaces a failed rotation instead of silently leaving the old secret on screen", async () => {
    stubConfirm(true);
    rotateWebhookSecret.mockRejectedValue(new Error("rotation refused"));
    const onRotated = vi.fn();
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }), onRotated);

    fireEvent.click(rotateButton());

    expect(await screen.findByText(/rotation refused/i)).toBeTruthy();
    // A failure is not a rotation: the parent must not be told to refetch, and the button must
    // come back so the operator can retry.
    expect(onRotated).not.toHaveBeenCalled();
    await waitFor(() => expect((rotateButton() as HTMLButtonElement).disabled).toBe(false));
  });

  // `disabled={busy}` is the only thing standing between an impatient double-click and TWO
  // rotations. The second one wins at the provider, so the secret the operator already copied out
  // of the first response is dead on arrival — and nothing on screen says so. The confirm() does
  // not help: it is answered once per click.
  it("cannot be fired a second time while a rotation is still in flight", async () => {
    stubConfirm(true);
    let release: (row: MaskedProviderConfig) => void = () => {};
    rotateWebhookSecret.mockReturnValue(
      new Promise<MaskedProviderConfig>((resolve) => {
        release = resolve;
      }),
    );
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(rotateControl());
    await waitFor(() => expect(rotateControl().disabled).toBe(true));

    fireEvent.click(rotateControl());
    expect(rotateWebhookSecret).toHaveBeenCalledTimes(1);

    release(savedConfig({ deliverabilityWebhook: WEBHOOK }));
    // ...and it comes back afterwards, so "disabled" is a mid-flight state and not a dead button.
    await waitFor(() => expect(rotateControl().disabled).toBe(false));
  });

  // `setError(null)` at the top of the rotation. Without it the message from the FAILED attempt is
  // still on screen after a later attempt SUCCEEDS: a fresh secret sitting under a banner saying
  // the rotation was refused, with no way to tell which one the provider now holds.
  it("clears the previous failure when a retry succeeds", async () => {
    stubConfirm(true);
    rotateWebhookSecret.mockRejectedValueOnce(new Error("rotation refused"));
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(rotateButton());
    expect(await screen.findByText(/rotation refused/i)).toBeTruthy();

    rotateWebhookSecret.mockResolvedValueOnce(savedConfig({ deliverabilityWebhook: WEBHOOK }));
    fireEvent.click(rotateButton());

    await waitFor(() => expect(rotateWebhookSecret).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(screen.queryByText(/rotation refused/i)).toBeNull());
  });

  // This is the one error on this screen that appears LATE, in response to a click. A screen
  // reader has already read past this point in the document, so a plain red <p> is never
  // encountered: the operator is told nothing at all about a rotation that did not happen.
  it("announces the rotation failure rather than only painting it", async () => {
    stubConfirm(true);
    rotateWebhookSecret.mockRejectedValue(new Error("rotation refused"));
    renderSaved(savedConfig({ deliverabilityWebhook: WEBHOOK }));

    fireEvent.click(rotateButton());

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toContain("rotation refused");
  });

  it("renders no webhook card for a provider that sends no webhook field", () => {
    renderSaved(savedConfig({}));

    expect(screen.queryByText("Deliverability webhook")).toBeNull();
    expect(screen.queryByText(/no secret is stored/i)).toBeNull();
    // Proves the card is absent because the FIELD is absent, not because the view failed to
    // render at all — without this, a crashed component would pass every assertion above.
    expect(screen.getByText("Configuration")).toBeTruthy();
    expect(screen.getByText("Postmark")).toBeTruthy();
  });

  it("renders no webhook card while adding an integration, when nothing is saved yet", () => {
    renderSaved(null);

    expect(screen.queryByText("Deliverability webhook")).toBeNull();
    expect(screen.getByRole("button", { name: /add integration/i })).toBeTruthy();
  });
});
