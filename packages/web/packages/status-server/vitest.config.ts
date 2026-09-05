import { defineConfig } from "vitest/config";

// Self-contained config so `pnpm --filter @agentic-toolkit/status-server run test`
// (cwd = this package) discovers test/**/*.test.ts. Pure Node — no DOM, no React.
// `test/` is a sibling of `src/`, so every test keeps its `../src/...` imports
// whether it runs here or from a host's vendored copy of this package.
export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    testTimeout: 30_000,
  },
});
