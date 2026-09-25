"use client";

import { useState } from "react";
import type { TopicDetailItem, TopicLevel, TopicListSearch } from "@agenticdevelopertoolkit/ui/blocks";

// ONE shared stand-in for the real rail (`TopicRail` in `@agenticdevelopertoolkit/ui`'s
// `topic-detail.tsx`), used by every feature package's component tests that render a rail HOST
// harness rather than mount the real one. Before this file, five suites
// (teams/notebook/research/projects' — and DocsCorpus's — feature tests) each hand-rolled a
// near-identical copy, and the copies had already drifted: one dropped `emptyLabel` entirely,
// another called `l.search.onQueryChange(...)` without the `?.` that the real field's type
// requires (`TopicListSearch.onQueryChange` is optional — a level that lets the rail own its own
// filtering, per `search: {}`, passes no `onQueryChange` at all) (Mike, 2026-09-25).
//
// This is a STAND-IN, not a port: it renders enough of a published `TopicLevel` for a test to
// drive (the rows, the toolbar's `+`/search/titleActions, the empty label, the busy spinner) but
// does not attempt the real rail's layout, collapse behavior, or hover-dwell timing — those are
// `topic-detail.tsx`'s own business and are pinned in its own suite
// (`topic-rail-toolbar.test.tsx` for the toolbar's `+`-then-search-then-titleActions order, which
// this stand-in mirrors so a test asserting order here is pinning the REAL rail's order, not an
// arbitrary one this file chose).
export interface RailStandInProps {
  /** The merged, published levels a rail host hands its rail — exactly what a real
   *  `RailHostRegistry` consumer receives. */
  levels: TopicLevel[];
  /** Render `<h3>{level.title}</h3>` above each level. Off by default: most suites never assert
   *  on it, and turning it on unconditionally risks a level's title colliding with an unrelated
   *  row label elsewhere on the same page. NotebookPane.test.tsx and DocsCorpus.test.tsx pass
   *  `true` — their harnesses always have. */
  showTitle?: boolean;
}

/** One level's toolbar search field. Its own component (not inlined in the `.map` below) because
 *  it owns local state — `useState` cannot live inside a loop body, and every level with a
 *  `search` needs its OWN fallback query, not one shared across levels.
 *
 *  `search.query === undefined` is the real rail's "I own my own filtering" mode (`search: {}}`,
 *  documented on `TopicListSearch`): the field must still be usable in that mode, so it falls
 *  back to locally-held state rather than rendering an uncontrolled-forever empty input. When
 *  `query` IS passed, the host owns it and this field is purely controlled — mirroring exactly
 *  what a level publishing `search: { query, onQueryChange }` is telling the real rail to do. */
function ToolbarSearch({ search }: { search: TopicListSearch }) {
  const [localQuery, setLocalQuery] = useState("");
  const controlled = search.query !== undefined;
  const query = controlled ? search.query! : localQuery;
  return (
    <input
      type="search"
      aria-label={search.placeholder}
      value={query}
      onChange={(e) => {
        const next = e.target.value;
        if (!controlled) setLocalQuery(next);
        search.onQueryChange?.(next);
      }}
    />
  );
}

/** One level's rows. Its own component only so `TopicDetailItem`'s optional `disabled` has
 *  somewhere obvious to read from — NotebookPane.test.tsx is the one suite whose notes can be
 *  disabled, and every other caller's rows simply never set it. */
function LevelRows({ level }: { level: TopicLevel }) {
  return (
    <ul>
      {level.items.map((item: TopicDetailItem) => (
        <li key={item.id}>
          <button
            type="button"
            disabled={item.disabled}
            onClick={() => level.onSelect(item.id)}
            onPointerEnter={() => level.onPrefetch?.(item.id)}
          >
            {item.label}
          </button>
        </li>
      ))}
    </ul>
  );
}

/**
 * Renders every published rail level the way a hub workspace shell's rail would: the rows, the
 * empty label when a level has zero items (G32: a level's `emptyLabel` must be visible for a test
 * to tell "still loading" from "loaded and empty" from "loaded and matches nothing"), the busy
 * spinner stand-in, and each level's own TOOLBAR — the `+` (`onNew`/`newLabel`), then the search
 * field, then `titleActions` — in that order because that is the REAL rail's order
 * (`topic-detail.tsx`'s list toolbar draws `+` first, then the magnifier, then trailing
 * `titleActions`); a test that wants to pin toolbar ORDER should pin it against the real rail's
 * own suite, not against this stand-in.
 *
 * Each level's toolbar is scoped inside `data-testid={\`toolbar-${level.id}\`}` so a test can
 * `within()` it rather than trust that nothing else on the page could satisfy an unscoped query —
 * mirroring the real rail's own `data-htd-toolbar`.
 */
export function RailStandIn({ levels, showTitle = false }: RailStandInProps) {
  return (
    <div>
      {levels.map((level) => (
        <div key={level.id}>
          {showTitle && <h3>{level.title}</h3>}
          {level.busy && <span data-testid={`busy-${level.id}`} />}
          {/* Wiring-level stand-in for the real rail's icon column: not rendering one is the
           *  observable effect of `hideItemIcons`, which nothing else here reads. Inert for every
           *  suite that never queries this testid. */}
          <span data-testid={`hide-item-icons-${level.id}`}>
            {String(Boolean(level.hideItemIcons))}
          </span>
          <div data-testid={`toolbar-${level.id}`}>
            {level.onNew ? (
              <button type="button" onClick={() => level.onNew?.()}>
                {level.newLabel}
              </button>
            ) : null}
            {level.search ? <ToolbarSearch search={level.search} /> : null}
            {level.titleActions}
          </div>
          {level.items.length === 0 ? <p>{level.emptyLabel}</p> : null}
          <LevelRows level={level} />
        </div>
      ))}
    </div>
  );
}
