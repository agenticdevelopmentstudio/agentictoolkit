import { describe, it, expect } from "vitest";
import { formatRemaining } from "./NextCheckCountdown";

describe("formatRemaining (the next-check countdown text)", () => {
  it("renders m:ss, ceiling partial seconds so the display never skips 0:01", () => {
    expect(formatRemaining(60_000)).toBe("1:00");
    expect(formatRemaining(59_999)).toBe("1:00"); // ceil
    expect(formatRemaining(61_000)).toBe("1:01");
    expect(formatRemaining(9_000)).toBe("0:09");
    expect(formatRemaining(500)).toBe("0:01");
  });

  it("floors at 0:00 for zero/negative remainders (poll overdue)", () => {
    expect(formatRemaining(0)).toBe("0:00");
    expect(formatRemaining(-5_000)).toBe("0:00");
  });
});
