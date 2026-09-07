import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import { adtAlias, adtInline } from "../../vitest.adt";

// Self-contained config so `pnpm --filter @agentic-toolkit/status-web run test`
// (cwd = this package) discovers src/**/*.test.ts(x). The default environment is
// node; DOM tests opt in per file with `// @vitest-environment jsdom`, exactly as
// they did in the host, and the workspace setup shim supplies jest-dom matchers,
// ResizeObserver, matchMedia and storage for those.
export default defineConfig({
  resolve: {
    // The panels render @agenticdevelopertoolkit/ui source, which lives in a
    // separate, uninstalled pnpm workspace — ONE React in the test process, see
    // ../../vitest.adt.ts.
    alias: adtAlias(fileURLToPath(new URL(".", import.meta.url))),
  },
  test: {
    dir: "src",
    include: ["**/*.test.ts", "**/*.test.tsx"],
    setupFiles: ["../../vitest.setup.ts"],
    testTimeout: 30_000,
    server: {
      // Aliases only apply to modules vite processes; deps resolved out of another
      // workspace are externalized by default and Node-resolve on their own.
      deps: { inline: adtInline },
    },
  },
});
