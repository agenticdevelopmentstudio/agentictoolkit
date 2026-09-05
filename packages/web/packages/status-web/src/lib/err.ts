/** Render an unknown thrown value as a display string (Error → message, else String). */
export const msg = (e: unknown): string => (e instanceof Error ? e.message : String(e));
