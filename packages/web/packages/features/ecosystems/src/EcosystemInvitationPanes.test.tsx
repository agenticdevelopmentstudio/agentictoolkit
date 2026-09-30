// @vitest-environment jsdom
//
// Component test for the three ecosystem-owner invitation panes (Requests, Pending users,
// Invites). Each pane used to leave its API affordance to whatever the caller drew — none did —
// so nothing was there. Now each draws its OWN FeatureTitle header (adh-ui's shared
// ListWithDetailsPane block, underneath, never draws a title of its own — see
// adh-ui/src/blocks/invitation-panes.tsx), carrying the pane's title on the left and, on the
// right, the API slot then help. What this file pins: the header renders ABOVE the scrollable
// body (never a button inside it), and each pane's `api` targets its own endpoint.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";

vi.mock("@agentic-toolkit/auth", () => ({
  useAuth: () => ({ user: { email: "owner@example.com" } }),
}));

const {
  useEcoInvitationRequests,
  useEcoPendingUsers,
  useEcoInvites,
  useEcoDeleteRow,
  useEcoSendInvitations,
  useEcoAddPendingUsers,
  useEcoRowNotes,
  useEcoRowHistory,
  useEcoSaveNotes,
} = vi.hoisted(() => ({
  useEcoInvitationRequests: vi.fn(),
  useEcoPendingUsers: vi.fn(),
  useEcoInvites: vi.fn(),
  useEcoDeleteRow: vi.fn(),
  useEcoSendInvitations: vi.fn(),
  useEcoAddPendingUsers: vi.fn(),
  useEcoRowNotes: vi.fn(),
  useEcoRowHistory: vi.fn(),
  useEcoSaveNotes: vi.fn(),
}));

vi.mock("@agentic-toolkit/data/ecosystems", () => ({
  useEcoInvitationRequests,
  useEcoPendingUsers,
  useEcoInvites,
  useEcoDeleteRow,
  useEcoSendInvitations,
  useEcoAddPendingUsers,
  useEcoRowNotes,
  useEcoRowHistory,
  useEcoSaveNotes,
}));

import { EcoRequestsPane, EcoPendingUsersPane, EcoInvitesPane } from "./EcosystemInvitationPanes";

const EMPTY_QUERY = { data: [], isPending: false, isError: false };
const IDLE_MUTATION = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false };

beforeEach(() => {
  vi.clearAllMocks();
  useEcoInvitationRequests.mockReturnValue(EMPTY_QUERY);
  useEcoPendingUsers.mockReturnValue(EMPTY_QUERY);
  useEcoInvites.mockReturnValue(EMPTY_QUERY);
  useEcoDeleteRow.mockReturnValue(IDLE_MUTATION);
  useEcoSendInvitations.mockReturnValue(IDLE_MUTATION);
  useEcoAddPendingUsers.mockReturnValue(IDLE_MUTATION);
  // AdminNotesModal calls these unconditionally (gated internally on `open`/`subjectId`, not on
  // whether the hook runs), so every pane needs them stubbed even with no row selected.
  useEcoRowNotes.mockReturnValue({ data: [], isPending: false });
  useEcoRowHistory.mockReturnValue({ data: [], isPending: false });
  useEcoSaveNotes.mockReturnValue(IDLE_MUTATION);
});

afterEach(cleanup);

/** The disabled fallback's accessible name (see resource/src/header-api-button.tsx) — what every
 *  pane's API slot renders here, since no `RecordAffordanceContext` host is provided. */
const API_BUTTON = () => screen.getByRole("button", { name: "API — This view has no API endpoint" });

describe("EcoRequestsPane", () => {
  it("draws its FeatureTitle header, with the API button, above the scrollable grid", () => {
    render(<EcoRequestsPane ecosystemRdid="eco-1" />);

    expect(screen.getByRole("heading", { name: "Requests" })).not.toBeNull();
    const api = API_BUTTON();
    const grid = screen.getByRole("grid", { name: "Invitation requests" });
    // Header precedes the scrollable body in document order.
    expect(api.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    // Exactly one API affordance on screen — never a second one drawn by the body.
    expect(screen.getAllByRole("button", { name: /API/ })).toHaveLength(1);
  });
});

describe("EcoPendingUsersPane", () => {
  it("draws its FeatureTitle header, with the API button, above the scrollable grid", () => {
    render(<EcoPendingUsersPane ecosystemRdid="eco-1" />);

    expect(screen.getByRole("heading", { name: "Pending users" })).not.toBeNull();
    const api = API_BUTTON();
    const grid = screen.getByRole("grid", { name: "Pending users" });
    expect(api.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getAllByRole("button", { name: /API/ })).toHaveLength(1);
  });
});

describe("EcoInvitesPane", () => {
  it("draws its FeatureTitle header, with the API button, above the scrollable grid", () => {
    render(<EcoInvitesPane ecosystemRdid="eco-1" />);

    expect(screen.getByRole("heading", { name: "Invites" })).not.toBeNull();
    const api = API_BUTTON();
    const grid = screen.getByRole("grid", { name: "Sent invites" });
    expect(api.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(screen.getAllByRole("button", { name: /API/ })).toHaveLength(1);
  });
});
