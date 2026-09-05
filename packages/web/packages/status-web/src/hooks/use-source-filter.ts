"use client";
import { useState } from "react";
import { ISSUE_SOURCES, type IssueSource } from "../lib/issue-sources";

/**
 * The source-set toggle state shared by every filtered pane (active problems,
 * recently resolved, activity). Starts with all sources selected; toggling one
 * adds/removes it. Extracted so the three panes can't drift in how they filter.
 */
export function useSourceFilter(): {
  sources: Set<IssueSource>;
  toggleSource: (s: IssueSource) => void;
} {
  const [sources, setSources] = useState<Set<IssueSource>>(() => new Set(ISSUE_SOURCES));
  const toggleSource = (s: IssueSource): void =>
    setSources((prev) => {
      const next = new Set(prev);
      if (next.has(s)) next.delete(s);
      else next.add(s);
      return next;
    });
  return { sources, toggleSource };
}
