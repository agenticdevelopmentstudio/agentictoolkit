import { featureTsup } from '../tsup.preset'

// One entry: unlike adh-billing (which splits ./parse, ./context, ./claim onto their
// own chunks so a route/shell that needs only one of them doesn't pull all five panes),
// nothing here has a caller that needs less than the whole feature. AdminFeature is
// always mounted behind a rail selection (the hub) or a page (admin.agenticdeveloperhub),
// never probed ahead of a render the way BillingGroup's context hook is — so there is no
// caller this split would serve, and one barrel is the simpler true shape.
export default featureTsup(['src/index.ts'])
