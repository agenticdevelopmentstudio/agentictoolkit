// `@agentic-toolkit/status-web` — the operator dashboard's host-facing surface.
// A Next host mounts these in its own pages and layouts; everything else in this
// package is reached through the `./components/*`, `./lib/*` and `./header-auth`
// subpaths. Every component here is a Client Component (the panels are
// interactive), so this barrel carries "use client" through the build.
export { StatusSign } from "./components/StatusSign";
export { StatusDot } from "./components/StatusDot";
export { HomeGate } from "./components/HomeGate";
export { WallboardStatus } from "./components/WallboardStatus";
export { StatusHostProvider, useStatusHost, type StatusHostSettings } from "./components/StatusHost";
export { BoardShell } from "./components/BoardShell";
export { AutoConfigureProvider } from "./components/AutoConfigureProvider";
export { DeviceApproval } from "./components/DeviceApproval";
export * from "./components/board-views";
export * from "./lib/colors";
export * from "./lib/retired-storage";
export * from "./header-auth";
