import { writeFileSync } from 'node:fs';
import { createClient } from '@libsql/client';
import { drizzle } from 'drizzle-orm/libsql';
import * as schema from '../src/libsql/schema';
import { createApp } from '../src/app';
import { buildOpenApiSpec } from '../src/openapi/build';
import { envConfig } from '../src/config/env';

const db = drizzle(createClient({ url: ':memory:' }), { schema });
const config = envConfig(process.env);
const spec = buildOpenApiSpec(createApp({ db, config }), config.appVersion);
writeFileSync('openapi.json', JSON.stringify(spec, null, 2));
console.log('wrote openapi.json');
