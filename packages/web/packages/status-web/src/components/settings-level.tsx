"use client";
import { createContext, useContext, useLayoutEffect, type ReactElement, type ReactNode } from "react";
import type { TopicLevel } from "@agentic-toolkit/ui/blocks";

/**
 * The channel a Settings section uses to publish its ENTITY LIST up to the board
 * hierarchy (BoardShell renders it as the third topic level, after the sections
 * level) — the WorkspaceShell publish-levels pattern. Sections without an entity
 * list (Appearance) publish nothing.
 */
const SettingsLevelContext = createContext<(level: TopicLevel | null) => void>(() => {});

export function SettingsLevelProvider({
  onPublish,
  children,
}: {
  onPublish: (level: TopicLevel | null) => void;
  children: ReactNode;
}): ReactElement {
  return <SettingsLevelContext.Provider value={onPublish}>{children}</SettingsLevelContext.Provider>;
}

/**
 * Publish this section's entity list as a board hierarchy level (null clears it).
 * Memoize the level in the caller — every new object re-publishes. Unmount
 * withdraws the level.
 */
export function useSettingsEntityLevel(level: TopicLevel | null): void {
  const publish = useContext(SettingsLevelContext);
  // Publish the current level on every change. `level` MUST be memoized by the caller: a
  // fresh object each render re-publishes and, via BoardShell's setState, re-renders — an
  // unstably-memoized level loops (React then throws max-update-depth, the loud backstop).
  useLayoutEffect(() => {
    publish(level);
  }, [publish, level]);
  // Withdraw the level ONLY on unmount (this effect's deps never change), NOT on every level
  // change — so switching filters/data republishes the new level with no intermediate `null`
  // flicker or double setState churn.
  useLayoutEffect(() => () => publish(null), [publish]);
}
