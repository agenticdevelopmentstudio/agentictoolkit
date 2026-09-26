import { type ComponentType, type ReactNode } from 'react';
import type { LandingContent } from './content';
/**
 * One node of a rich text value, as buildr writes it into a site's `landing.json`.
 *
 * A string is text. An element is `{ t, c }` — its tag and its children — and a link carries
 * its `href` besides. `link` is a route of the host app and `a` is anywhere else; which
 * component a `link` becomes is the SITE's fact, handed in as `options.link`, because the
 * JSON is content and must not know what router the site mounts it under.
 */
export type InlineNode = string | {
    t: 'b' | 'em' | 'code';
    c: InlineNode[];
} | {
    t: 'a' | 'link';
    href: string;
    c: InlineNode[];
};
export interface LandingDataOptions {
    /** What a `link` node renders as — `next/link`'s `Link` in the family. Absent: `<a>`. */
    link?: ComponentType<{
        href: string;
        children?: ReactNode;
    }>;
}
/**
 * A site's `landing.json`, as the `LandingContent` the deck mounts.
 *
 * The copy used to arrive as a generated `.tsx` of JSX fragments, which made a site's words a
 * module only a bundler could read. It is data now — the same tree whether it is imported from
 * the site's own `src/` or fetched from a server later — and this is the one place that turns
 * it back into ReactNodes.
 *
 * Only two shapes in the tree are not already the content's own: a rich text value, written
 * `{ "$inline": [nodes] }`, becomes a fragment; and any key starting with `$` is the
 * generator's own bookkeeping (the `$generated` banner) and is dropped. Every other value
 * passes through as it is, so the JSON's field names ARE `LandingContent`'s and there is no
 * second schema here to drift from the first.
 *
 * Children are spread as arguments rather than passed as an array, which is what lets React
 * render a static list without asking for keys.
 */
export declare function landingFromData(data: object, options?: LandingDataOptions): LandingContent;
//# sourceMappingURL=fromData.d.ts.map