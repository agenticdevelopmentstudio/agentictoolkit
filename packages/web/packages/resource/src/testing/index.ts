// @agentic-toolkit/resource/testing — test-support helpers for a feature package's own component
// tests. Never imported from production code (this subpath is `devDependency`-only for every
// consumer), which is why it is a separate entry rather than living in the package's main barrel.
export { RailStandIn, type RailStandInProps } from "./rail-stand-in";
