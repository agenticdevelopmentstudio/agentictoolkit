import { defineConfig } from 'tsup'
import { preserveDirectivesPlugin } from 'esbuild-plugin-preserve-directives'

export default defineConfig({
  entry: ['src/index.ts', 'src/testing/index.ts'],
  outDir: 'dist',
  format: ['esm'],
  target: 'es2022',
  platform: 'browser',
  sourcemap: true,
  clean: true,
  dts: false,
  bundle: true,
  splitting: true,
  outExtension: () => ({ js: '.js' }),
  // Peer/shared libs stay external so dist imports them (single version, resolved
  // from the consumer) rather than bundling copies: react, the sibling toolkit
  // packages, next (the host app owns it), lucide-react, and base-ui.
  external: [/^react/, /^@agentic-toolkit\//, /^next\//, 'lucide-react', '@base-ui/react', '@base-ui/react/*'],
  esbuildPlugins: [
    preserveDirectivesPlugin({
      directives: ['use client', 'use server'],
      include: /\.(js|ts|jsx|tsx)$/,
      exclude: /node_modules/,
    }),
  ],
})
