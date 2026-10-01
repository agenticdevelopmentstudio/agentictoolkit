import type { EnvOverrideSurface, ThemeAreasLoader } from './seams';
declare const TOP_ITEMS: readonly [{
    readonly id: "settings";
    readonly label: "Settings";
    readonly icon: import("react").JSX.Element;
}, {
    readonly id: "environment";
    readonly label: "Environment";
    readonly icon: import("react").JSX.Element;
}, {
    readonly id: "site-theme";
    readonly label: "Site theme";
    readonly icon: import("react").JSX.Element;
}, {
    readonly id: "chat-theme";
    readonly label: "Chat theme";
    readonly icon: import("react").JSX.Element;
}];
/**
 * Which root topics this build offers. Pure, and takes both facts as arguments, so the
 * production gate is directly assertable — the alternative (reading DEV_BUILD inline) can
 * only be checked by rendering the whole console, and a gate that is awkward to test is a
 * gate that silently stops holding.
 *
 * `devBuild` decides whether Site theme exists AT ALL: production has no site-theme editor,
 * admin or not (see {@link SiteThemeConsole} for why the door can't be the gate).
 * `hasChatTheme` follows the host's injected config.
 */
export declare function rootTopicsFor({ devBuild, hasChatTheme, }: {
    devBuild: boolean;
    hasChatTheme: boolean;
}): readonly ((typeof TOP_ITEMS)[number] & {
    dividerAfter?: boolean;
})[];
/**
 * The unified Debug console window — a backdrop-less {@link FloatingWindow} whose
 * {@link HierarchicalDetailView} stack hosts every debug topic (Settings / Environment /
 * Site theme / Chat theme), cascading or covered as the platform's hierarchical-view flag
 * decides. Fully controlled: the caller (the shared SiteMenu's "Debug Options" row) owns
 * `open` state and decides WHO may open the console — this component has no trigger of its
 * own and makes no runtime judgement about the viewer. The caller also INJECTS the two host
 * surfaces this package deliberately does not own: the environment-override store and the
 * theme taxonomy (see `./seams`).
 *
 * It does apply one gate of its own, and deliberately: which TOPICS this build contains.
 * The caller's door opens for a production admin, so a topic that must not exist in
 * production cannot be gated at the door — see {@link SiteThemeConsole}.
 *
 * The heavy work (theme editor + env fetch) lives in {@link DebugConsoleBody}, which
 * only mounts while the window is open (FloatingWindow returns `null` when closed).
 */
export type DebugConsoleWindowProps = {
    open: boolean;
    onClose: () => void;
    /** The host's environment-override store — see {@link EnvOverrideSurface}. */
    envOverride: EnvOverrideSurface;
    /** Loads the host's theme taxonomy + CSS editor — see {@link ThemeAreasLoader}. Passed
     *  straight through to the (env-gated) site-theme topic; never called here. */
    themeAreas: ThemeAreasLoader;
};
export declare function DebugConsoleWindow({ open, onClose, envOverride, themeAreas, }: DebugConsoleWindowProps): import("react").JSX.Element;
export {};
//# sourceMappingURL=DebugConsole.d.ts.map