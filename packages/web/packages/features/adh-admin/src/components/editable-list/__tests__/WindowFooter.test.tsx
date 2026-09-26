// @vitest-environment jsdom
//
// The strip under an append-only list. What is asserted here is the sentence it writes, because
// that sentence is the only thing standing between "there is no such event" and "the event you
// want is older than what has been loaded" — two readings of an empty table that lead an operator
// to opposite conclusions.
import * as React from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { WindowFooter } from "../WindowFooter";

afterEach(cleanup);

function setup(overrides: Partial<React.ComponentProps<typeof WindowFooter>> = {}) {
  const onLoadMore = vi.fn();
  render(
    <WindowFooter
      noun="events"
      loaded={200}
      showing={200}
      total={10_000}
      hasMore
      onLoadMore={onLoadMore}
      {...overrides}
    />,
  );
  const caption = () => screen.getByRole("status").textContent ?? "";
  const button = () => screen.queryByRole("button") as HTMLButtonElement | null;
  return { onLoadMore, caption, button };
}

describe("the caption", () => {
  it("says the list is partial while more remains", () => {
    expect(setup().caption()).toContain("older events are not loaded");
  });

  it("says the list is complete when nothing remains", () => {
    // The claim an operator needs before concluding something never happened.
    expect(setup({ hasMore: false }).caption()).toContain("the whole log");
  });

  it("distinguishes what is loaded from what is showing", () => {
    const { caption } = setup({ showing: 12 });
    expect(caption()).toContain("12 of 200 events");
  });

  it("states one number when nothing is filtered out", () => {
    expect(setup().caption()).toContain("200 events");
  });

  it("hedges the total, because the server's count saturates", () => {
    expect(setup().caption()).toContain("about 10,000");
  });

  it("omits the total rather than claiming one it does not have", () => {
    const { caption } = setup({ total: undefined });
    expect(caption()).toContain("older events are not loaded");
    expect(caption()).not.toContain("about");
  });

  it("lets a catalog say what its window actually is", () => {
    // The defaults describe a log read newest-first. A catalog comes back in the server's own
    // order, so "the newest hundred" would be a claim about an ordering it does not have — and an
    // operator who believes it stops looking for a row they assume must be older.
    const { caption } = setup({
      noun: "templates",
      windowWord: "first",
      unloadedWord: "more",
      wholeWord: "catalog",
    });
    expect(caption()).toContain("the first of about 10,000");
    expect(caption()).toContain("more templates are not loaded");
  });

  it("lets a catalog name the complete thing too", () => {
    expect(setup({ hasMore: false, wholeWord: "catalog" }).caption()).toContain(
      "the whole catalog",
    );
  });

  it("omits a total that is not bigger than the window", () => {
    // A server that reports 200 of 200 while still offering another page is describing its own
    // cap, not the log; repeating it as "about 200" would understate what is left.
    expect(setup({ total: 200 }).caption()).not.toContain("about");
  });
});

describe("growing the window", () => {
  it("offers the button while there is more", () => {
    expect(setup().button()).toBeTruthy();
  });

  it("drops the button once the whole log is loaded", () => {
    expect(setup({ hasMore: false }).button()).toBeNull();
  });

  it("names the button after what is missing, not after the log", () => {
    expect(setup({ noun: "templates", unloadedWord: "more" }).button()!.textContent).toContain(
      "Load more templates",
    );
  });

  it("asks for more", () => {
    const { button, onLoadMore } = setup();
    fireEvent.click(button()!);
    expect(onLoadMore).toHaveBeenCalledOnce();
  });

  it("cannot be asked twice while a fetch is in flight", () => {
    expect(setup({ busy: true }).button()!.disabled).toBe(true);
  });
});
