// The export DOCUMENT, pinned as its own unit — it is a pure function from rows to a string and
// back, so none of this needs a DOM, a save dialog or a file picker to be true.
//
// Two facts here are the expensive ones and both are asserted directly rather than implied:
// a secret never reaches the file, and "already got it" is the provider AND the name.
import { describe, expect, it } from 'vitest';
import type { MaskedProviderConfig, ProviderCatalogEntry } from '@agentic-toolkit/data/integrations';

import {
  EXPORT_KIND,
  buildExport,
  exportFilename,
  identityOf,
  parseExport,
  serializeExport,
  splitImport,
  type IntegrationsExport,
} from './integrationPortability';

const cfg = (patch: Partial<MaskedProviderConfig>): MaskedProviderConfig => ({
  id: 'uuid-1',
  ecosystemId: 'eco-1',
  providerId: 'github-app',
  name: 'GitHub (acme)',
  rdid: null,
  config: { clientId: '123456', scopes: ['repo', 'read:org'] },
  hasSecret: true,
  ...patch,
});

const provider = (patch: Partial<ProviderCatalogEntry>): ProviderCatalogEntry =>
  ({
    providerId: 'github-app',
    displayName: 'GitHub',
    subtitle: 'Code',
    description: '',
    links: [],
    authMethod: 'github_app',
    serviceTypes: [],
    capabilities: [],
    defaultPollIntervalMs: 0,
    ...patch,
  }) as ProviderCatalogEntry;

const catalog = (...entries: ProviderCatalogEntry[]) =>
  new Map(entries.map((p) => [p.providerId, p]));

const AT = new Date('2026-09-12T10:00:00.000Z');

describe('buildExport', () => {
  it('carries the config as the editor sees it', () => {
    const doc = buildExport([cfg({})], catalog(provider({})), AT);

    expect(doc.kind).toBe(EXPORT_KIND);
    expect(doc.version).toBe(1);
    expect(doc.exportedAt).toBe('2026-09-12T10:00:00.000Z');
    expect(doc.integrations).toHaveLength(1);
    const only = doc.integrations[0]!;
    expect(only.providerId).toBe('github-app');
    expect(only.name).toBe('GitHub (acme)');
    expect(only.input.clientId).toBe('123456');
    // Space-joined, because that is the draft shape the import writes straight back.
    expect(only.input.scopes).toBe('repo read:org');
  });

  it('NEVER puts a secret in the file', () => {
    // The API has never echoed one back, so there is nothing here to leak — which is exactly why
    // this is worth pinning: the day someone adds a reveal endpoint, this is the test that says
    // the export was not the place to spend it.
    const text = serializeExport(buildExport([cfg({})], catalog(provider({})), AT));

    expect(text).not.toContain('clientSecret":"');
    expect(JSON.parse(text).integrations[0].input.clientSecret).toBe('');
  });

  it('names the secret the operator will have to re-enter', () => {
    const doc = buildExport([cfg({})], catalog(provider({})), AT);
    // The form's own word for it, not "secret" — a GitHub App operator is looking for a box
    // labelled "Private key".
    expect(doc.integrations[0]!.needsSecrets).toEqual(['Private key']);
  });

  it('names every declared secret field for a provider that has several', () => {
    const twilio = provider({
      providerId: 'twilio',
      authMethod: 'api_key',
      configFields: [
        { key: 'accountSid', label: 'Account SID', secret: false, required: true },
        { key: 'authToken', label: 'Auth token', secret: true, required: true },
      ],
    });
    const doc = buildExport(
      [cfg({ providerId: 'twilio', name: 'Twilio', config: { accountSid: 'AC1' } })],
      catalog(twilio),
      AT,
    );

    expect(doc.integrations[0]!.needsSecrets).toEqual(['Auth token']);
    // And the non-secret half of the same provider DOES travel — otherwise the import is a list
    // of names and the operator retypes the whole form.
    expect(doc.integrations[0]!.input.fields.accountSid).toBe('AC1');
  });

  it('asks for nothing back when the integration stored no secret', () => {
    // `hasSecret: false` is a configured integration that simply has no secret, and telling its
    // importer to go and find one sends them looking for something that never existed.
    const doc = buildExport([cfg({ hasSecret: false })], catalog(provider({})), AT);
    expect(doc.integrations[0]!.needsSecrets).toEqual([]);
  });

  it('still exports a row whose provider this catalog no longer has', () => {
    // Refusing would lose the one copy of it the operator was trying to keep.
    const doc = buildExport([cfg({ providerId: 'retired' })], catalog(), AT);
    expect(doc.integrations[0]!.providerId).toBe('retired');
    expect(doc.integrations[0]!.input.clientId).toBe('123456');
  });
});

describe('exportFilename', () => {
  it('dates the file', () => {
    expect(exportFilename(AT)).toBe('integrations-2026-09-12.json');
  });
});

describe('parseExport', () => {
  const round = (doc: IntegrationsExport) => parseExport(serializeExport(doc));

  it('reads back exactly what was written', () => {
    const doc = buildExport([cfg({})], catalog(provider({})), AT);
    expect(round(doc)).toEqual(doc);
  });

  it('refuses a file that is not JSON, by saying so', () => {
    // What an operator gets when they pick an HTML page by mistake. "Unexpected token <" tells
    // them nothing about which of the three things they did wrong.
    expect(() => parseExport('<!doctype html>')).toThrow("That file isn't JSON.");
  });

  it('refuses valid JSON that is some other document', () => {
    expect(() => parseExport('{"name":"my-app","version":"1.0.0"}')).toThrow(
      "That file isn't an integrations export.",
    );
  });

  it('refuses a format it does not know rather than guessing at it', () => {
    expect(() => parseExport(JSON.stringify({ kind: EXPORT_KIND, version: 99, integrations: [] }))).toThrow(
      /newer version of the console/,
    );
  });

  it('refuses a document whose integrations are unreadable', () => {
    expect(() =>
      parseExport(JSON.stringify({ kind: EXPORT_KIND, version: 1, integrations: [{ name: 'x' }] })),
    ).toThrow(/damaged/);
  });
});

describe('splitImport', () => {
  const doc = (...names: [string, string][]): IntegrationsExport => ({
    kind: EXPORT_KIND,
    version: 1,
    exportedAt: AT.toISOString(),
    integrations: names.map(([providerId, name]) => ({
      providerId,
      name,
      input: { ...buildExport([cfg({ providerId, name })], catalog(), AT).integrations[0]!.input },
      needsSecrets: [],
    })),
  });

  const known = new Set(['github-app', 'vercel']);

  it('creates what is not here yet', () => {
    const split = splitImport(doc(['github-app', 'GitHub (acme)']), [], known);
    expect(split.toCreate.map((e) => e.name)).toEqual(['GitHub (acme)']);
    expect(split.duplicates).toEqual([]);
  });

  it('ignores an integration already here, and reports it', () => {
    const split = splitImport(
      doc(['github-app', 'GitHub (acme)'], ['vercel', 'Vercel']),
      [cfg({ providerId: 'github-app', name: 'GitHub (acme)' })],
      known,
    );
    expect(split.duplicates.map((e) => e.name)).toEqual(['GitHub (acme)']);
    expect(split.toCreate.map((e) => e.name)).toEqual(['Vercel']);
  });

  it('reads a name that differs only in case or padding as the same integration', () => {
    const split = splitImport(
      doc(['github-app', '  github (ACME) ']),
      [cfg({ providerId: 'github-app', name: 'GitHub (acme)' })],
      known,
    );
    expect(split.toCreate).toEqual([]);
    expect(split.duplicates).toHaveLength(1);
  });

  it('does NOT treat a second instance of the same provider as a duplicate', () => {
    // Multiple instances of one provider are the whole reason a config carries a name, so the
    // provider alone is not identity. Getting this wrong silently drops the second GitHub org.
    const split = splitImport(
      doc(['github-app', 'GitHub (beta)']),
      [cfg({ providerId: 'github-app', name: 'GitHub (acme)' })],
      known,
    );
    expect(split.toCreate.map((e) => e.name)).toEqual(['GitHub (beta)']);
  });

  it('creates a document that repeats itself exactly once', () => {
    const split = splitImport(doc(['vercel', 'Vercel'], ['vercel', 'Vercel']), [], known);
    expect(split.toCreate).toHaveLength(1);
    expect(split.duplicates).toHaveLength(1);
  });

  it('separates a provider this deployment does not have', () => {
    // Otherwise the create fails and the operator is handed whatever the API says about a client
    // id for a provider it has never heard of.
    const split = splitImport(doc(['retired', 'Old thing']), [], known);
    expect(split.toCreate).toEqual([]);
    expect(split.unknownProviders.map((e) => e.name)).toEqual(['Old thing']);
  });
});

describe('identityOf', () => {
  it('is the provider AND the name', () => {
    expect(identityOf('github-app', ' GitHub (Acme) ')).toBe(identityOf('github-app', 'github (acme)'));
    expect(identityOf('github-app', 'A')).not.toBe(identityOf('vercel', 'A'));
  });
});
