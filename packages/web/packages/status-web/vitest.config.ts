import { defineConfig } from "vitest/config";

// Self-contained config so `pnpm --filter @agentic-toolkit/status-web run test`
// (cwd = this package) discovers src/**/*.test.ts(x). The default environment is
// node; DOM tests opt in per file with `// @vitest-environment jsdom`, exactly as
// they did in the host, and the workspace setup shim supplies jest-dom matchers,
// ResizeObserver, matchMedia and storage for those.
export default defineConfig({
  test: {
    dir: "src",
    include: ["**/*.test.ts", "**/*.test.tsx"],
    setupFiles: ["../../vitest.setup.ts"],
    testTimeout: 30_000,
  },
});
