// @vitest-environment jsdom
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { render, screen, fireEvent, waitFor, cleanup, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { MaskedProviderConfig, ProviderCatalogEntry } from "@agentic-toolkit/data/integrations";

/**
 * Adding an integration is a PICKER and then a dialog about one service, and every assertion
 * below is about that seam. It used to be one 85vh modal with the list down the left and a full
 * provider form inflated down the right — a shape whose add button sat at the bottom of a
 * scrolling column where Enter could not reach it and no Cancel sat beside it, whose rows named
 * a service and described none of them, and which resized under the cursor as the filter
 * narrowed. So: a fixed-height list that scrolls inside a frame that does not move, driven from
 * the keyboard, and a second dialog with OK and Cancel in its footer.
 */

// Stub the integrations client so no real network happens. The modal takes its catalog
// via the `providers` prop (the parent calls listProviders), so createProviderConfig is
// the only method the Add flow actually invokes; listProviders is stubbed for parity.
const { createProviderConfig, listProviders } = vi.hoisted(() => ({
  createProviderConfig: vi.fn(),
  listProviders: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: { createProviderConfig, listProviders },
}));

import { AddIntegrationModal } from "./AddIntegrationModal";
import { saveDraft } from "./integration-draft-store";
import { intBlank } from "./IntegrationDetail";

// The hub vitest config has no global afterEach; tear each render (+ its portalled
// dialog) down explicitly so it doesn't leak into the next test.
afterEach(cleanup);
beforeEach(() => {
  window.localStorage.clear();
  createProviderConfig.mockReset();
  listProviders.mockReset();
});

function mkProvider(over: Partial<ProviderCatalogEntry>): ProviderCatalogEntry {
  return {
    providerId: over.providerId ?? "x",
    displayName: over.displayName ?? "X",
    subtitle: over.subtitle ?? "",
    description: over.description ?? "",
    links: over.links ?? [],
    authMethod: over.authMethod ?? "api_key",
    serviceTypes: over.serviceTypes ?? [],
    capabilities: over.capabilities ?? ["write"],
    defaultPollIntervalMs: over.defaultPollIntervalMs ?? 0,
    configFields: over.configFields,
  };
}

// Deliberately UNSORTED so the alphabetize assertion is meaningful.
const PROVIDERS: ProviderCatalogEntry[] = [
  mkProvider({
    providerId: "twilio",
    displayName: "Twilio",
    subtitle: "SMS and voice messaging",
    description: "Send text messages and place calls from your own Twilio account.",
    configFields: [{ key: "accountSid", label: "Account SID", secret: false, required: true }],
  }),
  mkProvider({
    providerId: "postmark",
    displayName: "Postmark",
    subtitle: "Transactional email",
    description: "Deliver receipts, password resets and other one-to-one email.",
  }),
  mkProvider({
    providerId: "sendgrid",
    displayName: "SendGrid",
    subtitle: "Email delivery",
    description: "Bulk and transactional email over SendGrid's API.",
  }),
];

const SAVED_ROW: MaskedProviderConfig = {
  id: "cfg-1",
  ecosystemId: "eco-1",
  providerId: "twilio",
  name: "My Twilio",
  rdid: "integration.twilio.cfg-1",
  config: {},
  hasSecret: false,
};

function renderModal({
  providers = PROVIDERS as ProviderCatalogEntry[] | null,
  initialFilter,
}: { providers?: ProviderCatalogEntry[] | null; initialFilter?: string } = {}) {
  const onOpenChange = vi.fn();
  const onAdded = vi.fn();
  render(
    <AddIntegrationModal
      open
      onOpenChange={onOpenChange}
      ecosystemId="eco-1"
      providers={providers}
      onAdded={onAdded}
      initialFilter={initialFilter}
    />,
  );
  return { onOpenChange, onAdded };
}

/** The row for a service, by the name it shows. Rows are listbox options, not buttons: there is
 *  one focus point (the filter box) and the arrows move a highlight, which is the combobox
 *  pattern the platform already has a role vocabulary for. */
const row = (name: string) => screen.getByRole("option", { name: new RegExp(name) });

/** The one dialog carrying this title, of however many are open. */
const dialogTitled = (title: string) =>
  screen
    .getAllByRole("dialog")
    .find((d) => within(d).queryByText(title, { selector: '[data-slot="dialog-title"]' }));

describe("the picker", () => {
  it("focuses the filter input on open", async () => {
    renderModal();
    const filter = screen.getByLabelText("Filter services");
    await waitFor(() => expect(document.activeElement).toBe(filter));
  });

  it("renders every provider, alphabetized by display name", () => {
    renderModal();
    const names = screen
      .getAllByRole("option")
      .map((o) => o.querySelector("span")?.textContent);
    expect(names).toEqual(["Postmark", "SendGrid", "Twilio"]);
  });

  it("shows each service's description, not just its name", () => {
    // The catalog has always carried this copy and the list never showed it, so a picker whose
    // whole job is "which of these do I want" answered with a name and one word. "GitHub" vs.
    // "GitHub App" is exactly the pair that decides wrongly without it.
    renderModal();
    expect(
      within(row("Twilio")).getByText(/Send text messages and place calls/),
    ).toBeTruthy();
  });

  it("filters by subtitle — typing 'sms' narrows to Twilio only", () => {
    renderModal();
    fireEvent.change(screen.getByLabelText("Filter services"), { target: { value: "sms" } });
    expect(screen.getAllByRole("option").map((o) => o.querySelector("span")?.textContent)).toEqual([
      "Twilio",
    ]);
  });

  it("filters by description too, now that the row shows one", () => {
    // A filter that cannot find the words the operator is reading looks broken.
    renderModal();
    fireEvent.change(screen.getByLabelText("Filter services"), {
      target: { value: "password resets" },
    });
    expect(screen.getAllByRole("option").map((o) => o.querySelector("span")?.textContent)).toEqual([
      "Postmark",
    ]);
  });

  it("starts on initialFilter, and the operator can clear it", () => {
    // Shipr's Connections passes "Code" so the picker opens on the forges. It is a starting
    // VALUE in a visible box, not a hidden restriction — `providerIds` is the restriction.
    renderModal({ initialFilter: "SMS" });
    expect((screen.getByLabelText("Filter services") as HTMLInputElement).value).toBe("SMS");
    expect(screen.getAllByRole("option")).toHaveLength(1);
    fireEvent.change(screen.getByLabelText("Filter services"), { target: { value: "" } });
    expect(screen.getAllByRole("option")).toHaveLength(3);
  });

  it("keeps the frame a fixed height, so filtering cannot resize the dialog", () => {
    // The one scroll region is the list; everything around it is fixed. A dialog that grows and
    // shrinks as you type moves the thing you are aiming at.
    renderModal();
    const panel = dialogTitled("Add integration")!;
    expect(panel.className).toMatch(/h-\[32rem\]/);
    expect(screen.getByRole("listbox", { name: "Services" }).className).toMatch(/overflow-y-auto/);
  });

  it("highlights the first visible row, and re-derives it when the filter moves on", () => {
    // Derived rather than stored: a stored highlight spends one render pointing at a row the
    // filter has just removed, and that is exactly the render Enter can land in.
    renderModal();
    expect(row("Postmark").getAttribute("aria-selected")).toBe("true");
    fireEvent.change(screen.getByLabelText("Filter services"), { target: { value: "sms" } });
    expect(row("Twilio").getAttribute("aria-selected")).toBe("true");
  });

  it("moves the highlight with the arrow keys without leaving the filter box", async () => {
    renderModal();
    const filter = screen.getByLabelText("Filter services");
    await waitFor(() => expect(document.activeElement).toBe(filter));
    await userEvent.keyboard("{ArrowDown}");
    expect(row("SendGrid").getAttribute("aria-selected")).toBe("true");
    // Focus never moves, so typing keeps filtering — which is why the filter box points
    // `aria-activedescendant` at the highlighted row rather than the row taking focus.
    expect(document.activeElement).toBe(filter);
    expect(filter.getAttribute("aria-activedescendant")).toBe(row("SendGrid").id);
    await userEvent.keyboard("{ArrowUp}");
    expect(row("Postmark").getAttribute("aria-selected")).toBe("true");
  });

  it("opens the highlighted service's own dialog on Enter", async () => {
    renderModal();
    await waitFor(() => expect(document.activeElement).toBe(screen.getByLabelText("Filter services")));
    await userEvent.keyboard("{ArrowDown}{ArrowDown}{Enter}");
    const panel = dialogTitled("Twilio")!;
    expect(panel).toBeTruthy();
    // The service's own dialog says what the service is — the same copy the row showed. Scoped
    // to the dialog, because the picker is still behind it saying the same thing.
    expect(within(panel).getByText(/Send text messages and place calls/)).toBeTruthy();
  });

  it("opens it from the footer OK too", async () => {
    renderModal();
    fireEvent.click(row("SendGrid"));
    await userEvent.click(screen.getByRole("button", { name: "OK" }));
    expect(dialogTitled("SendGrid")).toBeTruthy();
  });

  it("cancels without adding anything", async () => {
    const { onOpenChange, onAdded } = renderModal();
    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(onAdded).not.toHaveBeenCalled();
    expect(createProviderConfig).not.toHaveBeenCalled();
  });

  it("shows the resume banner on open when a draft exists for the ecosystem", () => {
    saveDraft("eco-1", "sendgrid", { ...intBlank("sendgrid"), name: "Draft SendGrid" }, []);
    renderModal();
    expect(screen.getByText(/unfinished integration/i)).toBeTruthy();
    expect(screen.getByRole("button", { name: /Resume/i })).toBeTruthy();
  });
});

describe("the service's own dialog", () => {
  /** Open the picker and go straight into Twilio's dialog. */
  async function openTwilio() {
    const handles = renderModal();
    fireEvent.click(row("Twilio"));
    await userEvent.click(screen.getByRole("button", { name: "OK" }));
    return handles;
  }

  it("adds an integration from its footer OK", async () => {
    createProviderConfig.mockResolvedValue(SAVED_ROW);
    const { onAdded, onOpenChange } = await openTwilio();

    const name = screen.getByLabelText("Name") as HTMLInputElement;
    const sid = screen.getByLabelText("Account SID") as HTMLInputElement;
    const ok = screen.getByRole("button", { name: /Add Integration/i }) as HTMLButtonElement;

    // Disabled until name + the required field are present.
    expect(ok.disabled).toBe(true);
    fireEvent.change(name, { target: { value: "My Twilio" } });
    fireEvent.change(sid, { target: { value: "AC123" } });
    expect(ok.disabled).toBe(false);

    fireEvent.click(ok);

    await waitFor(() => expect(createProviderConfig).toHaveBeenCalledTimes(1));
    expect(createProviderConfig).toHaveBeenCalledWith(
      "eco-1",
      expect.objectContaining({ providerId: "twilio", name: "My Twilio" }),
    );
    // BOTH dialogs close, and the pane's onAdded selects the new instance — so what the operator
    // is left looking at is the integration they just added, on its own detail. The old modal
    // stayed open with a cleared form, which is a poor answer to "did that work?".
    await waitFor(() => expect(onAdded).toHaveBeenCalledWith(SAVED_ROW));
    expect(onOpenChange).toHaveBeenCalledWith(false);
    expect(dialogTitled("Twilio")).toBeUndefined();
  });

  it("submits on Enter from a field, because OK is a form submit", async () => {
    // The whole reason the button moved to the footer and the body was split off behind a hook:
    // a `<form>` wraps the scroll region and the footer together, so Enter reaches the submit
    // button by the platform's own implicit-submission rule rather than a keydown handler that
    // would have to re-decide what Enter means inside every kind of field.
    createProviderConfig.mockResolvedValue(SAVED_ROW);
    await openTwilio();
    fireEvent.change(screen.getByLabelText("Name"), { target: { value: "My Twilio" } });
    fireEvent.change(screen.getByLabelText("Account SID"), { target: { value: "AC123" } });

    (screen.getByLabelText("Account SID") as HTMLInputElement).focus();
    await userEvent.keyboard("{Enter}");

    await waitFor(() => expect(createProviderConfig).toHaveBeenCalledTimes(1));
  });

  it("will not post a draft on Enter that a click could not post", async () => {
    // Enter now reaches submit through the form, so the "is this submittable" gate has to live
    // in `run()` and not only on the button's `disabled`.
    await openTwilio();
    (screen.getByLabelText("Name") as HTMLInputElement).focus();
    await userEvent.keyboard("{Enter}");
    expect(createProviderConfig).not.toHaveBeenCalled();
  });

  it("goes back to the picker on Cancel, adding nothing", async () => {
    const { onOpenChange, onAdded } = await openTwilio();
    await userEvent.click(
      within(dialogTitled("Twilio")!).getByRole("button", { name: "Cancel" }),
    );
    expect(dialogTitled("Twilio")).toBeUndefined();
    expect(dialogTitled("Add integration")).toBeTruthy();
    // Cancelling one service is not cancelling the picker.
    expect(onOpenChange).not.toHaveBeenCalled();
    expect(onAdded).not.toHaveBeenCalled();
    expect(createProviderConfig).not.toHaveBeenCalled();
  });

  it("does not repeat the provider card the picker already showed", async () => {
    // Its title bar carries the name and its description line carries the copy; a "What this
    // does" card an inch below is how a four-field dialog becomes a page.
    await openTwilio();
    const panel = dialogTitled("Twilio")!;
    expect(within(panel).queryByText("What this does")).toBeNull();
    expect(within(panel).getByText("Configuration")).toBeTruthy();
  });
});
