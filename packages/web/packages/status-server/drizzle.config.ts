import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  dialect: 'sqlite',
  schema: './src/libsql/schema.ts',
  out: './src/libsql/migrations',
  dbCredentials: { url: process.env.DATABASE_URL ?? 'file:./status.db' },
  verbose: true,
  strict: true,
});
