import { describe, it, expect } from "vitest";
import { stepIndex } from "@agentic-toolkit/ui/lib/step-index";

describe("stepIndex", () => {
  it("moves down and clamps at the last item", () => {
    expect(stepIndex(3, 0, "ArrowDown")).toBe(1);
    expect(stepIndex(3, 2, "ArrowDown")).toBe(2);
  });
  it("moves up and clamps at the first item", () => {
    expect(stepIndex(3, 2, "ArrowUp")).toBe(1);
    expect(stepIndex(3, 0, "ArrowUp")).toBe(0);
  });
  it("selects the first item on the first key press when nothing is selected", () => {
    expect(stepIndex(3, -1, "ArrowDown")).toBe(0);
    expect(stepIndex(3, -1, "ArrowUp")).toBe(0);
  });
  it("returns -1 for an empty list", () => {
    expect(stepIndex(0, -1, "ArrowDown")).toBe(-1);
  });
});
