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
  /** This provider has no test at all (`ProviderCatalogEntry.testable` is false), so nothing was
   *  sent. Not a failure and not a pass — a fact about the provider — and it is in the report
   *  because the alternative is what this replaced: a batch of four that quietly tested two and
   *  produced two answers, leaving the operator to work out which two and why. */
  skipped: boolean;
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
  /**
   * Created, and NOT yet usable: the document carries no secrets (see `integrationPortability`),
   * so each of these rows exists with an empty credential until somebody opens it and types one
   * in. `labels` is what to type — the provider's own words for it, as the form will ask.
   *
   * This is what `ExportedIntegration.needsSecrets` was written for. Until it was read here the
   * report said only "Imported integrations carry no credentials", a sentence printed whether or
   * not any of them needed one, naming neither the rows nor the credentials.
   */
  needsSecrets: { name: string; labels: string[] }[];
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
  /**
   * Remove these rows, and answer with the ones that actually went.
   *
   * The answer is the point. A batch settles per row, so "removed" and "asked to remove" are
   * different lists, and the caller's follow-up — untick what is gone, close the detail if it was
   * the open one — is about the first. Acting on the second unticks rows the server refused and
   * still has, which is a list saying the operator's selection succeeded when it did not.
   */
  remove: (rows: readonly MaskedProviderConfig[]) => Promise<MaskedProviderConfig[]>;
  exportRows: (rows: readonly MaskedProviderConfig[]) => Promise<void>;
  importFile: (file: File) => Promise<void>;
  /** Move these rows, and answer with the ones that actually moved — see {@link remove}. */
  transfer: (
    rows: readonly MaskedProviderConfig[],
    targetEcosystemId: string,
  ) => Promise<MaskedProviderConfig[]>;
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

  /**
   * Re-read the pane's list, and keep that read's failure inside the report.
   *
   * Every caller of these verbs fires them as `void bulk.remove(rows)` — there is no `await` to
   * attach a `.catch` to — so a `refresh()` that rejects inside a `try`/`finally` with no `catch`
   * leaves the process with an unhandled rejection, which in a browser is an error nobody sees
   * and in a test run is a failure attributed to whatever ran next. The writes themselves have
   * already settled by the time this runs; what is left to say is that the list on screen is the
   * one from before them, which is a sentence and not a crash.
   */
  const reread = useCallback(async () => {
    try {
      await refresh();
    } catch (e) {
      const said = errMsg(e, "The list couldn't be re-read.");
      setError((prev) => (prev ? `${prev} ${said}` : said));
    }
  }, [refresh]);

  const test = useCallback(
    async (rows: readonly MaskedProviderConfig[]) => {
      if (rows.length === 0) return;
      dismiss();
      setBusy("test");
      try {
        const answers = await Promise.all(
          rows.map(async (row): Promise<BulkTestRow> => {
            // The catalog's own answer, not a re-derivation from `authMethod`: `testable` is what
            // the backend's test route dispatches on. A row it says no to is reported as skipped
            // rather than spending a round trip to be told the provider has no validation
            // endpoint — and rather than being dropped before the report, which is what the
            // caller used to do and why a four-row batch could come back with two answers.
            if (!providerById.get(row.providerId)?.testable) {
              return { id: row.id, name: row.name, result: null, error: null, skipped: true };
            }
            try {
              const result = await integrationsApi.testProviderConfig(ecosystemId, row.id);
              return { id: row.id, name: row.name, result, error: null, skipped: false };
            } catch (e) {
              return {
                id: row.id,
                name: row.name,
                result: null,
                error: errMsg(e, "That integration could not be reached."),
                skipped: false,
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
    [dismiss, ecosystemId, onChanged, providerById],
  );

  const remove = useCallback(
    async (rows: readonly MaskedProviderConfig[]): Promise<MaskedProviderConfig[]> => {
      if (rows.length === 0) return [];
      dismiss();
      setBusy("remove");
      try {
        const outcomes = await Promise.all(
          rows.map(async (row) => {
            try {
              await integrationsApi.deleteProviderConfigById(ecosystemId, row.id);
              return { row, error: null as string | null };
            } catch (e) {
              return { row, error: `${row.name}: ${errMsg(e, "couldn't be removed.")}` };
            }
          }),
        );
        const refused = outcomes.filter((o) => o.error !== null);
        if (refused.length > 0) setError(refused.map((o) => o.error).join(" "));
        // Unconditional, and after every delete has settled: even a partly refused batch has
        // removed rows the list is still showing.
        await reread();
        const removed = outcomes.filter((o) => o.error === null).map((o) => o.row);
        // Success-only, like every other verb here and like the prop's own contract: a host uses
        // `onChanged` to re-read a fact it derived from these rows, and a batch the server
        // refused in full changed no fact — re-reading after it just repaints the same answer
        // with more confidence.
        if (removed.length > 0) onChanged?.();
        return removed;
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, onChanged, reread],
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
              return { entry, name: entry.name, error: null as string | null };
            } catch (e) {
              return { entry, name: entry.name, error: errMsg(e, "couldn't be created.") };
            }
          }),
        );

        setImportReport({
          created: outcomes.filter((o) => o.error === null).map((o) => o.name),
          duplicates: split.duplicates,
          unknownProviders: split.unknownProviders,
          failed: outcomes
            // The predicate narrows the OUTCOME — `& { error: string }` — rather than naming a
            // different object with the same two fields. A predicate's type has to be assignable
            // to what it narrows, and `{ name; error }` is not an outcome (it has no `entry`), so
            // the declaration-only build refused it; `tsup` strips types and never looked.
            .filter((o): o is (typeof outcomes)[number] & { error: string } => o.error !== null)
            .map((o) => ({ name: o.name, error: o.error })),
          // Only the rows that were actually created, and only the ones that need anything: a
          // provider configured without a client secret exported an empty `needsSecrets` and must
          // not be listed as owing one.
          needsSecrets: outcomes
            .filter((o) => o.error === null && o.entry.needsSecrets.length > 0)
            .map((o) => ({ name: o.name, labels: o.entry.needsSecrets })),
        });

        if (outcomes.some((o) => o.error === null)) {
          await reread();
          onChanged?.();
        }
      } catch (e) {
        setError(errMsg(e, "That file couldn't be imported."));
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, existing, onChanged, providerById, reread],
  );

  const transfer = useCallback(
    async (
      rows: readonly MaskedProviderConfig[],
      targetEcosystemId: string,
    ): Promise<MaskedProviderConfig[]> => {
      if (rows.length === 0 || !targetEcosystemId) return [];
      dismiss();
      setBusy("transfer");
      try {
        const outcomes = await Promise.all(
          rows.map(async (row) => {
            try {
              const moved = await integrationsApi.transferProviderConfig(ecosystemId, row.id, {
                targetEcosystemId,
              });
              return { row, connections: moved.connections, error: null as string | null };
            } catch (e) {
              return {
                row,
                connections: 0,
                error: errMsg(e, "couldn't be transferred."),
              };
            }
          }),
        );
        const moved = outcomes.filter((o) => o.error === null);
        const refused = outcomes.filter((o) => o.error !== null);
        if (refused.length > 0)
          setError(refused.map((o) => `${o.row.name}: ${o.error}`).join(" "));
        if (moved.length > 0) {
          const connections = moved.reduce((n, o) => n + o.connections, 0);
          setTransferReport(
            `Transferred ${count(moved.length, "integration")}` +
              (connections > 0 ? `, with ${count(connections, "connected account")}.` : "."),
          );
          // The rows have LEFT this ecosystem, so the pane's list and anything derived from it
          // are both wrong until they are re-read.
          await reread();
          onChanged?.();
        }
        return moved.map((o) => o.row);
      } finally {
        setBusy(null);
      }
    },
    [dismiss, ecosystemId, onChanged, reread],
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
