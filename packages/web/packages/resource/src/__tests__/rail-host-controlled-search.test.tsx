/// <reference types="@testing-library/jest-dom/vitest" />
//
// A rail's CONTROLLED search, typed one key at a time through the real host and the real rail.
// The pop-over field's `value` is the REGISTERED level's `search.query` — the host renders the
// level objects it stored, not the publisher's latest render — and the publish key used to leave
// `search` out, because it is an object and only plain fields were keyed. So a keystroke set the
// publisher's state, the key did not move, nothing re-registered, and React put the field back to
// the stale committed value: fast typing in Research kept only the last key, "abc" became "ac" in
// the notebook, and a space could never be typed into the ResourceExplorer filter at all.
//
// Each keystroke appends to what the field shows NOW, as a user's does, and the value is checked
// after every key: a revert in the middle is otherwise papered over by the next `change`.
import { useState } from "react";
import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup, within } from "@testing-library/react";
import type { TopicLevel } from "@agenticdevelopertoolkit/ui/blocks";
import { StandaloneRailHost } from "../standalone-rail-host";
import { StackLevels, useStackLevel } from "../rail-host";
import { ResourceExplorer, type ResourceTopic } from "../resource-explorer";

// ResourceExplorer calls next/navigation's useRouter unconditionally; its routing isn't under test
// here — mirrors resource-explorer.toolbar.test.tsx.
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
}));

// This package's vitest config has no global afterEach, so register cleanup explicitly.
afterEach(cleanup);

/** A list whose query lives in the publisher's state and reaches the rail CONTROLLED — the shape
 *  Research's documents and the notebook's notes use. Nothing else on the level moves with the
 *  query, so the query itself is the only thing that can make the level re-register. */
function notesLevel(query: string, onQueryChange: (q: string) => void): TopicLevel {
  return {
    id: "notes",
    title: "Notes",
    items: [
      { id: "n1", label: "Alpha note" },
      { id: "n2", label: "Beta note" },
    ],
    selectedId: null,
    onSelect: () => {},
    onClear: () => {},
    emptyLabel: "No notes yet.",
    search: { query, onQueryChange, placeholder: "Search notes" },
  };
}

function StackPublisher() {
  const [query, setQuery] = useState("");
  return (
    <StackLevels levels={[notesLevel(query, setQuery)]}>
      <div>pane</div>
    </StackLevels>
  );
}

function HookPublisher() {
  const [query, setQuery] = useState("");
  useStackLevel(notesLevel(query, setQuery));
  return <div>pane</div>;
}

/** Open the rail's pop-over search from its toolbar, then type `text` into it one key at a time,
 *  asserting what the field shows after every key. */
function typeIntoRailSearch(name: string, text: string) {
  const toolbar = document.querySelector("[data-htd-toolbar]") as HTMLElement;
  fireEvent.click(within(toolbar).getByRole("button", { name }));
  let typed = "";
  for (const key of text) {
    typed += key;
    const field = screen.getByRole("searchbox", { name }) as HTMLInputElement;
    fireEvent.change(field, { target: { value: field.value + key } });
    expect(screen.getByRole("searchbox", { name }), `after typing "${typed}"`).toHaveValue(typed);
  }
}

describe("a rail's controlled search, typed through the host", () => {
  it("keeps every keystroke, spaces included, from a StackLevels publisher", () => {
    render(
      <StandaloneRailHost>
        <StackPublisher />
      </StandaloneRailHost>,
    );
    typeIntoRailSearch("Search notes", "abc de");
  });

  it("keeps every keystroke, spaces included, from a useStackLevel publisher", () => {
    render(
      <StandaloneRailHost>
        <HookPublisher />
      </StandaloneRailHost>,
    );
    typeIntoRailSearch("Search notes", "abc de");
  });

  // The explorer's empty label used to quote the TRIMMED filter, so every other key happened to
  // move a plain field and re-register the level; a space moved nothing, and was the one key it
  // lost. The label quotes nothing now (a no-match is the rail's own to name), which leaves the
  // query itself as the only field a keystroke moves.
  it("lets ResourceExplorer's filter take a space, and narrows on the whole phrase", () => {
    const NO_TOPICS: ResourceTopic[] = [];
    render(
      <ResourceExplorer<{ id: string; label: string }>
        promoteTopics={false}
        basePath="/home"
        items={[
          { id: "a", label: "Alpha One" },
          { id: "b", label: "Alpha Two" },
        ]}
        getId={(i) => i.id}
        getLabel={(i) => i.label}
        nameSuffix="Project"
        topics={NO_TOPICS}
        rail={{ title: "All", help: "help", emptyLabel: "None yet." }}
      />,
    );
    typeIntoRailSearch("Filter all", "alpha t");
    expect(screen.getByText("Alpha Two")).toBeInTheDocument();
    expect(screen.queryByText("Alpha One")).toBeNull();
  });
});
