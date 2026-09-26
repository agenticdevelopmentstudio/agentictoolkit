/// <reference types="@testing-library/jest-dom/vitest" />
//
// A topic row's `sublabel` reaches the rail. The ecosystems feature marks a feature that is still
// being provisioned with one ("Provisioning…"), so the Features list can show the row instead of
// hiding it — which only works if ResourceExplorer carries the field onto the row it draws.
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { ResourceExplorer, type ResourceTopic } from "../resource-explorer";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

afterEach(cleanup);

interface Row {
  id: string;
  name: string;
}

describe("ResourceExplorer topic sublabel", () => {
  it("draws a topic's sublabel on its rail row", () => {
    const topics: ResourceTopic[] = [
      { id: "notes", label: "Notes", icon: null, render: () => <div>notes pane</div> },
      {
        id: "games",
        label: "Games",
        icon: null,
        sublabel: "Provisioning…",
        render: () => <div>games pane</div>,
      },
    ];
    render(
      <ResourceExplorer<Row>
        activeId="p1"
        basePath="/home"
        items={[{ id: "p1", name: "Project One" }]}
        getId={(i) => i.id}
        getLabel={(i) => i.name}
        nameSuffix="Project"
        topics={topics}
        rail={{ title: "All", help: "help", emptyLabel: "none" }}
      />,
    );
    expect(screen.getByText("Games")).toBeInTheDocument();
    expect(screen.getByText("Provisioning…")).toBeInTheDocument();
  });
});
