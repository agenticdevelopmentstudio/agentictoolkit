import { defineConfig } from "tsup";

// Every subpath in package.json `exports` is an entry here. `test/` is shipped as
// source for the host's vitest run but is never part of dist. Dependencies and
// peer dependencies are external by tsup's default, so dist imports hono,
// drizzle-orm, @libsql/client and @agentic-toolkit/deploy-platform from the host.
export default defineConfig({
  entry: [
    "src/index.ts",
    "src/config/index.ts",
    "src/libsql/index.ts",
    "src/monitor/worker.ts",
    "src/board/index.ts",
    "src/board/derive-activity.ts",
    "src/monitor/deploy-status.ts",
    "src/types.ts",
  ],
  format: ["esm"],
  target: "es2022",
  platform: "node",
  splitting: true,
  sourcemap: true,
  clean: true,
});
