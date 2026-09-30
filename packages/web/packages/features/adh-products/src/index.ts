// @agentic-toolkit/adh-products — the Products feature.
//
// A Product is what adh calls an ecosystem, and this package is that presentation:
// @agentic-toolkit/ecosystems's EcosystemsFeature in `listFirst` mode with Product labels, adh's
// own topic rail on it, and the pane each of those topics opens. The ecosystem MACHINERY stays
// where it is — mechanism, mountable by a host that has never heard of adh. This is the adh
// vocabulary laid over it.
//
// It exists because agenticdeveloperproducts.com mounts the feature at /home now, and the hub
// mounts it at /<workspace>/products. Two hosts building "Products" from two copies of one topic
// switch is two features with one name; the switch lives here and each host passes only what is
// genuinely its own — where it is mounted, and the seams it can answer.
//
// Why the `adh-` prefix: it composes @agentic-toolkit/adh-ecosystem-panes and adh's help store,
// both VOCABULARY, which mechanism may not import (scripts/check_boundaries.py). See
// `comment:tier` in package.json.

export { ProductsFeature, PRODUCT_TOPIC_CONFIGS, type ProductsFeatureProps } from "./ProductsFeature";

// The Applications row — the applications, a divider, then Settings (the ecosystem's client auth).
// Exported because the hub's workspace rail draws the same row, scoped to its default ecosystem.
export { ApplicationsGroup } from "./ApplicationsGroup";

// The rail as data. Re-exported for convenience, but a SERVER-safe consumer must import it from
// `@agentic-toolkit/adh-products/topics` instead — this barrel is `use client` end to end.
export { PRODUCT_TOPICS, HOST_RENDERED_TOPIC_IDS, type ProductTopicId } from "./topics";
