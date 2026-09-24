// @vitest-environment jsdom
import { describe, it, expect, afterEach, vi } from "vitest";
import { act, render, screen, fireEvent, cleanup, waitFor } from "@testing-library/react";
import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";

// SettingsDirtyProvider mounts its own UnsavedChangesGuard when no rail host is above it, and
// that guard passes onNavigate={(href) => router.push(href)}. There is no app-router context
// under vitest (same mock as settingsDirtyBridge.test.tsx).
const { push } = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));
import { SettingsDirtyProvider, useSettingsDirty } from "@agentic-toolkit/resource";
import {
  SocialLinksSection,
  socialLinkBlockedReason,
  SOCIAL_LINK_URL_REQUIRED_MESSAGE,
} from "./SocialLinksSection";
import { createSocialLink, updateSocialLink, type SocialLink } from "@agentic-toolkit/data/profile";

// The section calls useMutation/useQueryClient directly (no wrapper hook to swap), so a
// real QueryClient context is required; only the three network functions are stubbed.
// `resolvePrivacyLevel`/`socialLinksKey` stay real — they are pure helpers.
vi.mock("@agentic-toolkit/data/profile", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@agentic-toolkit/data/profile")>();
  return {
    ...actual,
    createSocialLink: vi.fn(),
    updateSocialLink: vi.fn(),
    deleteSocialLink: vi.fn(),
  };
});

const createLinkMock = vi.mocked(createSocialLink);
const updateLinkMock = vi.mocked(updateSocialLink);

// A stored row: the required URL already filled, which is what makes the "no reason while
// pristine" assertions meaningful.
const GITHUB = {
  id: "link_1",
  platform: "github",
  url: "https://github.com/mike",
  handle: "@mike",
} as unknown as SocialLink;

// The hub vitest config has no global afterEach; tear each render (+ its portalled
// dialog) down explicitly so it doesn't leak into the next test.
afterEach(() => {
  cleanup();
  createLinkMock.mockReset();
  updateLinkMock.mockReset();
});

function renderSection() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={qc}>
      <SocialLinksSection links={[GITHUB]} isLoading={false} grants={[]} hidePrivacy hideSectionTitle />
    </QueryClientProvider>,
  );
}

/** Edit is a BAR verb now, like admin's tables: tick the row, then press Edit. */
function openEdit() {
  fireEvent.click(screen.getByRole("checkbox", { name: "Select GitHub" }));
  fireEvent.click(screen.getByRole("button", { name: "Edit" }));
}

function openAdd() {
  fireEvent.click(screen.getByRole("button", { name: "Add social link" }));
}

function saveButton() {
  return screen.getByRole("button", { name: /^(Save|Saving…)$/ }) as HTMLButtonElement;
}

/** The rendered "why Save is dark" line, or null when the view is silent. */
function reason(): string | null {
  return screen.queryByRole("status")?.textContent ?? null;
}

function urlField() {
  return screen.getByPlaceholderText("https://example.com/you");
}

function handleField() {
  return screen.getByPlaceholderText("@yourhandle");
}

describe("socialLinkBlockedReason", () => {
  it("names the missing required field when the URL is blank", () => {
    expect(socialLinkBlockedReason({ platform: "github", url: "", handle: "" })).toBe(
      SOCIAL_LINK_URL_REQUIRED_MESSAGE,
    );
  });

  it("treats a whitespace-only URL as blank — the write trims it away to nothing", () => {
    expect(socialLinkBlockedReason({ platform: "github", url: "   ", handle: "" })).toBe(
      SOCIAL_LINK_URL_REQUIRED_MESSAGE,
    );
  });

  it("is null once the URL has content — platform defaults and the handle is optional", () => {
    expect(
      socialLinkBlockedReason({ platform: "github", url: "https://x.test/me", handle: "" }),
    ).toBeNull();
  });
});

describe("SocialLinksSection — editing a stored link", () => {
  it("opens with Save dark and says nothing: a loaded row is valid, and 'nothing changed yet' explains itself", () => {
    renderSection();
    openEdit();
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBeNull();
  });

  it("enables Save once the URL actually differs from the loaded row", () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/mfullerton" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("enables Save on a handle-only change — the diff covers every editable field, not just the required one", () => {
    renderSection();
    openEdit();
    fireEvent.change(handleField(), { target: { value: "@mikef" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("goes back to dark on an edit-and-revert — Save tracks the VALUE, not touched-ness", () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/mfullerton" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(urlField(), { target: { value: "https://github.com/mike" } });
    expect(saveButton().disabled).toBe(true);
  });

  // NOTE: there is deliberately no "surrounding whitespace on the URL leaves Save dark"
  // case here, unlike AddressesSection. The URL box is an `input[type=url]`, whose value
  // SANITIZATION algorithm strips leading/trailing whitespace before the value is ever
  // readable — in jsdom and in real browsers alike. A test for it would pass no matter
  // what `sameLink` does, which is exactly the kind of assertion-free test this branch
  // exists to stamp out. (The trimming in `sameLink`/`handleSave` stays: it keeps the two
  // in step by construction and survives the field ever changing type.)

  it("says WHY when the URL is emptied, instead of just greying out", () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "" } });
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBe(SOCIAL_LINK_URL_REQUIRED_MESSAGE);
  });

  it("does not write when the unchanged form is submitted directly (Enter bypasses the dark button)", async () => {
    renderSection();
    openEdit();
    const form = saveButton().closest("form")!;
    // Awaited, not asserted straight after the submit: react-query invokes the mutationFn
    // in a MICROTASK, so a synchronous `not.toHaveBeenCalled()` would pass even with the
    // guard deleted — the write simply hadn't happened yet.
    await act(async () => {
      fireEvent.submit(form);
    });
    expect(updateLinkMock).not.toHaveBeenCalled();
  });

  it("writes once for one edit — a second submit during the in-flight write is ignored", async () => {
    updateLinkMock.mockReturnValue(new Promise(() => {})); // never settles
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/mfullerton" } });
    const form = saveButton().closest("form")!;
    fireEvent.submit(form);
    await waitFor(() => expect(updateLinkMock).toHaveBeenCalledTimes(1));
    await act(async () => {
      fireEvent.submit(form);
    });
    expect(updateLinkMock).toHaveBeenCalledTimes(1);
  });

  it("sends the whole draft under the row's id — the edited URL plus the untouched fields", async () => {
    updateLinkMock.mockResolvedValue(GITHUB);
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/mfullerton" } });
    fireEvent.submit(saveButton().closest("form")!);
    await waitFor(() => expect(updateLinkMock).toHaveBeenCalledTimes(1));
    expect(updateLinkMock.mock.calls[0]![0]).toBe("link_1");
    expect(updateLinkMock.mock.calls[0]![1]).toEqual({
      platform: "github",
      url: "https://github.com/mfullerton",
      handle: "@mike",
    });
  });
});

describe("SocialLinksSection — adding a link", () => {
  it("opens dark and says which field it is waiting on — an empty form has no baseline to explain itself", () => {
    renderSection();
    openAdd();
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBe(SOCIAL_LINK_URL_REQUIRED_MESSAGE);
  });

  it("enables Save and falls silent once the required field is filled", () => {
    renderSection();
    openAdd();
    fireEvent.change(urlField(), { target: { value: "https://x.test/me" } });
    expect(saveButton().disabled).toBe(false);
    expect(reason()).toBeNull();
  });

  it("does not create when a blank form is submitted directly", async () => {
    renderSection();
    openAdd();
    const form = saveButton().closest("form")!;
    await act(async () => {
      fireEvent.submit(form);
    });
    expect(createLinkMock).not.toHaveBeenCalled();
  });
});

// The dialog's `onOpenChange` is how Escape, a backdrop click and the × ALL reach the close
// path, so firing Escape exercises that whole path rather than a bespoke one.
describe("SocialLinksSection dialog — Escape on a dirty draft asks before discarding", () => {
  it("does not close on Escape while dirty; Discard then closes", async () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/someone-else" } });

    fireEvent.keyDown(urlField(), { key: "Escape" });
    expect(screen.queryByText("Edit social link")).not.toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Discard" }));
    await waitFor(() => expect(screen.queryByText("Edit social link")).toBeNull());
  });

  it("Stay keeps the dialog open with the edit intact", async () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/someone-else" } });

    fireEvent.keyDown(urlField(), { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Stay" }));
    await waitFor(() => expect(screen.queryByRole("button", { name: "Discard" })).toBeNull());
    expect((urlField() as HTMLInputElement).value).toBe("https://github.com/someone-else");
  });

  it("closes immediately on Escape when the loaded link is untouched — no alert", async () => {
    renderSection();
    openEdit();
    fireEvent.keyDown(urlField(), { key: "Escape" });
    await waitFor(() => expect(screen.queryByText("Edit social link")).toBeNull());
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });

  // The false-positive test, and the reason the close gate CANNOT reuse the Save gate's
  // `dirty`: that one is unconditionally true in add mode. Reusing it would nag on every
  // abandoned Add.
  it("closes immediately on Escape from an untouched Add dialog — a blank draft is not unsaved work", async () => {
    renderSection();
    openAdd();
    fireEvent.keyDown(urlField(), { key: "Escape" });
    await waitFor(() => expect(screen.queryByText("Add social link")).toBeNull());
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });

  it("a half-filled Add dialog IS unsaved work — Escape asks", () => {
    renderSection();
    openAdd();
    fireEvent.change(urlField(), { target: { value: "https://example.com/me" } });
    fireEvent.keyDown(urlField(), { key: "Escape" });
    expect(screen.queryByText("Add social link")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy();
  });

  it("Cancel is gated the same way as Escape — the two are one close path", () => {
    renderSection();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.com/someone-else" } });
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByText("Edit social link")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy();
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
  // `hidden: true` because Base UI's Dialog inerts (aria-hidden) everything behind it — with the
  // dialog open, the default role query cannot see the readout at all.
  fireEvent.click(screen.getByRole("button", { name: "Read", hidden: true }));
}

// The dialog gates its OWN exits (Escape / backdrop / × / Cancel). A reload, a link click or a
// rail row switch is none of those, so the open draft has to reach the settings registry too.
describe("SocialLinksSection reports its unsaved dialog draft to the settings registry", () => {
  function renderInRegistry() {
    const qc = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    return render(
      <QueryClientProvider client={qc}>
        <SettingsDirtyProvider>
          <DirtyReadout />
          <SocialLinksSection links={[GITHUB]} isLoading={false} grants={[]} hidePrivacy hideSectionTitle />
        </SettingsDirtyProvider>
      </QueryClientProvider>,
    );
  }

  it("stays clean with no dialog open", () => {
    renderInRegistry();
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });

  // The false-positive that matters here: the Save gate's own `dirty` is unconditionally true in
  // add mode, so reporting THAT would nag on every Add dialog the user opens and thinks better of.
  it("stays clean for an Add dialog opened and left untouched", () => {
    renderInRegistry();
    openAdd();
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });

  it("reports dirty for a half-filled Add dialog", () => {
    renderInRegistry();
    openAdd();
    fireEvent.change(urlField(), { target: { value: "https://x.test/me" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("reports dirty once a loaded row is edited", () => {
    renderInRegistry();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.test/someone-else" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("withdraws the report once the dialog is discarded away", () => {
    renderInRegistry();
    openEdit();
    fireEvent.change(urlField(), { target: { value: "https://github.test/someone-else" } });
    fireEvent.keyDown(urlField(), { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Discard", hidden: true }));
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });
});
