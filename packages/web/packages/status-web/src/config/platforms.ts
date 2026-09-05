// SEED-ONLY: these lists now live in the DB (deploy_integrations.config) and are
// read from there by the sync; db/config.ts seedIntegrations copies them in once.
// Nothing reads these at runtime anymore — edit the config (Platforms UI) instead.
// Worker script names (temporal sites are deployed as Workers, not Pages).
export const CF_WORKER_SCRIPTS = ["temporal-web", "temporal-landing", "temporal-admin"];

// Railway: single project with three environments. The `name` is the real
// Railway project name — rows are labelled "<project> <environment>" (e.g.
// "adh-backend production"), NOT the GitHub repo behind a deploy (which is a
// per-service detail, not the project, and reads as a made-up name).
export const RAILWAY_PROJECTS = [
  { id: "867c64ae-6f69-4d26-b4a6-2ecd06867ed3", name: "adh-backend" },
] as const;

// Vercel: one team token lists all projects; no per-project config needed.
