import { act, renderHook, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { useBulkRemove } from "../use-bulk-remove";

interface Row {
  id: string;
}
const A = { id: "a" };
const B = { id: "b" };

function setup(remove: (id: string) => Promise<unknown>) {
  const onSettled = vi.fn();
  const onDone = vi.fn();
  const hook = renderHook(() =>
    useBulkRemove<Row>({
      getId: (r) => r.id,
      remove,
      onSettled,
      onDone,
      errorMessage: (e) => (e instanceof Error ? e.message : "failed"),
    }),
  );
  return { ...hook, onSettled, onDone };
}

describe("useBulkRemove", () => {
  it("closes and reports done when every row goes", async () => {
    const { result, onSettled, onDone } = setup(() => Promise.resolve());
    act(() => result.current.open([A, B]));
    act(() => result.current.confirm());
    await waitFor(() => expect(result.current.targets).toBeNull());
    expect(onSettled).toHaveBeenCalledTimes(1);
    expect(onDone).toHaveBeenCalledTimes(1);
    expect(result.current.error).toBeNull();
  });

  it("narrows the confirm to the rows that failed, so a retry never re-sends a removed one", async () => {
    const remove = vi.fn((id: string) =>
      id === "b" ? Promise.reject(new Error("server said no")) : Promise.resolve(),
    );
    const { result, onSettled, onDone } = setup(remove);
    act(() => result.current.open([A, B]));
    act(() => result.current.confirm());
    await waitFor(() => expect(result.current.pending).toBe(false));
    expect(result.current.targets).toEqual([B]);
    expect(result.current.error).toBe("1 of 2 could not be removed: server said no");
    // Re-read even on failure: A is gone and the table must not keep showing it.
    expect(onSettled).toHaveBeenCalledTimes(1);
    expect(onDone).not.toHaveBeenCalled();

    remove.mockClear();
    remove.mockImplementation(() => Promise.resolve());
    act(() => result.current.confirm());
    await waitFor(() => expect(result.current.targets).toBeNull());
    expect(remove.mock.calls.map(([id]) => id)).toEqual(["b"]);
  });

  it("stays pending until EVERY request settles, not just the first rejection", async () => {
    let finishA!: () => void;
    const remove = (id: string) =>
      id === "a"
        ? new Promise<void>((resolve) => {
            finishA = resolve;
          })
        : Promise.reject(new Error("nope"));
    const { result } = setup(remove);
    act(() => result.current.open([A, B]));
    act(() => result.current.confirm());
    await act(async () => {});
    expect(result.current.pending).toBe(true);
    await act(async () => finishA());
    await waitFor(() => expect(result.current.pending).toBe(false));
    expect(result.current.targets).toEqual([B]);
  });
});
