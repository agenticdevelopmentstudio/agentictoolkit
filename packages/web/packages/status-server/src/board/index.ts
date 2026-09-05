export * from "./types";
export { boardTargetKey, parseBoardTarget } from "./target-key";
export { deriveBoard } from "./derive";
export { deriveActivity, indicatorFor, ISSUE_VERB, pageActivity } from "./derive-activity";
export { createActivityPageReader, ownedDeploysWhere, readActivityPage, readBoardFacts, readRoster } from "./facts";
// The ownership rule, for the surfaces OUTSIDE the fold that must agree with it about
// which deploy targets exist — the webhook door, the Deployments tab, the live-host stamp.
export {
  entryIdentity, matchRosterEntry, ownedDeployTarget, ownsDeployProject,
  rosterDeployProjects, rosterTargets,
} from "./ownership";
export type { DeployIdentity } from "./ownership";
export { reconcileBoardLedger } from "./reconcile";
// The platform-health target spelling and its inverse — so no reader outside the fold has
// to know that the string starts with "platform-health|".
export { errorsTarget, parseErrorsTarget, parsePlatformHealthTarget, platformHealthTarget } from "./derive-problems";
