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
  AddressesSection,
  addressBlockedReason,
  ADDRESS_LINE1_REQUIRED_MESSAGE,
} from "./AddressesSection";
import { createAddress, updateAddress, deleteAddress, type Address, type AddressWrite } from "@agentic-toolkit/data/profile";

// The section calls useMutation/useQueryClient directly (no wrapper hook to swap), so a
// real QueryClient context is required; only the three network functions are stubbed.
// `resolvePrivacyLevel`/`addressesKey` stay real — they are pure helpers.
vi.mock("@agentic-toolkit/data/profile", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@agentic-toolkit/data/profile")>();
  return {
    ...actual,
    createAddress: vi.fn(),
    updateAddress: vi.fn(),
    deleteAddress: vi.fn(),
  };
});

const createAddressMock = vi.mocked(createAddress);
const updateAddressMock = vi.mocked(updateAddress);
const deleteAddressMock = vi.mocked(deleteAddress);

// A stored row: every required field already filled, which is what makes the "no reason
// while pristine" assertions meaningful.
const HOME = {
  id: "addr_1",
  label: "Home",
  line1: "123 Main St",
  line2: "",
  city: "Austin",
  region: "TX",
  postalCode: "78701",
  country: "USA",
} as unknown as Address;

// The hub vitest config has no global afterEach; tear each render (+ its portalled
// dialog) down explicitly so it doesn't leak into the next test.
afterEach(() => {
  cleanup();
  createAddressMock.mockReset();
  updateAddressMock.mockReset();
  deleteAddressMock.mockReset();
});

function renderSection() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={qc}>
      <AddressesSection addresses={[HOME]} isLoading={false} grants={[]} hidePrivacy hideSectionTitle />
    </QueryClientProvider>,
  );
}

/** Edit is a BAR verb now, like admin's tables: tick the row, then press Edit. */
function openEdit() {
  fireEvent.click(screen.getByRole("checkbox", { name: "Select Home" }));
  fireEvent.click(screen.getByRole("button", { name: "Edit" }));
}

function openAdd() {
  fireEvent.click(screen.getByRole("button", { name: "Add address" }));
}

function saveButton() {
  return screen.getByRole("button", { name: /^(Save|Saving…)$/ }) as HTMLButtonElement;
}

/** The rendered "why Save is dark" line, or null when the view is silent. */
function reason(): string | null {
  return screen.queryByRole("status")?.textContent ?? null;
}

function line1() {
  return screen.getByPlaceholderText("123 Main St");
}

describe("addressBlockedReason", () => {
  it("names the missing required field when line 1 is blank", () => {
    expect(addressBlockedReason({ ...draftOfHome(), line1: "" })).toBe(
      ADDRESS_LINE1_REQUIRED_MESSAGE,
    );
  });

  it("treats a whitespace-only line 1 as blank — the write trims it away to nothing", () => {
    expect(addressBlockedReason({ ...draftOfHome(), line1: "   " })).toBe(
      ADDRESS_LINE1_REQUIRED_MESSAGE,
    );
  });

  it("is null once line 1 has content — every other field is optional", () => {
    expect(
      addressBlockedReason({
        label: "",
        line1: "1 Infinite Loop",
        line2: "",
        city: "",
        region: "",
        postalCode: "",
        country: "",
      }),
    ).toBeNull();
  });
});

function draftOfHome(): AddressWrite {
  return {
    label: HOME.label,
    line1: HOME.line1,
    line2: HOME.line2,
    city: HOME.city,
    region: HOME.region,
    postalCode: HOME.postalCode,
    country: HOME.country,
  };
}

describe("AddressesSection — editing a stored address", () => {
  it("opens with Save dark and says nothing: a loaded row is valid, and 'nothing changed yet' explains itself", () => {
    renderSection();
    openEdit();
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBeNull();
  });

  it("enables Save once a field actually differs from the loaded row", () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });
    expect(saveButton().disabled).toBe(false);
  });

  it("goes back to dark on an edit-and-revert — Save tracks the VALUE, not touched-ness", () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });
    expect(saveButton().disabled).toBe(false);
    fireEvent.change(line1(), { target: { value: "123 Main St" } });
    expect(saveButton().disabled).toBe(true);
  });

  it("stays dark when only surrounding whitespace was added — the write trims, so the record would not change", () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "  123 Main St  " } });
    expect(saveButton().disabled).toBe(true);
  });

  it("says WHY when the required field is emptied, instead of just greying out", () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "" } });
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBe(ADDRESS_LINE1_REQUIRED_MESSAGE);
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
    expect(updateAddressMock).not.toHaveBeenCalled();
  });

  it("writes once for one edit — a second submit during the in-flight write is ignored", async () => {
    updateAddressMock.mockReturnValue(new Promise(() => {})); // never settles
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });
    const form = saveButton().closest("form")!;
    fireEvent.submit(form);
    await waitFor(() => expect(updateAddressMock).toHaveBeenCalledTimes(1));
    await act(async () => {
      fireEvent.submit(form);
    });
    expect(updateAddressMock).toHaveBeenCalledTimes(1);
  });

  it("sends the trimmed edit under the row's id", async () => {
    updateAddressMock.mockResolvedValue(HOME);
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "  456 Oak Ave  " } });
    fireEvent.submit(saveButton().closest("form")!);
    await waitFor(() => expect(updateAddressMock).toHaveBeenCalledTimes(1));
    expect(updateAddressMock.mock.calls[0]![0]).toBe("addr_1");
    expect(updateAddressMock.mock.calls[0]![1]).toEqual({
      ...draftOfHome(),
      line1: "456 Oak Ave",
    });
  });
});

describe("AddressesSection — adding an address", () => {
  it("opens dark and says which field it is waiting on — an empty form has no baseline to explain itself", () => {
    renderSection();
    openAdd();
    expect(saveButton().disabled).toBe(true);
    expect(reason()).toBe(ADDRESS_LINE1_REQUIRED_MESSAGE);
  });

  it("enables Save and falls silent once the required field is filled", () => {
    renderSection();
    openAdd();
    fireEvent.change(line1(), { target: { value: "1 Infinite Loop" } });
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
    expect(createAddressMock).not.toHaveBeenCalled();
  });
});

// The dialog's `onOpenChange` is how Escape, a backdrop click and the × ALL reach the close
// path, so firing Escape exercises that whole path rather than a bespoke one.
describe("AddressesSection dialog — Escape on a dirty draft asks before discarding", () => {
  function line1() {
    return screen.getByPlaceholderText("123 Main St") as HTMLInputElement;
  }

  it("does not close on Escape while dirty; Discard then closes", async () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });

    fireEvent.keyDown(line1(), { key: "Escape" });
    expect(screen.queryByText("Edit address")).not.toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Discard" }));
    await waitFor(() => expect(screen.queryByText("Edit address")).toBeNull());
  });

  it("Stay keeps the dialog open with the edit intact", async () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });

    fireEvent.keyDown(line1(), { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Stay" }));
    await waitFor(() => expect(screen.queryByRole("button", { name: "Discard" })).toBeNull());
    expect(line1().value).toBe("456 Oak Ave");
  });

  it("closes immediately on Escape when the loaded address is untouched — no alert", async () => {
    renderSection();
    openEdit();
    fireEvent.keyDown(line1(), { key: "Escape" });
    await waitFor(() => expect(screen.queryByText("Edit address")).toBeNull());
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });

  // The false-positive test, and the reason the close gate CANNOT reuse the Save gate's
  // `dirty`: that one is unconditionally true in add mode (an add has no loaded baseline, so
  // filling the required field IS the change). Reusing it would nag on every abandoned Add.
  it("closes immediately on Escape from an untouched Add dialog — a blank draft is not unsaved work", async () => {
    renderSection();
    openAdd();
    fireEvent.keyDown(line1(), { key: "Escape" });
    await waitFor(() => expect(screen.queryByText("Add address")).toBeNull());
    expect(screen.queryByRole("button", { name: "Discard" })).toBeNull();
  });

  it("a half-filled Add dialog IS unsaved work — Escape asks", () => {
    renderSection();
    openAdd();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });
    fireEvent.keyDown(line1(), { key: "Escape" });
    expect(screen.queryByText("Add address")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy();
  });

  it("Cancel is gated the same way as Escape — the two are one close path", () => {
    renderSection();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Oak Ave" } });
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(screen.queryByText("Edit address")).not.toBeNull();
    expect(screen.getByRole("button", { name: "Discard" })).toBeTruthy();
  });
});

// Delete is a BAR verb over the whole selection: one confirm that names every ticked row, and
// one delete call per row — not a trash can that only ever reaches the row it sits on.
describe("AddressesSection — deleting from the bar", () => {
  const WORK = { ...HOME, id: "addr_2", label: "Work", line1: "1 Office Pk" } as unknown as Address;

  it("confirms every ticked address by name and deletes each of them", async () => {
    deleteAddressMock.mockResolvedValue(undefined as never);
    const qc = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    render(
      <QueryClientProvider client={qc}>
        <AddressesSection addresses={[HOME, WORK]} isLoading={false} grants={[]} hidePrivacy hideSectionTitle />
      </QueryClientProvider>,
    );
    fireEvent.click(screen.getByRole("checkbox", { name: "Select Home" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "Select Work" }));
    // Edit opens ONE record; with two ticked it must not guess which.
    expect((screen.getByRole("button", { name: "Edit" }) as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(screen.getByText("Remove 2 addresses?")).toBeTruthy();
    expect(screen.getByText("Remove Home; Work from your card?")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() => expect(deleteAddressMock).toHaveBeenCalledTimes(2));
    expect(deleteAddressMock.mock.calls.map((c) => c[0]).sort()).toEqual(["addr_1", "addr_2"]);
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
describe("AddressesSection reports its unsaved dialog draft to the settings registry", () => {
  function renderInRegistry() {
    const qc = new QueryClient({
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    return render(
      <QueryClientProvider client={qc}>
        <SettingsDirtyProvider>
          <DirtyReadout />
          <AddressesSection addresses={[HOME]} isLoading={false} grants={[]} hidePrivacy hideSectionTitle />
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
    fireEvent.change(line1(), { target: { value: "1 Infinite Loop" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("reports dirty once a loaded row is edited", () => {
    renderInRegistry();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Elm St" } });
    readRegistry();
    expect(screen.getByText("registry sees dirty")).toBeTruthy();
  });

  it("withdraws the report once the dialog is discarded away", () => {
    renderInRegistry();
    openEdit();
    fireEvent.change(line1(), { target: { value: "456 Elm St" } });
    fireEvent.keyDown(line1(), { key: "Escape" });
    fireEvent.click(screen.getByRole("button", { name: "Discard", hidden: true }));
    readRegistry();
    expect(screen.getByText("registry sees clean")).toBeTruthy();
  });
});
