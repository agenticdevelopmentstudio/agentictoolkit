import '@agentic-toolkit/bitbag/css/bitbag-dock.css';
/**
 * bitbag in the footer — the SAME fixture fishlamp.com runs, not a second chat
 * that merely shares his name: his face riding above his chat, his mood and gaze
 * following the conversation, his own scripted voice, on fishlamp's skin, parked
 * where fishlamp parks him.
 *
 * That sentence was aspirational for months and this comment asserted it anyway.
 * fishlamp ran a VENDORED FORK of the dock and evolved it, the toolkit evolved
 * separately, and the two drifted down to bitbag's eye colour and the shape of
 * his send button — while every reader of this file was told they couldn't. One
 * component mounted in both places is what makes the claim true; fishlamp's
 * version is the one that was folded back into `BitbagDock`, because fishlamp is
 * where the design was drawn. Don't re-fork him: change the toolkit.
 *
 * Loaded lazily + CLIENT-ONLY by FooterChat (`next/dynamic`, `ssr: false`) — so it
 * never server-renders (the transcript stamps `new Date()` + a random id per
 * message, and the avatar runs gsap timelines, neither of which survives
 * hydration) and its JS + CSS stay out of every site's first-paint bundle,
 * fetched only when the footer mounts on the client.
 *
 * No `backend` prop: he speaks his built-in scripted voice.
 *
 * `rest="avatar"` is the one way he differs from fishlamp's mounting, and it is a
 * difference of CONTEXT, not a fork: here he shares the bottom edge with the footer
 * bar, so at rest he is his face alone, in the slot the bar keeps just left of its
 * Legal menu (of Terms, where a browser without popovers shows the inline pair), and
 * when he is tapped he grows back to the centre with his chat opening under him (the
 * slot is adh-site.css's; `useFooterRestOffset` measures where it is and writes it on
 * this dock). His resting entry line used to lie across the middle of the bar, over its
 * links, and made every page reserve 6rem for it.
 *
 * PORTALLED TO `document.body`, not rendered in place. The dock positions itself
 * (`position: fixed`, bottom-centred, riding the keyboard — see bitbag-dock.css),
 * so it has no reason to sit inside the footer's DOM, and one strong reason not
 * to: `.adh-footer` is `position: sticky` WITH a `z-index`, which makes it a
 * stacking context that its descendants cannot paint out of. Left inside it, the
 * dock would be trapped under the header at z-index 50 no matter what it asked
 * for, and the scrim that dims the page behind an engaged bitbag would stop
 * politely short of the header. Portalled to the body its `z-index` means what it
 * says (`.adh-footer__chat` raises it to 51, clearing the header), and the footer
 * keeps its own stacking to itself.
 *
 * The `theme` DOES come in as a prop, because it has to: bitbag emits his own
 * scoped `<ThemeStyle>` inside the dock, so a host stylesheet scoped to the
 * wrapper sits on a farther ancestor and never wins (see chat-theme-store).
 * Unset — which is production everywhere — he keeps his shipping skin, the lamp.
 */
export default function FooterChatInner(): import("react").ReactPortal | null;
//# sourceMappingURL=FooterChatInner.d.ts.map