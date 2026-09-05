import type React from "react";

/** Shared style for the three-pane body panels in DetailPanel and GlobalPanel. */
export const paneStyle: React.CSSProperties = {
  padding: "10px 16px",
  borderRight: "1px solid var(--color-apt-border)",
  overflow: "hidden",
  display: "flex",
  flexDirection: "column",
  gap: 8,
};

// The pane heading treatment moved to the shared display micro-heading:
// use `sectionLabelClass` from @agentic-toolkit/ui/components/section-label
// (e.g. <h4 className={sectionLabelClass}>) instead of a local style.

/** Shared style for incident rows. */
export const incRowStyle: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: 8,
  padding: "4px 0",
  fontFamily: "var(--mono,ui-monospace,monospace)",
  fontSize: 11,
  color: "var(--color-apt-text)",
};
