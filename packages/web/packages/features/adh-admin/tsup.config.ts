import { featureTsup } from '../tsup.preset'

// Three entries, split by WHO IMPORTS WHAT (the same reasoning as adh-billing's config).
//
// The barrel is the twelve panes plus the AdminFeature mount. A static import of ANY barrel export
// pulls that whole bundled module, so the admin site's AdminShell — which needs only the section
// names and icons to draw its rail — once loaded every pane, react-query and all the editors into
// the shell chunk of every admin page. `./topics` (src/adminTopics.ts: the list and the id guard,
// no panes) is what a rail or a route reads instead. `./query` (the AdminQueryProvider) is for a
// host layout that wraps panes it does not itself import.
export default featureTsup(['src/index.ts', 'src/adminTopics.ts', 'src/AdminQueryProvider.tsx'])
