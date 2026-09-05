import { describe, it, expect } from "vitest";
import { computeOverall } from "./overall";

describe("computeOverall", () => {
  it("empty is unknown", () => expect(computeOverall([])).toBe("unknown"));
  it("all healthy is operational", () => expect(computeOverall(["healthy", "healthy"])).toBe("operational"));
  it("any degraded is degraded", () => expect(computeOverall(["healthy", "degraded"])).toBe("degraded"));
  it("some down is degraded", () => expect(computeOverall(["healthy", "down"])).toBe("degraded"));
  it("all down is major_outage", () => expect(computeOverall(["down", "down"])).toBe("major_outage"));
});
