// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { purgeRetiredStorage } from "./retired-storage";

// Fix Round 4 item 5.9. The retired activity blob is the literal artifact of the bug
// this branch was opened to fix, so the purge has to actually fire — and it has to be
// unable to break the mount it runs in.
//
// This jsdom build ships NO `window.localStorage` (see use-live-snapshot.dom.test.tsx,
// which guards with `?.` for the same reason), so each test installs its own.

function installStorage(impl: Partial<Storage>): void {
  Object.defineProperty(window, "localStorage", { value: impl, configurable: true, writable: true });
}

function memoryStorage() {
  const map = new Map<string, string>();
  return {
    map,
    getItem: (k: string) => (map.has(k) ? map.get(k)! : null),
    setItem: (k: string, v: string) => void map.set(k, String(v)),
    removeItem: (k: string) => void map.delete(k),
    clear: () => map.clear(),
  };
}

let store: ReturnType<typeof memoryStorage>;

beforeEach(() => {
  store = memoryStorage();
  installStorage(store as unknown as Storage);
});

afterEach(() => {
  vi.unstubAllGlobals();
  Reflect.deleteProperty(window, "localStorage");
});

describe("purgeRetiredStorage", () => {
  it("removes the retired activity blob", () => {
    store.map.set("adh-activity-v1", JSON.stringify([{ id: "phantom" }]));
    purgeRetiredStorage();
    expect(store.getItem("adh-activity-v1")).toBeNull();
  });

  it("leaves keys the app still uses alone", () => {
    // The purge is a named allow-list, not a wipe: every live preference survives it.
    store.map.set("adh-font-scale", "1.2");
    store.map.set("adh-env-filter", JSON.stringify(["production"]));
    store.map.set("adh-healthy-ttl", "3600000");
    purgeRetiredStorage();
    expect(store.getItem("adh-font-scale")).toBe("1.2");
    expect(store.getItem("adh-env-filter")).toBe(JSON.stringify(["production"]));
    expect(store.getItem("adh-healthy-ttl")).toBe("3600000");
  });

  it("is a no-op when the key was never written", () => {
    expect(() => purgeRetiredStorage()).not.toThrow();
    expect(store.map.size).toBe(0);
  });

  it("swallows a throwing localStorage — storage-disabled contexts must still mount", () => {
    const removeItem = vi.fn(() => {
      throw new DOMException("The operation is insecure.", "SecurityError");
    });
    installStorage({ removeItem } as unknown as Storage);
    expect(() => purgeRetiredStorage()).not.toThrow();
    expect(removeItem).toHaveBeenCalledWith("adh-activity-v1");
  });

  it("does nothing when there is no window (SSR)", () => {
    vi.stubGlobal("window", undefined);
    expect(() => purgeRetiredStorage()).not.toThrow();
  });
});
