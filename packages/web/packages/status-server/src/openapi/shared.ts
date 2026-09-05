/* eslint-disable @typescript-eslint/no-explicit-any --
 * An OpenAPI document is an open-ended JSON structure, and zod's toJSONSchema
 * returns `unknown`-shaped schemas; building path/response objects dynamically
 * needs `any`. No client input flows through here — these are static document
 * fragments, derived entirely from the trusted route zod schemas. */
import { z } from 'zod';

/** A map of OpenAPI path → path-item object. The shape each `*Paths` module exports. */
export type Paths = Record<string, any>;
/** A map of component-schema name → JSON Schema. The shape each `*Schemas` module exports. */
export type Schemas = Record<string, any>;

/** `security: BEARER` marks an operation as requiring the API-token bearer scheme. */
export const BEARER = [{ bearerAuth: [] as string[] }];

/** Wrap a JSON Schema as an `application/json` request/response body. */
export const jsonBody = (s: any) => ({ content: { 'application/json': { schema: s } } });

/** Reference a named component schema, e.g. `ref('Error')`. */
export const ref = (name: string) => ({ $ref: `#/components/schemas/${name}` });

/** The standard `{ error: { message } }` error response, used on 4xx/5xx. */
export const errorResponse = { description: 'Error', ...jsonBody(ref('Error')) };

/**
 * The standard `Error` response keyed by each status code — spread into a
 * `responses` map: `responses: { 200: okJson(...), ...errors(401, 404) }`. One place
 * to define what a documented error entry is, instead of repeating `: errorResponse`.
 */
export const errors = (...codes: number[]): Record<number, typeof errorResponse> =>
  Object.fromEntries(codes.map((c) => [c, errorResponse]));

/** A documented JSON success response: a description + an `application/json` body. */
export const okJson = (description: string, schema: any) => ({ description, ...jsonBody(schema) });

/** The common `{ ok: true }` success body, shared by the self-serve mutation routes. */
export const okFlag = okJson('Success', {
  type: 'object',
  required: ['ok'],
  properties: { ok: { type: 'boolean' } },
});

/** A single path parameter (`{name}`), typed as a string. */
export const pathParam = (name: string) => ({
  name,
  in: 'path' as const,
  required: true,
  schema: { type: 'string' },
});

/** A query parameter; pass `required: true` for mandatory ones. */
export const queryParam = (name: string, required = false) => ({
  name,
  in: 'query' as const,
  required,
  schema: { type: 'string' },
});

/**
 * Convert a route's own zod schema to JSON Schema for the doc, so the documented
 * request/response body is the SAME schema the handler validates against (no hand-
 * transcription to drift). Falls back to an untyped object if a schema contains a
 * type zod can't represent in JSON Schema (e.g. a raw `z.date()`); the route zod
 * bodies here are plain JSON shapes, so that path is defensive only.
 */
export function zodJson(schema: unknown): any {
  try {
    return z.toJSONSchema(schema as z.ZodType, { target: 'draft-2020-12' });
  } catch {
    return { type: 'object', additionalProperties: true };
  }
}
