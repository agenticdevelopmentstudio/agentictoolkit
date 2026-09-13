"use client";

/**
 * WHAT THE BUTTON BAR DOES TO A SET OF ROWS.
 *
 * The pane's bar acts on a SELECTION — one row, or four ticked ones — and every one of its
 * verbs is the same shape: fire a request per row, keep going when one of them refuses, and end
 * with something the operator can read. That shape is here rather than in the pane because the
 * pane is already the largest file in this package and because none of this needs a rail, a
 * draft, or a URL to be true.
 *
 * ONE ROW FAILING MUST NOT CANCEL THE REST. Every verb settles per row and reports per row: a
 * GitHub App whose private key was revoked should not stop the other three from being tested,
 * and a duplicate name should not abandon the rest of an import halfway through. `Promise.all`
 * over already-caught promises, never over raw ones.
 *
 * NOTHING HERE OPENS A DIALOG. The confirmations (Remove, Transfer) are the pane's `AlertModal`s
 * and the file picker is the pane's `<input type="file">`; this hook is handed the rows, or the
 * `File`, after the operator has already said yes. That keeps it callable from a test with no
 * DOM beyond the one `saveTextFile` needs.
 */

import { useCallback, useState } from "react";
import { readTextFile, saveTextFile } from "@agenticdevelopertoolkit/ui/lib/file-exchange";
import {
  integrationsApi,
  type IntegrationTestResult,
  type MaskedProviderConfig,
  type ProviderCatalogEntry,
} from "@agentic-toolkit/data/integrations";
import { errMsg } from "@agentic-toolkit/data";

import { intToCreateBody } from "./IntegrationDetail";
import {
  buildExport,
  exportFilename,
  parseExport,
  serializeExport,
  splitImport,
  type ExportedIntegration,
} from "./integrationPortability";

/** One row's answer from a bulk Test. `id` is the config's uuid — this list is a report and never
 *  a thing to select from, so it wants a React key rather than an address.
 *
 *  `result` and `error` are the same distinction the single Test draws: a provider that refused
 *  has ANSWERED (`result.ok === false`), and `error` is the other thing — the request could not
 *  be made at all. */
export interface BulkTestRow {
  id: string;
  name: string;
  result: IntegrationTestResult | null;
  error: string | null;
}

/** What an import did, in the shape the operator asked to be shown at the end of one. */
export interface ImportReport {
  created: string[];
  /** Already here by name+provider, skipped. The user asked for this list by name. */
  duplicates: ExportedIntegration[];
  /** Their provider is not in this deployment's catalog, so nothing could be created. */
  unknownProviders: ExportedIntegration[];
  /** Accepted by the split and then refused by the API — a name collision, a rejected field. */
  failed: { name: string; error: string }[];
}

/** Which verb is in flight, or null. One value rather than a boolean per verb: the bar disables
 *  as a whole while any of them runs, and two at once is a state nothing here can produce. */
export type BulkVerb = "test" | "remove" | "export" | "import" | "transfer";

export interface IntegrationBulkActions {
  busy: BulkVerb | null;
  /** A failure that was not about one row — a file that would not parse, a save that threw. */
  error: string | null;
  /** The last bulk Test's answers, newest run replacing the previous one. */
  testRows: BulkTestRow[] | null;
  importReport: ImportReport | null;
  /** What a transfer moved, as one sentence. */
  transferReport: string | null;
  /** Clear every report and error — the bar's own dismiss, and what a changed selection calls. */
  dismiss: () => void;
  test: (rows: readonly MaskedProviderConfig[]) => Promise<void>;
  remove: (rows: readonly MaskedProviderConfig[]) => Promise<void>;
  exportRows: (rows: readonly MaskedProviderConfig[]) => Promise<void>;
  importFile: (file: File) => Promise<void>;
  transfer: (
    rows: readonly MaskedProviderConfig[],
    targetEcosystemId: string,
  ) => Promise<void>;
}

export function useIntegrationBulkActions({
  ecosystemId,
  providerById,
  existing,
  refresh,
  onChanged,
}: {
  ecosystemId: string;
  /** The catalog, by provider id — what an export names its secrets from and what an import
   *  turns an entry back into a create body with. */
  providerById: ReadonlyMap<string, ProviderCatalogEntry>;
  /** The rows already in this ecosystem, for the import's duplicate test. */
  existing: readonly MaskedProviderConfig[];
  /** Re-read the pane's list — every verb that writes calls it. */
  refresh: () => void | Promise<unknown>;
  /** Something about this ecosystem's integrations changed; see `IntegrationsPane.onChanged`. */
  onChanged?: () => void;
}): IntegrationBulkActions {
  const [busy, setBusy] = useState<BulkVerb | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [testRows, setTestRows] = useState<BulkTestRow[] | null>(null);
  const [importReport, setImportReport] = useState<ImportReport | null>(null);
  const [transferReport, setTransferReport] = useState<string | null>(null);

  const dismiss = useCallback(() => {
    setError(null);
    setTestRows(null);
    setImportReport(null);
    setTransferReport(null);
  }, []);

  const test = useCallback(
    async (rows: readonly MaskedProviderConfig[]) => {
      if (rows.length === 0) return;
      dismiss();
      setBusy("test");
      try {
        const answers = await Promise.all(
          rows.map(async (row): Promise<BulkTestRow> => {
            try {
              const result = await integrationsApi.testProviderConfig(ecosystemId, row.id);
              return { id: row.id, name: row.name, result, error: null };
            } catch (e) {
              return {
                id: row.id,
                name: row.name,
                result: null,
                error: errMsg(e, "That integration could not be reached."),
              };
            }
          }),
        );
        setTestRows(answers);
        // Testing a GitHub App is also what CREATES its connection rows, so a run that adopted
        // anything has changed what a repository picker would find. One notification for the
        // whole batch: the host re-reads a list, and re-reading it four times is four of the
        // same answer.
        if (answers.some((a) => a.result?.adopted)) onChanged?.();
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, onChanged],
  );

  const remove = useCallback(
    async (rows: readonly MaskedProviderConfig[]) => {
      if (rows.length === 0) return;
      dismiss();
      setBusy("remove");
      try {
        const failures = await Promise.all(
          rows.map(async (row) => {
            try {
              await integrationsApi.deleteProviderConfigById(ecosystemId, row.id);
              return null;
            } catch (e) {
              return `${row.name}: ${errMsg(e, "couldn't be removed.")}`;
            }
          }),
        );
        const refused = failures.filter((f): f is string => f !== null);
        if (refused.length > 0) setError(refused.join(" "));
        // Unconditional, and after every delete has settled: even a partly refused batch has
        // removed rows the list is still showing.
        await refresh();
        onChanged?.();
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, onChanged, refresh],
  );

  const exportRows = useCallback(
    async (rows: readonly MaskedProviderConfig[]) => {
      if (rows.length === 0) return;
      dismiss();
      setBusy("export");
      try {
        const doc = buildExport(rows, providerById);
        await saveTextFile({
          text: serializeExport(doc),
          filename: exportFilename(),
          description: "Integrations export",
        });
      } catch (e) {
        setError(errMsg(e, "That export couldn't be saved."));
      } finally {
        setBusy(null);
      }
    },
    [dismiss, providerById],
  );

  const importFile = useCallback(
    async (file: File) => {
      dismiss();
      setBusy("import");
      try {
        // The read and the parse both throw sentences meant for an operator — see
        // `parseExport` — so one catch around both, and no rewriting of what they said.
        const doc = parseExport(await readTextFile(file));
        const split = splitImport(doc, existing, new Set(providerById.keys()));

        const outcomes = await Promise.all(
          split.toCreate.map(async (entry) => {
            try {
              await integrationsApi.createProviderConfig(
                ecosystemId,
                intToCreateBody(entry.input, providerById.get(entry.providerId)),
              );
              return { name: entry.name, error: null as string | null };
            } catch (e) {
              return { name: entry.name, error: errMsg(e, "couldn't be created.") };
            }
          }),
        );

        setImportReport({
          created: outcomes.filter((o) => o.error === null).map((o) => o.name),
          duplicates: split.duplicates,
          unknownProviders: split.unknownProviders,
          failed: outcomes
            .filter((o): o is { name: string; error: string } => o.error !== null)
            .map((o) => ({ name: o.name, error: o.error })),
        });

        if (outcomes.some((o) => o.error === null)) {
          await refresh();
          onChanged?.();
        }
      } catch (e) {
        setError(errMsg(e, "That file couldn't be imported."));
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, existing, onChanged, providerById, refresh],
  );

  const transfer = useCallback(
    async (rows: readonly MaskedProviderConfig[], targetEcosystemId: string) => {
      if (rows.length === 0 || !targetEcosystemId) return;
      dismiss();
      setBusy("transfer");
      try {
        const outcomes = await Promise.all(
          rows.map(async (row) => {
            try {
              const moved = await integrationsApi.transferProviderConfig(ecosystemId, row.id, {
                targetEcosystemId,
              });
              return { name: row.name, connections: moved.connections, error: null as string | null };
            } catch (e) {
              return {
                name: row.name,
                connections: 0,
                error: errMsg(e, "couldn't be transferred."),
              };
            }
          }),
        );
        const moved = outcomes.filter((o) => o.error === null);
        const refused = outcomes.filter((o) => o.error !== null);
        if (refused.length > 0) setError(refused.map((o) => `${o.name}: ${o.error}`).join(" "));
        if (moved.length > 0) {
          const connections = moved.reduce((n, o) => n + o.connections, 0);
          setTransferReport(
            `Transferred ${count(moved.length, "integration")}` +
              (connections > 0 ? `, with ${count(connections, "connected account")}.` : "."),
          );
          // The rows have LEFT this ecosystem, so the pane's list and anything derived from it
          // are both wrong until they are re-read.
          await refresh();
          onChanged?.();
        }
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, onChanged, refresh],
  );

  return {
    busy,
    error,
    testRows,
    importReport,
    transferReport,
    dismiss,
    test,
    remove,
    exportRows,
    importFile,
    transfer,
  };
}

/** "1 integration" / "4 integrations". Naive plural, and every noun it is given here takes it. */
function count(n: number, noun: string): string {
  return `${n} ${noun}${n === 1 ? "" : "s"}`;
}
