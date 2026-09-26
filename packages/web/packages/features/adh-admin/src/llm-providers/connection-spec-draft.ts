// Pure draft<->wire conversion for a provider template's ConnectionSpec, kept
// separate from the editor component so it's independently testable (no DOM).
//
// The draft form is deliberately flatter than the wire shape: `auth` is one
// object on the wire keyed by `type`, but the editor shows a single auth-type
// select with type-specific fields underneath — so the draft carries every
// field for every type at once, and assembly picks only the ones the chosen
// type uses. Rows (urlVars / defaultQuery / extraHeaders) carry a `localId`
// purely for React keys; it never reaches the wire.

import type { ProviderConnectionSpec } from "../api/llm-providers";

export type ConnectionAuthType = "none" | "bearer" | "header" | "sigv4" | "oauth2";

export interface KVRow {
  localId: string;
  key: string;
  value: string;
}

export interface UrlVarRow {
  localId: string;
  name: string;
  label: string;
  example: string;
  secret: boolean;
}

export interface HeaderVarRow {
  localId: string;
  header: string;
  label: string;
  example: string;
  secret: boolean;
}

export interface ConnectionSpecDraft {
  authType: ConnectionAuthType;
  /** header auth only: the header name (e.g. api-key). */
  header: string;
  /** header auth only: how the key is framed in that header. */
  scheme: "bearer" | "raw";
  /** sigv4 only — reserved, not yet enforced by the backend client. */
  region: string;
  /** oauth2 only — reserved, not yet enforced by the backend client. */
  tokenUrl: string;
  urlVars: UrlVarRow[];
  headerVars: HeaderVarRow[];
  defaultQuery: KVRow[];
  extraHeaders: KVRow[];
}

let localIdSeq = 0;
export function newLocalId(prefix: string): string {
  localIdSeq += 1;
  return `${prefix}-${localIdSeq}`;
}

export function emptyConnectionSpecDraft(): ConnectionSpecDraft {
  return {
    authType: "none",
    header: "",
    scheme: "bearer",
    region: "",
    tokenUrl: "",
    urlVars: [],
    headerVars: [],
    defaultQuery: [],
    extraHeaders: [],
  };
}

function kvRowsFromRecord(record: Record<string, string> | undefined): KVRow[] {
  return Object.entries(record ?? {}).map(([key, value]) => ({
    localId: newLocalId("kv"),
    key,
    value,
  }));
}

/** Build an editable draft from a stored (or absent) ConnectionSpec. */
export function draftFromConnectionSpec(
  spec: ProviderConnectionSpec | null | undefined,
): ConnectionSpecDraft {
  if (!spec) return emptyConnectionSpecDraft();
  const auth = spec.auth;
  return {
    // A stored explicit `bearer` collapses to "none" — both mean plain Bearer, and
    // the editor offers only one option for that (see ConnectionSpecFields).
    authType: auth?.type === "bearer" ? "none" : (auth?.type ?? "none"),
    header: auth?.header ?? "",
    scheme: auth?.scheme ?? "bearer",
    region: auth?.region ?? "",
    tokenUrl: auth?.tokenUrl ?? "",
    urlVars: (spec.urlVars ?? []).map((v) => ({
      localId: newLocalId("uv"),
      name: v.name,
      label: v.label ?? "",
      example: v.example ?? "",
      secret: v.secret ?? false,
    })),
    headerVars: (spec.headerVars ?? []).map((v) => ({
      localId: newLocalId("hv"),
      header: v.header,
      label: v.label ?? "",
      example: v.example ?? "",
      secret: v.secret ?? false,
    })),
    defaultQuery: kvRowsFromRecord(spec.defaultQuery),
    extraHeaders: kvRowsFromRecord(spec.extraHeaders),
  };
}

function recordFromKvRows(rows: KVRow[]): Record<string, string> | undefined {
  const entries = rows
    .map((r) => [r.key.trim(), r.value] as const)
    .filter(([key]) => key.length > 0);
  return entries.length > 0 ? Object.fromEntries(entries) : undefined;
}

/**
 * Assemble the draft into a ConnectionSpec, or `null` when there is nothing to
 * configure — no auth chosen and no query/header/urlVar rows. `null` is a
 * meaningful wire value (the PUT contract treats it as "clear the spec"), so
 * this is what a fully-empty editor deliberately produces.
 */
export function connectionSpecFromDraft(draft: ConnectionSpecDraft): ProviderConnectionSpec | null {
  const auth =
    draft.authType === "none"
      ? undefined
      : {
          type: draft.authType,
          ...(draft.authType === "header"
            ? { header: draft.header.trim(), scheme: draft.scheme }
            : {}),
          ...(draft.authType === "sigv4" && draft.region.trim()
            ? { region: draft.region.trim() }
            : {}),
          ...(draft.authType === "oauth2" && draft.tokenUrl.trim()
            ? { tokenUrl: draft.tokenUrl.trim() }
            : {}),
        };
  const urlVars = draft.urlVars
    .filter((v) => v.name.trim().length > 0)
    .map((v) => ({
      name: v.name.trim(),
      ...(v.label.trim() ? { label: v.label.trim() } : {}),
      ...(v.example.trim() ? { example: v.example.trim() } : {}),
      ...(v.secret ? { secret: true } : {}),
    }));
  const headerVars = draft.headerVars
    .filter((v) => v.header.trim().length > 0)
    .map((v) => ({
      header: v.header.trim(),
      ...(v.label.trim() ? { label: v.label.trim() } : {}),
      ...(v.example.trim() ? { example: v.example.trim() } : {}),
      ...(v.secret ? { secret: true } : {}),
    }));
  const defaultQuery = recordFromKvRows(draft.defaultQuery);
  const extraHeaders = recordFromKvRows(draft.extraHeaders);

  const hasContent =
    auth != null ||
    urlVars.length > 0 ||
    headerVars.length > 0 ||
    defaultQuery != null ||
    extraHeaders != null;
  if (!hasContent) return null;

  return {
    specVersion: 1,
    ...(auth ? { auth } : {}),
    ...(urlVars.length > 0 ? { urlVars } : {}),
    ...(headerVars.length > 0 ? { headerVars } : {}),
    ...(defaultQuery ? { defaultQuery } : {}),
    ...(extraHeaders ? { extraHeaders } : {}),
  };
}

// Client-side mirror of the backend connectionSpec zod rules (llm/connectionSpec.ts)
// so a bad key, a blank header name, or a duplicate is reported inline instead of
// as an opaque 400 on save. Empty rows are ignored (they're dropped on assembly).
const HEADER_NAME_RE = /^[A-Za-z0-9-]{1,64}$/;
const QUERY_KEY_RE = /^[A-Za-z0-9._-]{1,64}$/;
const URL_VAR_NAME_RE = /^[A-Za-z0-9_]{1,64}$/;
const RESERVED_HEADERS = new Set([
  "authorization",
  "host",
  "content-length",
  "content-type",
  "connection",
]);

/** Returns an error message, or null when the draft is valid. */
export function validateConnectionSpecDraft(draft: ConnectionSpecDraft): string | null {
  if (draft.authType === "header" && !draft.header.trim()) {
    return "Custom-header auth needs a header name.";
  }
  const urlVarNames = new Set<string>();
  for (const v of draft.urlVars) {
    const name = v.name.trim();
    if (!name) continue;
    if (!URL_VAR_NAME_RE.test(name)) {
      return `URL variable "${name}" may use only letters, digits and underscores.`;
    }
    if (urlVarNames.has(name)) return `Duplicate URL variable "${name}".`;
    urlVarNames.add(name);
  }
  const headerVarNames = new Set<string>();
  for (const v of draft.headerVars) {
    const header = v.header.trim();
    if (!header) continue;
    if (!HEADER_NAME_RE.test(header) || RESERVED_HEADERS.has(header.toLowerCase())) {
      return `Header variable "${header}" is invalid or reserved.`;
    }
    if (headerVarNames.has(header.toLowerCase())) return `Duplicate header variable "${header}".`;
    headerVarNames.add(header.toLowerCase());
  }
  const queryKeys = new Set<string>();
  for (const r of draft.defaultQuery) {
    const key = r.key.trim();
    if (!key) continue;
    if (!QUERY_KEY_RE.test(key)) return `Query-param key "${key}" is not a valid key.`;
    if (queryKeys.has(key)) return `Duplicate query param "${key}".`;
    queryKeys.add(key);
  }
  const headerKeys = new Set<string>();
  for (const r of draft.extraHeaders) {
    const key = r.key.trim();
    if (!key) continue;
    if (!HEADER_NAME_RE.test(key) || RESERVED_HEADERS.has(key.toLowerCase())) {
      return `Header name "${key}" is invalid or reserved.`;
    }
    if (headerKeys.has(key.toLowerCase())) return `Duplicate header "${key}".`;
    headerKeys.add(key.toLowerCase());
  }
  return null;
}
