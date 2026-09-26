/**
 * Rendering the backend's timestamps — moved to `@agenticdevelopertoolkit/ui/lib/timestamps`, because the
 * rule it encodes (a Postgres `timestamp` arrives with a space and no zone, and `new Date()` reads
 * that as LOCAL time) is a property of the transport, and the ecosystem panes read the same
 * columns off the same backend. Kept as this path so the four pages that import it did not each
 * have to learn where it went.
 */
export {
  parseBackendTimestamp,
  formatDate,
  formatDateTime,
} from "@agenticdevelopertoolkit/ui/lib/timestamps";
