import type { ReactElement } from "react";
import type { IndicatorState } from "../lib/overview";

import { COLORS, PALETTE } from "../lib/colors";
// Regular octagon inscribed in a 0..100 box, inset by 4 for the white rim.
const OCTAGON = "30.96,4 69.04,4 96,30.96 96,69.04 69.04,96 30.96,96 4,69.04 4,30.96";

const SIGN = {
  down: { fill: PALETTE.red, rim: COLORS.signRim, glow: "adh-indicator-down" },
  warn: { fill: PALETTE.amber, rim: COLORS.signRim, glow: "adh-indicator-warn" },
  ok: { fill: PALETTE.green, rim: COLORS.signRim, glow: "adh-indicator-ok" },
} as const;

/**
 * The road-sign status glyph: green check circle (ok), amber count triangle
 * (warn), red count octagon (down). Shared by the BigIndicator header and the
 * activity list's empty/offline states, so "the sign" is one drawing everywhere.
 * Omit `count` (or pass 0) on ok — the ok sign never shows a number.
 */
export function StatusSign({ state, count = 0, size }: { state: IndicatorState; count?: number; size: number }): ReactElement {
  const sign = SIGN[state];
  return (
    <svg className={sign.glow} width={size} height={size} viewBox="0 0 100 100" aria-hidden style={{ display: "block", flexShrink: 0 }}>
      {state === "ok" ? (
        <>
          <circle cx="50" cy="50" r="46" fill={sign.fill} stroke={sign.rim} strokeWidth={5} />
          <path d="M29 51 L44 67 L73 32" fill="none" stroke={sign.rim} strokeWidth={9} strokeLinecap="round" strokeLinejoin="round" />
        </>
      ) : state === "warn" ? (
        <>
          <polygon points="50,7 93,87 7,87" fill={sign.fill} stroke={sign.rim} strokeWidth={5} strokeLinejoin="round" />
          <text x="50" y="68" textAnchor="middle" dominantBaseline="central" fontSize="34" fontWeight={800} fill={COLORS.amberBgDeeper} style={{ fontFamily: "var(--mono, ui-monospace, monospace)" }}>
            {count}
          </text>
        </>
      ) : (
        <>
          <polygon points={OCTAGON} fill={sign.fill} stroke={sign.rim} strokeWidth={5} strokeLinejoin="round" />
          {/* countless red sign = a plain stop sign ("monitoring offline") — show ! not 0 */}
          <text x="50" y="51" textAnchor="middle" dominantBaseline="central" fontSize="42" fontWeight={800} fill={sign.rim} style={{ fontFamily: "var(--mono, ui-monospace, monospace)" }}>
            {count > 0 ? count : "!"}
          </text>
        </>
      )}
    </svg>
  );
}
