// @vitest-environment jsdom
import { useState } from "react";
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import type { ProviderCatalogEntry, SafeConnection } from "@agentic-toolkit/data/integrations";
import { SettingsDirtyProvider, useSettingsDirty } from "@agentic-toolkit/resource";

vi.mock("@agentic-toolkit/auth", () => ({
  reportUnexpectedAuthError: vi.fn(),
}));

// SettingsDirtyProvider mounts its own UnsavedChangesGuard when no rail host is above it, and
// that guard passes onNavigate={(href) => router.push(href)}. There is no app-router context
// under vitest (same mock as settingsDirtyBridge.test.tsx).
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

const { patchSettings, listConnections } = vi.hoisted(() => ({
  patchSettings: vi.fn(),
  listConnections: vi.fn(),
}));
vi.mock("@agentic-toolkit/data/integrations", () => ({
  integrationsApi: {
    listConnections,
    sync: vi.fn(),
    disconnect: vi.fn(),
    patchSettings,
  },
}));

// Not under test here — stub it out so rendering ProviderConnections doesn't also
// have to satisfy ConnectAccountDialog's own (unrelated) wiring.
vi.mock("./ConnectAccountDialog", () => ({
  ConnectAccountDialog: () => null,
}));

import { ProviderConnections } from "./ProviderConnections";

afterEach(cleanup);
beforeEach(() => {
  patchSettings.mockReset();
  listConnections.mockReset();
});

function provider(providerId: string): ProviderCatalogEntry {
  return {
    providerId,
    displayName: providerId,
    subtitle: "",
    description: "",
    links: [],
    authMethod: "oauth",
    testable: false,
    serviceTypes: [],
    capabilities: ["read"],
    defaultPollIntervalMs: 0,
  };
}

function connection(providerId: string, syncSettings: Record<string, unknown>): SafeConnection {
  return {
    id: "conn-1",
    provider: providerId,
    serviceType: "",
    status: "active",
    displayName: "Test account",
    username: "",
    externalAccountId: "",
    createdAt: "2026-07-25T00:00:00Z",
    syncSettings,
  };
}

/** Every render now goes through the fetch: the section reads the ecosystem's connections
 *  itself, so the rows — and the "Sync settings" disclosure with them — arrive a tick later. */
function renderSection(p: ProviderCatalogEntry, conns: SafeConnection[]) {
  listConnections.mockResolvedValue(conns);
  render(<ProviderConnections provider={p} ecosystemId="eco-1" providerConfig={null} />);
}

async function openSyncSettings() {
  fireEvent.click(await screen.findByRole("button", { name: /sync settings/i }));
}

function saveButton() {
  return screen.getByRole("button", { name: "Save sync settings" }) as HTMLButtonElement;
}

describe("ProviderConnections — Gmail sync settings Save is disabled at mount, enabled after an edit", () => {
  const GMAIL = provider("gmail");
  const CONN = connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 30 });

  it("is disabled at mount (loaded, unedited)", async () => {
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once the label ids are edited", async () => {
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Label ids"), { target: { value: "INBOX, IMPORTANT" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("disables again once reverted back to the loaded value", async () => {
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    const labels = screen.getByLabelText("Label ids");
    fireEvent.change(labels, { target: { value: "INBOX, IMPORTANT" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(labels, { target: { value: "INBOX" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("stays disabled on an edit that fails the window-days check, even though it's dirty", async () => {
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("History window (days)"), { target: { value: "0" } });
    expect(saveButton().disabled).toBe(true);
  });

  // The gate makes onSave's own range check unreachable by click, so the message it would have
  // set has to be rendered — otherwise an out-of-range window is just a dead button.
  it("says WHY Save is blocked for an out-of-range window", async () => {
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("History window (days)"), { target: { value: "0" } });
    expect(
      screen.getByText("Window must be a whole number of days between 1 and 366."),
    ).toBeTruthy();
  });

  // The other half of the rule. Prefilled from a STORED value that already fails the range check,
  // so the reason really is non-null at mount — only `dirty` keeps it quiet. (A connection with a
  // valid stored window would pass this test even with the `dirty` term deleted.)
  it("stays silent about an out-of-range STORED window until the user touches it", async () => {
    const stale = connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 0 });
    renderSection(GMAIL, [stale]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
    expect(screen.queryByText(/Window must be a whole number/)).toBeNull();
  });

  it("clicking Save while enabled persists, then goes back to disabled (re-baselined)", async () => {
    patchSettings.mockResolvedValue({});
    renderSection(GMAIL, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Label ids"), { target: { value: "INBOX, IMPORTANT" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.click(saveButton());
    await vi.waitFor(() => expect(patchSettings).toHaveBeenCalledTimes(1));
    await vi.waitFor(() => expect(saveButton().disabled).toBe(true));
  });
});

describe("ProviderConnections — Reddit sync settings Save is disabled at mount, enabled after an edit", () => {
  const REDDIT = provider("reddit");
  const CONN = connection("reddit", { redditSubreddits: ["typescript"], redditKeywords: ["claude"] });

  it("is disabled at mount (loaded, unedited)", async () => {
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once the watchlist is edited", async () => {
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Watched subreddits"), {
      target: { value: "typescript, LocalLLaMA" },
    });
    expect(saveButton().disabled).toBe(false);
  });

  it("disables again once reverted back to the loaded value", async () => {
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    const subs = screen.getByLabelText("Watched subreddits");
    fireEvent.change(subs, { target: { value: "typescript, LocalLLaMA" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(subs, { target: { value: "typescript" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("stays disabled on an edit that fails the subreddit-name check, even though it's dirty", async () => {
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Watched subreddits"), { target: { value: "a" } });
    expect(saveButton().disabled).toBe(true);
  });

  // Same reasoning as Gmail's: the gate makes onSave's name check unreachable, and this one names
  // the offending entry — exactly the detail a grey button can't convey.
  it("says WHY Save is blocked, naming the bad entry", async () => {
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Watched subreddits"), { target: { value: "a" } });
    expect(
      screen.getByText('"a" is not a subreddit name (letters, digits, _; 2–21 chars).'),
    ).toBeTruthy();
  });

  it("stays silent about an already-invalid STORED watchlist until the user touches it", async () => {
    const stale = connection("reddit", { redditSubreddits: ["a"], redditKeywords: [] });
    renderSection(REDDIT, [stale]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
    expect(screen.queryByText(/is not a subreddit name/)).toBeNull();
  });

  it("clicking Save while enabled persists, then goes back to disabled (re-baselined)", async () => {
    patchSettings.mockResolvedValue({});
    renderSection(REDDIT, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Watched subreddits"), {
      target: { value: "typescript, LocalLLaMA" },
    });
    expect(saveButton().disabled).toBe(false);
    fireEvent.click(saveButton());
    await vi.waitFor(() => expect(patchSettings).toHaveBeenCalledTimes(1));
    await vi.waitFor(() => expect(saveButton().disabled).toBe(true));
  });
});

describe("ProviderConnections — Mailchimp sync settings Save is disabled at mount, enabled after an edit", () => {
  const MAILCHIMP = provider("mailchimp");
  const CONN = connection("mailchimp", { audienceIds: ["list1"] });

  it("is disabled at mount (loaded, unedited)", async () => {
    renderSection(MAILCHIMP, [CONN]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once the audience ids are edited", async () => {
    renderSection(MAILCHIMP, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Audience ids"), { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("disables again once reverted back to the loaded value", async () => {
    renderSection(MAILCHIMP, [CONN]);
    await openSyncSettings();
    const ids = screen.getByLabelText("Audience ids");
    fireEvent.change(ids, { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(ids, { target: { value: "list1" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("clicking Save while enabled persists, then goes back to disabled (re-baselined)", async () => {
    patchSettings.mockResolvedValue({});
    renderSection(MAILCHIMP, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Audience ids"), { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.click(saveButton());
    await vi.waitFor(() => expect(patchSettings).toHaveBeenCalledTimes(1));
    await vi.waitFor(() => expect(saveButton().disabled).toBe(true));
  });
});

describe("ProviderConnections — Klaviyo sync settings Save is disabled at mount, enabled after an edit", () => {
  const KLAVIYO = provider("klaviyo");
  const CONN = connection("klaviyo", { audienceIds: ["list1"] });

  it("is disabled at mount (loaded, unedited)", async () => {
    renderSection(KLAVIYO, [CONN]);
    await openSyncSettings();
    expect(saveButton().disabled).toBe(true);
  });

  it("enables once the audience ids are edited", async () => {
    renderSection(KLAVIYO, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Audience ids"), { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("disables again once reverted back to the loaded value", async () => {
    renderSection(KLAVIYO, [CONN]);
    await openSyncSettings();
    const ids = screen.getByLabelText("Audience ids");
    fireEvent.change(ids, { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(ids, { target: { value: "list1" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("clicking Save while enabled persists, then goes back to disabled (re-baselined)", async () => {
    patchSettings.mockResolvedValue({});
    renderSection(KLAVIYO, [CONN]);
    await openSyncSettings();
    fireEvent.change(screen.getByLabelText("Audience ids"), { target: { value: "list1, list2" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.click(saveButton());
    await vi.waitFor(() => expect(patchSettings).toHaveBeenCalledTimes(1));
    await vi.waitFor(() => expect(saveButton().disabled).toBe(true));
  });
});

// What the conversion is FOR. The route returns the ECOSYSTEM's connections, so the cache key is
// the ecosystem: one read serves every provider in the detail. Before this, each provider switch
// re-read the whole ecosystem and blanked the section to "Loading…" while it did.
describe("ProviderConnections caches the ecosystem's connections across a provider switch", () => {
  const GMAIL = provider("gmail");
  const REDDIT = provider("reddit");

  it("paints the next provider's accounts from the read already made", async () => {
    const gmailConn: SafeConnection = {
      ...connection("gmail", {}),
      id: "conn-gmail",
      displayName: "Gmail account",
    };
    const redditConn: SafeConnection = {
      ...connection("reddit", {}),
      id: "conn-reddit",
      displayName: "Reddit account",
    };
    listConnections.mockResolvedValue([gmailConn, redditConn]);

    const { rerender } = render(
      <ProviderConnections provider={GMAIL} ecosystemId="eco-1" providerConfig={null} />,
    );
    await screen.findByText("Gmail account");
    expect(screen.queryByText("Reddit account")).toBeNull();
    expect(listConnections).toHaveBeenCalledTimes(1);

    // The sibling provider in the SAME ecosystem: its account is on screen with nothing awaited,
    // and the ecosystem is not read a second time.
    rerender(<ProviderConnections provider={REDDIT} ecosystemId="eco-1" providerConfig={null} />);
    expect(screen.getByText("Reddit account")).toBeTruthy();
    expect(screen.queryByText("Gmail account")).toBeNull();
    expect(screen.queryByText("Loading…")).toBeNull();
    expect(listConnections).toHaveBeenCalledTimes(1);
  });
});

/** Reads the settings registry the way the overlay's close gate does — from an event handler. */
function DirtyReadout() {
  const { isAnyDirty } = useSettingsDirty();
  const [seen, setSeen] = useState<string | null>(null);
  return (
    <div>
      <button type="button" onClick={() => setSeen(isAnyDirty() ? "dirty" : "clean")}>
        Read
      </button>
      {seen && <p>registry sees {seen}</p>}
    </div>
  );
}

function readRegistry() {
  fireEvent.click(screen.getByRole("button", { name: "Read" }));
}

describe("the per-provider sync-settings forms report their unsaved draft to the settings registry", () => {
  const GMAIL = provider("gmail");
  const REDDIT = provider("reddit");

  async function renderIn(p: ProviderCatalogEntry, c: SafeConnection) {
    listConnections.mockResolvedValue([c]);
    render(
      <SettingsDirtyProvider>
        <DirtyReadout />
        <ProviderConnections provider={p} ecosystemId="eco-1" providerConfig={null} />
      </SettingsDirtyProvider>,
    );
    await openSyncSettings();
  }

  it("stays clean while Gmail's loaded settings are untouched", async () => {
    await renderIn(GMAIL, connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 30 }));
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });

  it("reports dirty once Gmail's label ids are edited", async () => {
    await renderIn(GMAIL, connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 30 }));
    fireEvent.change(screen.getByLabelText("Label ids"), { target: { value: "INBOX, IMPORTANT" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("goes clean again when Gmail's edit is reverted to the loaded value", async () => {
    await renderIn(GMAIL, connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 30 }));
    const labels = screen.getByLabelText("Label ids");
    fireEvent.change(labels, { target: { value: "INBOX, IMPORTANT" } });
    fireEvent.change(labels, { target: { value: "INBOX" } });
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });

  it("reports dirty on a Gmail edit Save REFUSES — an invalid draft is still unsaved work", async () => {
    await renderIn(GMAIL, connection("gmail", { gmailLabelIds: ["INBOX"], gmailWindowDays: 30 }));
    fireEvent.change(screen.getByLabelText("History window (days)"), { target: { value: "0" } });
    expect(saveButton().disabled).toBe(true);
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("stays clean while Reddit's loaded settings are untouched", async () => {
    await renderIn(REDDIT, connection("reddit", { redditSubreddits: ["aww"], redditKeywords: [] }));
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });

  it("reports dirty once Reddit's subreddits are edited", async () => {
    await renderIn(REDDIT, connection("reddit", { redditSubreddits: ["aww"], redditKeywords: [] }));
    fireEvent.change(screen.getByLabelText("Watched subreddits"), { target: { value: "aww, pics" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("withdraws the report when the sync-settings disclosure is collapsed away", async () => {
    await renderIn(REDDIT, connection("reddit", { redditSubreddits: ["aww"], redditKeywords: [] }));
    fireEvent.change(screen.getByLabelText("Watched subreddits"), { target: { value: "aww, pics" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
    // Collapsing unmounts the form and destroys the draft with it — the exit guard must not stay
    // armed for edits that no longer exist anywhere. (`expanded` picks the disclosure TRIGGER;
    // once open, "Save sync settings" matches the same name.)
    fireEvent.click(screen.getByRole("button", { name: /sync settings/i, expanded: true }));
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });
});
