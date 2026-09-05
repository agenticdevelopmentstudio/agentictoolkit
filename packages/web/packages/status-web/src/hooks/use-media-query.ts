"use client";
import { useEffect, useState } from "react";

/**
 * Track a CSS media query on the client. Returns false during SSR / first paint
 * (server can't measure the viewport), then updates after mount and on change.
 */
export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(false);

  useEffect(() => {
    const mq = window.matchMedia(query);
    setMatches(mq.matches);
    const onChange = (e: MediaQueryListEvent): void => setMatches(e.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [query]);

  return matches;
}
