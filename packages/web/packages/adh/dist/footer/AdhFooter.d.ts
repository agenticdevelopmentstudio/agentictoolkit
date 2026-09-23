import type { MouseEvent, ReactNode } from 'react';
/** One entry of a {@link FooterMenu}: a real link, or a trigger for another popover. */
export type FooterMenuItem = {
    label: string;
    href: string;
    onSelect?: (event: MouseEvent<HTMLAnchorElement>) => void;
    prefetch?: boolean;
} | {
    label: string;
    popoverTarget: string;
    ariaLabel?: string;
};
export type FooterLink = 
/** A real navigation link. `onSelect` is optional progressive enhancement: it runs on a
 *  plain left-click and may `preventDefault()` to handle the click itself. The `href`
 *  stays in the server HTML either way, so the link is never dead without JS.
 *  `prefetch` is passed straight through to next/link — leave it `undefined` to keep
 *  Next's own default (host decides per-link; the toolkit takes no position). */
{
    label: string;
    href: string;
    onSelect?: (event: MouseEvent<HTMLAnchorElement>) => void;
    prefetch?: boolean;
    className?: string;
}
/** A native popover trigger: `popovertarget` opens the panel with NO client JS. Carries
 *  the `adh-footer__sites-trigger` class, which a host stylesheet may use to hide it in
 *  browsers without the Popover API — where it cannot degrade to anything. */
 | {
    label: string;
    popoverTarget: string;
    ariaLabel?: string;
    className?: string;
}
/** A popup menu of further entries — see {@link FooterMenu}. */
 | {
    label: string;
    menuId: string;
    items: FooterMenuItem[];
    ariaLabel?: string;
    className?: string;
};
export type AdhFooterProps = {
    links?: FooterLink[];
    copyright?: ReactNode;
    trailing?: ReactNode;
    /** Extra classes for the `<footer>`, for a host whose `trailing` needs the bar to make
     *  room — adh's SiteFooter reserves bitbag's resting slot with one. */
    className?: string;
};
/**
 * A footer popup menu, on the native Popover API: a `popovertarget` button and the panel it
 * opens, both in the server HTML. The panel is collapsed by `display:none` rather than left
 * out, so every link in it is crawlable — the footer is on every page of every site, and a
 * menu that only existed after hydration would take those links out of the index.
 *
 * Positioned against its own trigger with CSS anchor positioning where the browser has it
 * (the anchor name is derived from `id`, so any number of menus can share a bar); where it
 * does not, the host stylesheet's fallback parks it above the bar. Light-dismiss and Escape
 * are the platform's.
 */
export declare function FooterMenu({ id, label, items, ariaLabel, className, triggerClassName, }: {
    id: string;
    label: ReactNode;
    items: FooterMenuItem[];
    ariaLabel?: string;
    className?: string;
    triggerClassName?: string;
}): import("react").JSX.Element;
export declare function AdhFooter({ links, copyright, trailing, className }: AdhFooterProps): import("react").JSX.Element;
//# sourceMappingURL=AdhFooter.d.ts.map