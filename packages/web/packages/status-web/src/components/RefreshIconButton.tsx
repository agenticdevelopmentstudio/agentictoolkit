"use client";
import { type ReactElement, useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { Button } from "@agentic-toolkit/ui/components/button";
import { cn } from "@agentic-toolkit/ui/lib/utils";

export interface RefreshIconButtonProps {
  onRefresh: () => void;
  refreshing?: boolean;
}

/**
 * Compact icon-only refresh control for the top bar — the shared borderless
 * (ghost) 24px icon Button carrying a spinning RefreshCw glyph. Spins while a
 * poll is in flight and is disabled so it can't queue a second poll mid-flight.
 */
export function RefreshIconButton({ onRefresh, refreshing = false }: RefreshIconButtonProps): ReactElement {
  // Keep spinning for at least one full rotation once a refresh starts — a fast
  // poll flips `refreshing` for under 0.8s, which would otherwise flicker the
  // arrows a single frame instead of visibly spinning them.
  const [spinning, setSpinning] = useState(false);
  useEffect(() => {
    if (refreshing) {
      setSpinning(true);
      return;
    }
    const t = setTimeout(() => setSpinning(false), 800);
    return () => clearTimeout(t);
  }, [refreshing]);

  return (
    <Button
      type="button"
      variant="ghost"
      size="icon-xs"
      onClick={onRefresh}
      disabled={refreshing}
      aria-label="Refresh status"
      title="Refresh now"
      className="shrink-0 text-apt-text-muted"
    >
      <span className={cn("inline-flex leading-none", spinning && "adh-spin")}>
        <RefreshCw aria-hidden className="size-4" />
      </span>
    </Button>
  );
}
