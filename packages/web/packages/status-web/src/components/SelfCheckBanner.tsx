"use client";
import type { ReactElement } from "react";
import { cn } from "@agentic-toolkit/ui/lib/utils";
import type { IntegrationsResponse } from "../types";
import { computeSelfCheck } from "../lib/self-check";

export interface SelfCheckBannerProps {
  data: IntegrationsResponse | undefined;
}

export function SelfCheckBanner({ data }: SelfCheckBannerProps): ReactElement | null {
  const view = computeSelfCheck(data);
  if (!view) return null;
  const { missingEnv, missingEnvError, issues, hasError } = view;
  const count = issues.length + missingEnv.length;

  return (
    <div
      role="status"
      className={cn(
        "flex shrink-0 flex-wrap items-center gap-3.5 border-b px-4 py-1.5 font-mono",
        hasError ? "border-apt-red/35 bg-apt-red/10" : "border-apt-gold/35 bg-apt-gold/10",
      )}
    >
      <span
        className={cn(
          "whitespace-nowrap text-[11px] font-bold tracking-wider",
          hasError ? "text-apt-red" : "text-apt-gold",
        )}
      >
        ⚠ SELF-CHECK: {count} issue{count !== 1 ? "s" : ""}
      </span>

      {/* Missing expected env — named exactly so a blank var (the silent killer) is
          impossible to miss. Red only when it's genuinely broken (couldn't resolve);
          amber when it's recoverable (e.g. an auto-discovered account you can pin). */}
      {missingEnv.length > 0 && (
        <span
          title="These environment variables are expected by the monitor but are not set"
          className={cn(
            "inline-flex items-center gap-1.5 rounded-[5px] border px-2 py-0.5 text-[11.5px] font-bold",
            missingEnvError ? "border-apt-red/40 bg-apt-red/15 text-apt-red" : "border-apt-gold/40 bg-apt-gold/15 text-apt-gold",
          )}
        >
          MISSING ENV: {missingEnv.join(", ")}
        </span>
      )}

      {issues.map((check) => {
        const err = check.state === "error";
        return (
          <span
            key={check.id}
            className={cn(
              "inline-flex items-center gap-1.5 rounded-[5px] border px-2 py-0.5 text-[11.5px]",
              err ? "border-apt-red/40 bg-apt-red/15 text-apt-red" : "border-apt-gold/40 bg-apt-gold/15 text-apt-gold",
            )}
          >
            {check.label} — {check.detail}
          </span>
        );
      })}
    </div>
  );
}
