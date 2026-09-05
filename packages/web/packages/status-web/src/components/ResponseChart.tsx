import type { ReactElement } from "react";

import { PALETTE, TINT } from "../lib/colors";
export interface ResponseChartProps {
  points: (number | null)[];
  color?: string;
  /** Pixel height of the chart (default 64). */
  height?: number;
}

/**
 * Inline SVG area+line sparkline, matching the mockup's spark() function.
 * Responsive width, `height`px tall (default 64). Empty/all-null → empty box.
 * null values produce a gap in the line (e.g. down/timed-out checks).
 */
export function ResponseChart({ points, color = PALETTE.blue, height = 64 }: ResponseChartProps): ReactElement {
  const nonNull = points.filter((p): p is number => p !== null);

  if (points.length === 0 || nonNull.length === 0) {
    return <div style={{ height, background: TINT.whiteGhost, borderRadius: 3 }} />;
  }

  const W = 320;
  const H = height;
  const max = Math.max(...nonNull, 1);
  const step = points.length > 1 ? W / (points.length - 1) : W;

  // Build line segments split at null gaps.
  // Each segment is a run of consecutive non-null points.
  const segments: { x: number; y: number }[][] = [];
  let current: { x: number; y: number }[] = [];

  for (let i = 0; i < points.length; i++) {
    const p: number | null = points[i] ?? null;
    if (p === null) {
      if (current.length > 0) {
        segments.push(current);
        current = [];
      }
    } else {
      current.push({
        x: i * step,
        y: H - (p / max) * H * 0.92 - 3,
      });
    }
  }
  if (current.length > 0) segments.push(current);

  // Build line path from all segments (M to start of each, L for subsequent points).
  const linePath = segments
    .map((seg) => seg.map(({ x, y }, j) => `${j === 0 ? "M" : "L"}${x.toFixed(0)},${y.toFixed(0)}`).join(" "))
    .join(" ");

  // Build area path: one closed shape per segment, floor at H.
  const areaPath = segments
    .map((seg) => {
      const line = seg.map(({ x, y }, j) => `${j === 0 ? "M" : "L"}${x.toFixed(0)},${y.toFixed(0)}`).join(" ");
      const lastX = seg[seg.length - 1]!.x.toFixed(0);
      const firstX = seg[0]!.x.toFixed(0);
      return `${line} L${lastX},${H} L${firstX},${H} Z`;
    })
    .join(" ");

  return (
    <svg
      width="100%"
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="none"
      style={{ height, display: "block" }}
      aria-hidden="true"
    >
      <path d={areaPath} fill={`color-mix(in srgb, ${color} 13%, transparent)`} />
      <path d={linePath} fill="none" stroke={color} strokeWidth={1.5} />
    </svg>
  );
}
