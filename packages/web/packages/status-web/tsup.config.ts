import { defineConfig } from "tsup";
import { preserveDirectivesPlugin } from "esbuild-plugin-preserve-directives";

// Entries are GLOBBED so that every subpath the `exports` map promises
// (`./components/*`, `./lib/*`, `./header-auth`) exists in dist without anyone
// editing this file — the same shape as @agentic-toolkit/ui. Hooks, config and
// telemetry modules are not public subpaths; they become shared chunks.
// `src/api/client.ts` is the one `api/*` module that IS a public subpath — the
// host's composition root imports it to mount `StatusApiProvider`.
// Tests and fixtures are source, not surface.
export default defineConfig({
  entry: [
    "src/index.ts",
    "src/header-auth.ts",
    "src/api/client.ts",
    "src/components/*.tsx",
    "src/components/*.ts",
    "src/lib/*.ts",
    "!src/**/*.test.ts",
    "!src/**/*.test.tsx",
    "!src/**/*.fixture.ts",
  ],
  outDir: "dist",
  format: ["esm"],
  target: "es2022",
  platform: "browser",
  sourcemap: true,
  clean: true,
  dts: false,
  bundle: true,
  splitting: true,
  outExtension: () => ({ js: ".js" }),
  // Peers and the sibling toolkit packages stay external so the host resolves ONE copy
  // of each (react-query's QueryClientProvider context, next/navigation's router).
  external: [
    "react",
    "react-dom",
    "react/jsx-runtime",
    "next",
    "next/navigation",
    "next/link",
    "@tanstack/react-query",
    "lucide-react",
    /^@agentic-toolkit\//,
  ],
  esbuildPlugins: [
    preserveDirectivesPlugin({
      directives: ["use client", "use server"],
      include: /\.(js|ts|jsx|tsx)$/,
      exclude: /node_modules/,
    }),
  ],
});
