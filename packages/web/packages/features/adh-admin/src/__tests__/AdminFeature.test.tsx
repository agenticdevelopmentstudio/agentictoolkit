import { render } from "@testing-library/react";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  pushSegment: vi.fn(),
  confirm: vi.fn<() => Promise<boolean>>(),
  onSelect: undefined as ((id: string | null) => void) | undefined,
}));

vi.mock("@agentic-toolkit/resource", () => ({
  RailHostBoundary: ({ children }: { children: ReactNode }) => <>{children}</>,
  StackGroupDetail: (props: { urlSelection: { onSelect: (id: string | null) => void } }) => {
    h.onSelect = props.urlSelection.onSelect;
    return null;
  },
  useBasePathRoute: () => ({ pushSegment: h.pushSegment }),
}));
vi.mock("@agenticdevelopertoolkit/ui/lib/navigation-guard", () => ({
  confirmNavigation: h.confirm,
}));

import { AdminFeature } from "../AdminFeature";

const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("AdminFeature's section switch", () => {
  beforeEach(() => {
    h.pushSegment.mockReset();
    h.confirm.mockReset();
    render(<AdminFeature basePath="/admin" />);
  });

  it("asks the unsaved-changes guard first, and stays put when it says no", async () => {
    h.confirm.mockResolvedValue(false);
    h.onSelect?.("users");
    await settle();
    expect(h.confirm).toHaveBeenCalledTimes(1);
    expect(h.pushSegment).not.toHaveBeenCalled();
  });

  it("switches once the guard allows it", async () => {
    h.confirm.mockResolvedValue(true);
    h.onSelect?.("users");
    await settle();
    expect(h.pushSegment).toHaveBeenCalledWith("users");
  });
});
