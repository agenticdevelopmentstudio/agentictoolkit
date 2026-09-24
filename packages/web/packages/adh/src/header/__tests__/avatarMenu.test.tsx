import { describe, expect, it, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { AvatarMenu } from "../AvatarMenu";

const user = { name: "Mike Fullerton", fullName: "Mike Fullerton" };
// A slug is data on the account, but it no longer turns the Profile row on by itself —
// see AvatarMenuProps.profileHref. Kept as a separate fixture rather than added to
// `user` above, so a case that renders with a slug but no profileHref still proves
// slug-alone is not the gate.
const userWithSlug = { ...user, slug: "mikefullerton" };

describe("AvatarMenu", () => {
  it("names the settings row 'User Settings'", async () => {
    render(<AvatarMenu user={user} onSettings={vi.fn()} onLogout={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(await screen.findByText("User Settings")).toBeInTheDocument();
    expect(screen.queryByText(/^Settings$/)).not.toBeInTheDocument();
  });

  it("omits the row entirely when the host offers no settings surface", async () => {
    render(<AvatarMenu user={user} onLogout={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(screen.queryByText("User Settings")).not.toBeInTheDocument();
  });

  it("still shows exactly the five account rows, when the caller supplies profileHref", async () => {
    render(
      <AvatarMenu
        user={userWithSlug}
        profileHref="/mikefullerton/profile"
        onSettings={vi.fn()}
        onLogout={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(await screen.findByText("Welcome Mike!")).toBeInTheDocument();
    expect(screen.getByText("Home")).toBeInTheDocument();
    expect(screen.getByText("Profile")).toBeInTheDocument();
    expect(screen.getByText("User Settings")).toBeInTheDocument();
    expect(screen.getByText("Log out")).toBeInTheDocument();
  });

  it("shows four rows, with no Profile, when the account has no slug — there is no profile address to link to", async () => {
    render(<AvatarMenu user={user} onSettings={vi.fn()} onLogout={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(await screen.findByText("Welcome Mike!")).toBeInTheDocument();
    expect(screen.getByText("Home")).toBeInTheDocument();
    expect(screen.queryByText("Profile")).not.toBeInTheDocument();
    expect(screen.getByText("User Settings")).toBeInTheDocument();
    expect(screen.getByText("Log out")).toBeInTheDocument();
  });

  it("omits Profile when the account has a slug but the caller withholds profileHref — this site carries no /<slug>/profile route", async () => {
    render(<AvatarMenu user={userWithSlug} onSettings={vi.fn()} onLogout={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(await screen.findByText("Welcome Mike!")).toBeInTheDocument();
    expect(screen.queryByText("Profile")).not.toBeInTheDocument();
  });

  it("points the Profile row at whatever href the caller supplies", async () => {
    render(
      <AvatarMenu
        user={userWithSlug}
        profileHref="/mikefullerton/profile"
        onSettings={vi.fn()}
        onLogout={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    // The row's accessible role is "menuitem", not "link": Base UI's MenuLinkItem renders an
    // `<a>` but assigns it the ARIA menuitem role (the WAI-ARIA menu pattern requires every
    // child of role="menu" to expose role="menuitem", regardless of the underlying element) —
    // so `getByRole("link", …)` never matches a row inside this popup.
    const link = await screen.findByRole("menuitem", { name: "Profile" });
    expect(link.getAttribute("href")).toBe("/mikefullerton/profile");
  });

  it("places Profile between Home and Settings", async () => {
    render(
      <AvatarMenu
        user={userWithSlug}
        profileHref="/mikefullerton/profile"
        onSettings={vi.fn()}
        onLogout={vi.fn()}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    await screen.findByText("Profile");
    // Position is the requirement, not merely presence: every other case here queries by text or
    // role and would pass just as happily with Profile moved below Log out. Reading indices out of
    // the rendered text is what makes a reordering fail — the rows are siblings in DOM order, so
    // document order IS visual order.
    const text = document.body.textContent ?? "";
    expect(text.indexOf("Profile")).toBeGreaterThan(text.indexOf("Home"));
    expect(text.indexOf("Profile")).toBeLessThan(text.indexOf("User Settings"));
  });

  it("offers no Debug Options row unless the caller hands in the door", async () => {
    render(<AvatarMenu user={user} onSettings={vi.fn()} onLogout={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    await screen.findByText("Log out");
    expect(screen.queryByText("Debug Options")).not.toBeInTheDocument();
  });

  it("ends with Debug Options, after Log out and behind its own divider, and opens it", async () => {
    const onDebugOptions = vi.fn();
    render(
      <AvatarMenu
        user={userWithSlug}
        profileHref="/mikefullerton/profile"
        onSettings={vi.fn()}
        onLogout={vi.fn()}
        onDebugOptions={onDebugOptions}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    const row = await screen.findByRole("menuitem", { name: "Debug Options" });
    // LAST — every menuitem, in document order, and this one closes the list.
    const items = screen.getAllByRole("menuitem");
    expect(items[items.length - 1]).toBe(row);
    // ...with a separator directly before it, so it reads as apart from the account rows.
    expect(row.previousElementSibling?.getAttribute("role")).toBe("separator");
    fireEvent.click(row);
    expect(onDebugOptions).toHaveBeenCalledTimes(1);
  });

  it("shows the Debug row's hint beside its label without renaming the row", async () => {
    render(
      <AvatarMenu user={user} onLogout={vi.fn()} onDebugOptions={vi.fn()} debugOptionsHint="Sim: prod" />,
    );
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    expect(await screen.findByText("Sim: prod")).toBeInTheDocument();
    // The NAME, not just the text on screen: a menuitem named from all of its content
    // read "Debug OptionsSim: prod" here, and a role query (or a voice command) for
    // "Debug Options" found nothing — while production was being simulated, which is
    // exactly when a developer comes back for this row. The hint is the description.
    const row = screen.getByRole("menuitem", { name: "Debug Options" });
    expect(row).toHaveAccessibleDescription("Sim: prod");
  });

  it("describes the Debug row with nothing when there is no hint", async () => {
    render(<AvatarMenu user={user} onLogout={vi.fn()} onDebugOptions={vi.fn()} />);
    fireEvent.click(screen.getByRole("button", { name: "Open Mike Fullerton menu" }));
    const row = await screen.findByRole("menuitem", { name: "Debug Options" });
    expect(row).toHaveAccessibleDescription("");
  });
});
