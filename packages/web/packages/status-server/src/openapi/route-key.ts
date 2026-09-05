/**
 * Normalize a Hono route pattern (e.g. `/auth/tokens/:id`) to its OpenAPI path key
 * (`/auth/tokens/{id}`): `:param`→`{param}`, collapse duplicate slashes, strip the
 * trailing slash. Shared by the drift guard and anything else that has to agree on
 * what a route's key is, so they can never disagree.
 */
export function normHonoPath(path: string): string {
  return (
    path
      .replace(/:([A-Za-z0-9_]+)/g, '{$1}')
      .replace(/\/+/g, '/')
      .replace(/\/$/, '') || '/'
  );
}
