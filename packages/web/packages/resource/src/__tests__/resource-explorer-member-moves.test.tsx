/// <reference types="@testing-library/jest-dom/vitest" />
//
// `memberMoves`: a group that was split or retired leaves addresses behind, and each one redirects
// (replace, not push) to where its member lives now. The ecosystems feature retired its
// Authentication group this way — Storage Access Tokens went to Storage, Settings to Users.
import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";
import { render, cleanup } from "@testing-library/react";
import { ResourceExplorer, type ResourceTopic } from "../resource-explorer";

const replace = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace, prefetch: vi.fn() }),
}));

beforeEach(() => replace.mockClear());
afterEach(cleanup);

interface Row {
  id: string;
  name: string;
}

const TOPICS: ResourceTopic[] = [
  { id: "storage", label: "Storage", icon: null, render: () => <div>storage pane</div> },
  { id: "invitations", label: "Users", icon: null, render: () => <div>users pane</div> },
];

const MOVES = {
  authentication: { tokens: "storage", auth: "invitations", legacy: null },
};

function open(activeTopic: string, activeLeafId?: string, activeMemberEntityId?: string) {
  render(
    <ResourceExplorer<Row>
      activeId="p1"
      activeTopic={activeTopic}
      activeLeafId={activeLeafId}
      activeMemberEntityId={activeMemberEntityId}
      basePath="/home"
      items={[{ id: "p1", name: "Project One" }]}
      getId={(i) => i.id}
      getLabel={(i) => i.name}
      nameSuffix="Project"
      topics={TOPICS}
      memberMoves={MOVES}
      rail={{ title: "All", help: "help", emptyLabel: "none" }}
    />,
  );
}

describe("ResourceExplorer memberMoves", () => {
  it("sends a moved member to its new group, carrying its inner entity", () => {
    open("authentication", "tokens", "tok_1");
    expect(replace).toHaveBeenCalledWith("/home/p1/storage/tokens/tok_1", { scroll: false });
  });

  it("sends a member that became a topic of its own to the top level", () => {
    open("authentication", "legacy");
    expect(replace).toHaveBeenCalledWith("/home/p1/legacy", { scroll: false });
  });

  it("sends the retired group itself, named with no member, to the resource", () => {
    open("authentication");
    expect(replace).toHaveBeenCalledWith("/home/p1", { scroll: false });
  });

  it("leaves a current address alone", () => {
    open("storage", "buckets");
    expect(replace).not.toHaveBeenCalled();
  });
});
