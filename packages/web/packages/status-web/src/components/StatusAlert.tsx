"use client";
import { type ReactElement, useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import { Settings } from "lucide-react";
import { Alert, AlertTitle, AlertDescription } from "@agentic-toolkit/ui/components/alert";
import { Button } from "@agentic-toolkit/ui/components/button";

/**
 * A themed, in-app replacement for window.alert — the shared accent {@link Alert}
 * card presented as a small centered modal (portaled to <body> like Popover so no
 * ancestor `overflow` can clip it). Renders nothing when `message` is null.
 * Dismiss via the button, Escape, or a backdrop click.
 */
export function StatusAlert({
  message,
  title = "Auto Configure",
  onClose,
}: {
  message: string | null;
  title?: string;
  onClose: () => void;
}): ReactElement | null {
  const dismissRef = useRef<HTMLButtonElement>(null);
  const restoreRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    if (message == null) return;
    // Move focus into the dialog, restore it to the trigger on close (a11y).
    restoreRef.current = document.activeElement as HTMLElement | null;
    dismissRef.current?.focus();
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      restoreRef.current?.focus?.();
    };
  }, [message, onClose]);

  if (message == null) return null;

  return createPortal(
    <div
      onClick={onClose}
      className="fixed inset-0 z-[1000] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
    >
      <Alert
        variant="accent"
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-md shadow-lg"
      >
        <Settings aria-hidden />
        <AlertTitle className="text-[11px] font-bold tracking-wider uppercase text-apt-gold">{title}</AlertTitle>
        {/* whitespace-pre-line: a run summary carries per-project detail lines, and without
            it they collapse into one unreadable paragraph. Long reasons still wrap. */}
        <AlertDescription className="mt-1 max-h-[60vh] overflow-y-auto leading-relaxed break-words whitespace-pre-line text-apt-text">
          {message}
        </AlertDescription>
        <div className="col-start-2 mt-3 flex justify-end">
          <Button ref={dismissRef} type="button" variant="outline" size="sm" onClick={onClose}>
            Dismiss
          </Button>
        </div>
      </Alert>
    </div>,
    document.body,
  );
}
