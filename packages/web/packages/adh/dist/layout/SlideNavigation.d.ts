export type SlideDirection = 'forward' | 'back';
/** The one attribute the stylesheet keys the slide on (adh-site.css, "SLIDE NAVIGATION"). Set
 *  on <html> for the life of one transition and removed after, so an ordinary navigation —
 *  which never goes through here — keeps the browser's default of no animation at all. */
export declare const SLIDE_ATTR = "data-adh-slide";
/**
 * Whether a slide can run here: the View Transitions API exists, and the reader has not asked
 * for less motion — in the Appearance settings first, then the OS. Where it cannot, callers
 * navigate exactly as they did before.
 *
 * The Appearance choice has to be honoured HERE, not left to the stylesheet. It lands on
 * <html> as `data-reduce-motion` — "on", "off", or absent for "auto", which follows the OS —
 * and the themes' accessibility rules that zero animation durations under it select `*`,
 * `*::before` and `*::after`, none of which matches a `::view-transition-*` pseudo-element. So
 * a reader who chose "on" still got the slide, and one who chose "off" (keep motion even
 * though the OS asks for less) never did.
 */
export declare function canSlide(): boolean;
/**
 * Navigate to `href` with the page sliding in from the right, as if pushed onto a stack — and
 * remember the pair, so Back (the browser's button, or a swipe; see `SwipeHistory`) slides it
 * off again to the page it came from. It is an ordinary `router.push`: the history entry, the
 * URL and the destination are exactly what the plain link would have produced. The slide is
 * decoration.
 *
 * Returns whether it took the navigation. `false` — no API, reduced motion, no router
 * registered, or already there — means the caller should let its link navigate as usual, so
 * the call is always safe to make from a link's click handler before `preventDefault()`.
 */
export declare function slideNavigate(href: string): boolean;
/**
 * Render-free. Tracks the committed path for `slideNavigate`, and plays a slide when the
 * browser's history steps between two pages that were slid between.
 *
 * WHICH WAY comes from the history POSITION, never from the pair. The pair only says the two
 * pages were slid between; a step over it can run either way. Reading the direction off the
 * pair's orientation played the PUSH animation on Back in the avatar menu: slide /acme →
 * /acme/profile (the Profile row), go home with the Home row (a plain push, so history reads
 * /acme, /acme/profile, /acme), press Back — /acme to /acme/profile is the pair's own
 * orientation, so it slid "forward" while the reader went back, and Forward onto that plain
 * /acme entry played the pop. `navigation.currentEntry` is already the destination by the time
 * `popstate` fires, so its index against the committed page's says which way the reader went.
 * No Navigation API ⇒ no position ⇒ no slide, rather than a guess.
 *
 * WHY BACK HAS TO BE HELD FOR A FRAME: a view transition photographs the OLD page at the next
 * frame after it starts. On Back the app router starts rendering the destination the moment
 * `popstate` fires, and for a cached route it can commit before that frame — the "old" photo
 * would already be the new page, and the slide would move a page over a copy of itself. So
 * this listener runs first (capture, on the target — it precedes every bubbling `popstate`
 * listener, the router's included), holds the event back, and re-dispatches it from inside the
 * transition's update callback, once the old page is safely captured. Only a step between a
 * slid pair is held; every other popstate — including the unsaved-changes guard's same-URL
 * sentinel — passes straight through untouched.
 *
 * A HELD STEP CAN GO STALE before that callback runs. A second Back or Forward inside those
 * frames (key repeat, a mouse's back button double-firing, a slow device) is usually not held
 * itself — a Forward straight back to the page still on screen is no step at all from the
 * committed page's point of view — so it reaches the router first. Replaying the first step's
 * captured state after it handed Next the first destination's tree under the URL the second
 * step left in the address bar; Next wrote that tree into the entry, and the slide sat out the
 * whole render timeout waiting for a path that never committed. So every traversal is counted,
 * a held one is dropped at release if another arrived meanwhile or the address bar has moved
 * on, and a live one replays the CURRENT entry's `history.state` rather than the copy captured
 * with the event. A new traversal also ends any slide still waiting for its page to commit:
 * that page is no longer where history is going, and the wait would only freeze the screen
 * until it timed out.
 */
export declare function SlideTransitions(): null;
//# sourceMappingURL=SlideNavigation.d.ts.map