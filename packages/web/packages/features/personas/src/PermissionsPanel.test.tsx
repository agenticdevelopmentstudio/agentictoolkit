// @vitest-environment jsdom
//
// Component test for PermissionsPanel — the persona editor's "where / as-what may this persona
// use its tools, plus the human decision queue" facet. Ported from the old workspace
// ApprovalsFeature.test.tsx (the approve/reject queue) and AgentToolsPanel.test.tsx (the may_act
// switch tests), combined and adapted to the personaId-prop shape. This package's vitest config is
// node-only, so this file opts into jsdom via the docblock above and drives React with
// @testing-library/react. Only the api-client module boundary is mocked (vi.mock), so the
// panel's may_act toggle wiring, the server-scoped (`?personaId=`) approvals request, and the
// optimistic row removal are exercised, not the transport.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  render,
  screen,
  fireEvent,
  waitFor,
  cleanup,
  within,
  act,
} from "@testing-library/react";

vi.mock("@agentic-toolkit/data/personas", () => ({
  personaApprovalsApi: { list: vi.fn(), approve: vi.fn(), reject: vi.fn() },
  personaMayActApi: { list: vi.fn(), grant: vi.fn(), revoke: vi.fn() },
}));

import { PermissionsPanel } from "./PermissionsPanel";
import {
  personaApprovalsApi,
  personaMayActApi,
  type Approval,
  type MayActKind,
} from "@agentic-toolkit/data/personas";

const list = vi.mocked(personaApprovalsApi.list);
const approve = vi.mocked(personaApprovalsApi.approve);
const reject = vi.mocked(personaApprovalsApi.reject);
const mayActList = vi.mocked(personaMayActApi.list);
const grant = vi.mocked(personaMayActApi.grant);
const revoke = vi.mocked(personaMayActApi.revoke);

// The panel reads id/toolName/subjectKind/personaId/args/createdAt off each row — a minimal
// literal stands in for the full OpenAPI-derived Approval shape. Both belong to persona p1
// (the default personaId used by most tests below).
const A1 = {
  id: "ap1",
  toolName: "sendEmail",
  subjectKind: "user",
  personaId: "p1",
  args: { to: "x@example.com" },
  createdAt: "2026-07-03T00:00:00Z",
} as unknown as Approval;
const A2 = {
  id: "ap2",
  toolName: "deleteFile",
  subjectKind: "user",
  personaId: "p1",
  args: { path: "/tmp/y" },
  createdAt: "2026-07-03T00:00:00Z",
} as unknown as Approval;
beforeEach(() => {
  vi.clearAllMocks();
  list.mockResolvedValue([]);
  // Default: only the seeded 'self' kind — both may-act switches are off.
  mayActList.mockResolvedValue(["self"]);
});

// This package's vitest config has no global afterEach — tear down each render explicitly.
afterEach(cleanup);

/** The Approve button inside a specific queue row (addressed by its decide group). */
const approveBtn = (toolName: string) =>
  within(screen.getByRole("group", { name: `decide ${toolName}` })).getByRole("button", {
    name: /approve/i,
  });

/** The Reject button inside a specific queue row (addressed by its decide group). */
const rejectBtn = (toolName: string) =>
  within(screen.getByRole("group", { name: `decide ${toolName}` })).getByRole("button", {
    name: /reject/i,
  });

// base-ui reflects a disabled control via the native `disabled` attribute (and/or
// aria-disabled); accept either so the assertion isn't coupled to one representation.
const isDisabled = (el: HTMLElement) =>
  el.hasAttribute("disabled") || el.getAttribute("aria-disabled") === "true";

const mayActSwitch = () => screen.getByRole("switch", { name: "May act for users" });
const mayActTeamSwitch = () => screen.getByRole("switch", { name: "May act via teams" });

describe("PermissionsPanel — decision queue", () => {
  it("requests the pending queue scoped to this persona server-side (#14)", async () => {
    list.mockResolvedValueOnce([structuredClone(A1)]);
    render(<PermissionsPanel personaId="p1" />);

    await screen.findByText("sendEmail");
    // The persona id is passed straight through to the API — the backend, not the panel, is
    // what narrows the decidable queue down to this persona's rows.
    expect(list).toHaveBeenCalledWith("pending", "p1");
  });

  it("approves an action, drops it from the queue, and reloads (happy path)", async () => {
    list.mockResolvedValueOnce([structuredClone(A1), structuredClone(A2)]); // initial load
    approve.mockResolvedValueOnce(structuredClone(A1));
    list.mockResolvedValueOnce([structuredClone(A2)]); // reload after approve

    render(<PermissionsPanel personaId="p1" />);
    await screen.findByText("sendEmail");

    fireEvent.click(approveBtn("sendEmail"));

    await waitFor(() => expect(approve).toHaveBeenCalledWith("ap1"));
    // The decided row is gone; the sibling row stays.
    await waitFor(() => expect(screen.queryByText("sendEmail")).toBeNull());
    expect(screen.getByText("deleteFile")).not.toBeNull();
  });

  it("rejects an action, drops it from the queue, and reloads", async () => {
    list.mockResolvedValueOnce([structuredClone(A1), structuredClone(A2)]); // initial load
    reject.mockResolvedValueOnce(structuredClone(A1));
    list.mockResolvedValueOnce([structuredClone(A2)]); // reload after reject

    render(<PermissionsPanel personaId="p1" />);
    await screen.findByText("sendEmail");

    fireEvent.click(rejectBtn("sendEmail"));

    await waitFor(() => expect(reject).toHaveBeenCalledWith("ap1"));
    // The rejected row is gone (no execution); the sibling row stays.
    await waitFor(() => expect(screen.queryByText("sendEmail")).toBeNull());
    expect(screen.getByText("deleteFile")).not.toBeNull();
  });

  it("removes the decided row even when the post-decision reload throws", async () => {
    list.mockResolvedValueOnce([structuredClone(A1), structuredClone(A2)]); // initial load
    approve.mockResolvedValueOnce(structuredClone(A1));
    list.mockRejectedValueOnce(new Error("reload failed")); // reload after approve throws

    render(<PermissionsPanel personaId="p1" />);
    await screen.findByText("sendEmail");

    fireEvent.click(approveBtn("sendEmail"));

    await waitFor(() => expect(approve).toHaveBeenCalledWith("ap1"));
    // Even though the reload rejected, the decided row was optimistically removed, so it
    // cannot be re-decided from stale UI; the un-decided sibling row remains.
    await waitFor(() => expect(screen.queryByText("sendEmail")).toBeNull());
    expect(screen.getByText("deleteFile")).not.toBeNull();
    // busy cleared in the finally — the remaining row's Approve is enabled again.
    await waitFor(() => expect(approveBtn("deleteFile").hasAttribute("disabled")).toBe(false));
  });

  it("keeps the row (and surfaces the error) when the decision call itself throws", async () => {
    list.mockResolvedValueOnce([structuredClone(A1)]); // initial load
    approve.mockRejectedValueOnce(new Error("approve boom"));

    render(<PermissionsPanel personaId="p1" />);
    await screen.findByText("sendEmail");

    fireEvent.click(approveBtn("sendEmail"));

    await waitFor(() => expect(approve).toHaveBeenCalledWith("ap1"));
    // The decision threw, so the row must NOT be removed — it stays to be retried…
    expect(screen.getByText("sendEmail")).not.toBeNull();
    // …the error surfaces, and busy is cleared (Approve re-enabled).
    expect(await screen.findByText("approve boom")).not.toBeNull();
    await waitFor(() => expect(approveBtn("sendEmail").hasAttribute("disabled")).toBe(false));
  });

  it("an in-flight decision on one row does not disable an independent row's buttons", async () => {
    list.mockResolvedValueOnce([structuredClone(A1), structuredClone(A2)]); // initial load
    let resolveApprove!: () => void;
    approve.mockImplementation(
      () =>
        new Promise<Approval>((res) => {
          resolveApprove = () => res(structuredClone(A1));
        }),
    );

    render(<PermissionsPanel personaId="p1" />);
    await screen.findByText("sendEmail");

    // Address the Approve button by POSITION within its row's group rather than by its
    // name, since the label itself flips to "Approving…" once busy.
    const approveBtnIn = (toolName: string) =>
      within(screen.getByRole("group", { name: `decide ${toolName}` })).getAllByRole(
        "button",
      )[0]!;

    fireEvent.click(approveBtnIn("sendEmail")); // ap1's decision is now in flight

    // ap1's own Approve is disabled while its decision is in flight…
    await waitFor(() => expect(approveBtnIn("sendEmail").hasAttribute("disabled")).toBe(true));
    // …but ap2's row is untouched — a busy decision on one row must never serialize the
    // whole queue (a per-row busy set, not one shared id).
    expect(approveBtnIn("deleteFile").hasAttribute("disabled")).toBe(false);

    list.mockResolvedValueOnce([structuredClone(A2)]); // reload after approve
    await act(async () => {
      resolveApprove();
    });
    await waitFor(() => expect(screen.queryByText("sendEmail")).toBeNull());
  });

  // The panel used to draw its own API affordance beside the "Permissions" title (FieldGroup
  // `trailing`); that button now lives once, in PersonaEditor's leafHeader (its ButtonBar `api`),
  // so this body must never render one of its own.
  it("renders no API affordance of its own — that lives in the persona editor's header", async () => {
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));
    expect(screen.queryByRole("button", { name: /API/ })).toBeNull();
  });
});

describe("PermissionsPanel — may_act switches", () => {
  it("reflects a may-act grant of 'user' — switch on", async () => {
    mayActList.mockResolvedValueOnce(["self", "user"]);
    render(<PermissionsPanel personaId="p1" />);
    expect(mayActList).toHaveBeenCalledWith("p1");
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("true");
  });

  it("leaves the switch off when 'user' is not granted", async () => {
    mayActList.mockResolvedValueOnce(["self"]);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("false");
  });

  it("toggling the switch on grants 'user'", async () => {
    mayActList.mockResolvedValueOnce(["self"]);
    grant.mockResolvedValueOnce(["self", "user"]);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));

    fireEvent.click(mayActSwitch());

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "user"));
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("true");
  });

  it("toggling the switch off revokes 'user'", async () => {
    mayActList.mockResolvedValueOnce(["self", "user"]);
    revoke.mockResolvedValueOnce(undefined);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("true");

    fireEvent.click(mayActSwitch());

    await waitFor(() => expect(revoke).toHaveBeenCalledWith("p1", "user"));
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("false");
  });

  it("reverts the switch when the grant rejects", async () => {
    mayActList.mockResolvedValueOnce(["self"]);
    grant.mockRejectedValueOnce(new Error("nope"));
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));

    fireEvent.click(mayActSwitch());
    // Optimistic flip on, then revert once the rejected grant settles.
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("true");

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "user"));
    await waitFor(() => expect(mayActSwitch().getAttribute("aria-checked")).toBe("false"));
  });

  it("reflects a may-act grant of 'team' — switch on", async () => {
    mayActList.mockResolvedValueOnce(["self", "team"]);
    render(<PermissionsPanel personaId="p1" />);
    expect(mayActList).toHaveBeenCalledWith("p1");
    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");
  });

  it("reads both switches off the single may-act list() call", async () => {
    mayActList.mockResolvedValueOnce(["self", "user", "team"]);
    render(<PermissionsPanel personaId="p1" />);
    // One list() request feeds BOTH switches — no second request per switch.
    await waitFor(() => expect(isDisabled(mayActSwitch())).toBe(false));
    expect(mayActList).toHaveBeenCalledTimes(1);
    expect(mayActSwitch().getAttribute("aria-checked")).toBe("true");
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");
  });

  it("leaves the team switch off when 'team' is not granted", async () => {
    mayActList.mockResolvedValueOnce(["self", "user"]);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("false");
  });

  it("toggling the team switch on grants 'team'", async () => {
    mayActList.mockResolvedValueOnce(["self"]);
    grant.mockResolvedValueOnce(["self", "team"]);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));

    fireEvent.click(mayActTeamSwitch());

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "team"));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");
  });

  it("toggling the team switch off revokes 'team'", async () => {
    mayActList.mockResolvedValueOnce(["self", "team"]);
    revoke.mockResolvedValueOnce(undefined);
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");

    fireEvent.click(mayActTeamSwitch());

    await waitFor(() => expect(revoke).toHaveBeenCalledWith("p1", "team"));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("false");
  });

  it("reverts the team switch when the grant rejects", async () => {
    mayActList.mockResolvedValueOnce(["self"]);
    grant.mockRejectedValueOnce(new Error("nope"));
    render(<PermissionsPanel personaId="p1" />);
    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));

    fireEvent.click(mayActTeamSwitch());
    // Optimistic flip on, then revert once the rejected grant settles.
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");

    await waitFor(() => expect(grant).toHaveBeenCalledWith("p1", "team"));
    await waitFor(() => expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("false"));
  });
});

describe("PermissionsPanel — persona switch (rerender with a new personaId)", () => {
  it("drops a stale may-act response so the newly-selected persona's state stands", async () => {
    let resolveP1!: (v: MayActKind[]) => void;
    const pendingP1 = new Promise<MayActKind[]>((resolve) => {
      resolveP1 = resolve;
    });
    mayActList.mockImplementation((id: string) =>
      id === "p1" ? pendingP1 : Promise.resolve<MayActKind[]>(["self", "team"]),
    );

    const { rerender } = render(<PermissionsPanel personaId="p1" />); // list(p1): still pending
    rerender(<PermissionsPanel personaId="p2" />); // list(p2): resolves now

    await waitFor(() => expect(isDisabled(mayActTeamSwitch())).toBe(false));
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");

    // The slow p1 response lands LAST; the stale guard must drop it, not overwrite p2's state.
    await act(async () => {
      resolveP1(["self"]);
    });
    expect(mayActTeamSwitch().getAttribute("aria-checked")).toBe("true");
  });
});
