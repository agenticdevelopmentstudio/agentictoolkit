"use client";
import type { ReactElement } from "react";
import { Button } from "@agentic-toolkit/ui/components/button";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import { useAutoConfigure } from "./AutoConfigureProvider";

/**
 * One amber "Auto Configure" action, shared by the Overview banner and the Configure
 * "Sites" header. MATCH-ONLY: it wires each existing site to the deploy project that owns
 * its domain — never creating a site — via the shared runner; the themed result dialog is
 * rendered by AutoConfigureProvider (so it survives this button unmounting on success).
 */
export function AutoConfigureButton({ className }: { className?: string }): ReactElement {
  const { run, busy, progress } = useAutoConfigure();
  return (
    <Button
      type="button"
      variant="outline"
      size="xs"
      disabled={busy}
      onClick={() => void run()}
      title="Match each site to the deploy project that owns its domain"
      className={cn(
        "shrink-0 border-apt-gold/50 font-mono text-[11px] font-semibold text-apt-gold hover:bg-apt-gold/10",
        className,
      )}
    >
      {busy ? (progress ? `Configuring ${progress.done}/${progress.total}…` : "Configuring…") : "⚙ Auto Configure"}
    </Button>
  );
}
