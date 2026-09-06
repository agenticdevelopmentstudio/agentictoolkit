import { providerConnFromIntegrations, type ProviderConn } from "@agentic-toolkit/deploy-platform/conn";
import { enumerateDeployProjectsFrom, type DeployEnumeration } from "@agentic-toolkit/deploy-platform/enumerate";
import type { StatusConfig } from "../config/port";
import type { Storage } from "../storage/ports";

// The storage-boundary replacements for `providerConnFromConfig(db)` and
// `enumerateDeployProjectsVerified(db)` (`@agentic-toolkit/deploy-platform/conn` and
// `/enumerate`) — both DB-based helpers the deploy-platform package still ships for
// its OWN Db-holding consumers, but which status-server may no longer call now that
// `db` does not leave `src/libsql/`. Every remaining site that needs a provider
// connection or a live enumeration goes through one of these two instead.

/** The active integration rows plus the credential lookup, assembled the same way
 *  `providerConnFromConfig` used to read them from the DB directly — except that the
 *  row's `tokenEnvVar` is resolved through the config port (`config.secrets`): the host
 *  decides what a credential name means; this package never reads the environment. */
export async function providerConn(storage: Storage, config: StatusConfig): Promise<ProviderConn> {
  const active = (await storage.config.listIntegrations()).filter((i) => i.isActive);
  return providerConnFromIntegrations(active, (name) => config.secrets[name]);
}

/** `enumerateDeployProjectsVerified(db)`'s replacement — same result shape, built
 *  from the storage port instead of a live `deployProjectMeta` table read. */
export async function enumerateDeployProjects(storage: Storage, config: StatusConfig): Promise<DeployEnumeration> {
  return enumerateDeployProjectsFrom({
    conn: await providerConn(storage, config),
    projectMeta: await storage.deploy.listProjectMeta(),
  });
}
