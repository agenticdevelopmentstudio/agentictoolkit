//
//  ContributedViews.swift
//  AgenticToolkit
//

import Foundation

/// One `contributes.viewsContainers` entry, recorded rather than rendered.
public struct ContributedViewContainer: Sendable, Equatable {
    public let extensionIdentifier: String
    /// `activitybar`, `panel`, … — the `viewsContainers` key.
    public let location: String
    public let containerID: String
    public let title: String
    /// Raw, as declared, and deliberately unresolved: nothing renders a
    /// container (Ruling FD), so a container's `$(codicon)` is carried for a
    /// future host rather than looked up here — which is why
    /// `CodiconSymbols.table` covers names this builder never asks for.
    public let icon: String?
    public let when: String?

    public init(
        extensionIdentifier: String,
        location: String,
        containerID: String,
        title: String,
        icon: String?,
        when: String?
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.location = location
        self.containerID = containerID
        self.title = title
        self.icon = icon
        self.when = when
    }
}

/// One `contributes.views` entry, resolved as far as a host without an
/// extension host can resolve it.
public struct ContributedView: Sendable, Equatable {
    public let extensionIdentifier: String
    /// The raw VS Code view id — what a future host's
    /// `registerTreeDataProvider(viewId:)` will arrive with.
    public let viewID: String
    /// `extension.<identifier>.<viewID>`.
    public let registryID: String
    public let targetContainerID: String
    public let name: String
    /// `.tree` when the manifest declares no `type`, which is VS Code's own
    /// default and why the tree population is far larger than the count of
    /// entries that say `tree` outright.
    public let kind: Kind
    public let symbolName: String?
    /// Set when the declared icon was a file path rather than a codicon.
    public let iconPath: String?
    public let when: String?
    public let visibility: String?
    public let initialSize: Double?
    public let preferredAxisIsVertical: Bool

    public enum Kind: String, Sendable, Equatable { case tree, webview }

    public init(
        extensionIdentifier: String,
        viewID: String,
        registryID: String,
        targetContainerID: String,
        name: String,
        kind: Kind,
        symbolName: String?,
        iconPath: String?,
        when: String?,
        visibility: String?,
        initialSize: Double?,
        preferredAxisIsVertical: Bool
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.viewID = viewID
        self.registryID = registryID
        self.targetContainerID = targetContainerID
        self.name = name
        self.kind = kind
        self.symbolName = symbolName
        self.iconPath = iconPath
        self.when = when
        self.visibility = visibility
        self.initialSize = initialSize
        self.preferredAxisIsVertical = preferredAxisIsVertical
    }
}

/// Something a `views` or `viewsContainers` declaration said that this host
/// could not honour exactly.
///
/// The same shape as `ContributedSettingNote`, deliberately: a code-facing
/// `kind` a caller can group on, and a `detail` sentence written for a person.
/// The Extensions UI filters these by identifier at display time, which is why
/// nothing here offers a pre-filtered accessor.
public struct ContributedViewNote: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// A `when` clause was declared. It is stored and never evaluated.
        case whenNotEvaluated
        /// `"type": "webview"` — the content is the extension's own code.
        case webviewNeedsHost
        /// A `$(codicon)` reference with no SF Symbol equivalent.
        case unmappedIcon
        /// The icon was a file inside the extension, which nothing here reads.
        case fileIcon
        /// The target container is neither self-declared nor a VS Code
        /// built-in.
        case unknownContainer
        /// The same extension declared the same view id more than once.
        case duplicateViewID
        /// A field was declared with JSON the decoder could not read — an
        /// `initialSize` spelled `"2"`, an `icon` given as a light/dark object
        /// — so the view kept its identity and lost that field.
        ///
        /// This note is the whole reason `ExtensionManifest.View` records
        /// `unreadableKeys`. Without it the widened decoder would trade a loud
        /// failure (the element thrown out, a `DecodingFailure` recorded) for a
        /// silent one, and a dropped `when` would leave a pane offered
        /// unconditionally with nothing anywhere saying its author tried to
        /// condition it — the exact failure `whenNotEvaluated` exists to
        /// prevent, one level down.
        case malformedField
    }

    public let extensionIdentifier: String
    public let viewID: String
    public let kind: Kind
    public let detail: String

    public init(extensionIdentifier: String, viewID: String, kind: Kind, detail: String) {
        self.extensionIdentifier = extensionIdentifier
        self.viewID = viewID
        self.kind = kind
        self.detail = detail
    }
}

/// The `$(codicon)` names this host can answer with an SF Symbol.
///
/// A table rather than a transformation, because there is no rule connecting
/// the two vocabularies: `history` is `clock.arrow.circlepath` and no amount
/// of string manipulation gets there. Nothing else in this repo already maps
/// icon names to symbols — `abstractr exports` has no `Codicon`, `SFSymbol`
/// or `IconMap` export, and no file mentions codicons — so this is the first
/// answer to the question rather than a second one (`dry`).
public enum CodiconSymbols {

    /// `nil` for any name with no faithful equivalent: every vendor-private
    /// name a manifest happens to spell like a codicon (`gitlens-graph`,
    /// `colab-logo`), and every real codicon whose glyph has no generic
    /// subject — see the rule on `table`.
    ///
    /// - Parameter codicon: the bare name, without the `$(…)` wrapper.
    public static func symbolName(forCodicon codicon: String) -> String? {
        table[codicon]
    }

    /// Every mapping, exposed so a test can prove each value resolves on this
    /// platform: a wrong SF Symbol name is an invisible icon at runtime, not a
    /// build error, so nothing but a test catches it (`fail-fast`).
    ///
    /// **The rule.** A codicon is mapped when the glyph it draws has a generic
    /// subject a symbol can name — a cloud, a terminal, a clock. It is left
    /// unmapped when the glyph *is* a mark (`github`) or a control rather than
    /// a subject (`debug-gripper`, a drag handle on VS Code's floating debug
    /// toolbar). An unmapped name becomes an `unmappedIcon` note and a pane
    /// with no icon, which is honest where a stand-in glyph would not be.
    ///
    /// Note what the rule is *not*: "no third-party brands". `azure` and
    /// `terminal-powershell` are both branded names and both are mapped,
    /// because what those codicons draw is a cloud and a terminal. It is the
    /// Octocat that has no generic subject, not the word GitHub.
    ///
    /// Only long-established symbols are used. The deployment target is macOS
    /// 14 and the build machine is newer, so `NSImage(systemSymbolName:)`
    /// answering here does not by itself prove the name existed in SF Symbols
    /// 5; choosing names that predate it is what does.
    public static let table: [String: String] = [
        "azure": "cloud",
        "bell": "bell",
        "bookmark": "bookmark",
        "chevron-right": "chevron.right",
        "code": "chevron.left.forwardslash.chevron.right",
        "code-review": "text.bubble",
        "database": "cylinder.split.1x2",
        "debug-disconnect": "bolt.slash",
        "diff": "rectangle.split.2x1",
        "diff-multiple": "doc.on.doc",
        "file-code": "doc.plaintext",
        "folder-library": "folder",
        "git-compare": "arrow.triangle.branch",
        "git-merge": "arrow.triangle.merge",
        "git-pull-request": "arrow.triangle.pull",
        // SF Symbols has no "create a pull request" variant, and a pane icon
        // names its subject rather than the verb that made it.
        "git-pull-request-create": "arrow.triangle.pull",
        "graph": "chart.bar",
        // A plot with axes rather than a scatter of dots: `chart.dots.scatter`
        // arrived in SF Symbols 5, exactly the deployment floor, and a symbol
        // that is missing on the oldest supported system is an invisible icon.
        "graph-scatter": "chart.xyaxis.line",
        "history": "clock.arrow.circlepath",
        "info": "info.circle",
        "issues": "exclamationmark.circle",
        "json": "curlybraces",
        "lightbulb": "lightbulb",
        "list-tree": "list.bullet.indent",
        "notebook": "book",
        "output": "text.alignleft",
        "package": "shippingbox",
        "project": "square.grid.2x2",
        "pulse": "waveform.path.ecg",
        "question": "questionmark.circle",
        "references": "link",
        "remote-explorer": "network",
        "search": "magnifyingglass",
        "server-environment": "server.rack",
        "sparkle": "sparkles",
        "symbol-class": "cube",
        "symbol-file": "doc",
        "tag": "tag",
        "terminal-powershell": "terminal",
        "type-hierarchy": "square.stack.3d.up"
    ]
}

/// Turns `contributes.views` and `contributes.viewsContainers` into the
/// registry's vocabulary.
///
/// Pure and Foundation-only, so every ruling it applies is testable without a
/// window. It resolves icons to *names* and never opens a file: an extension's
/// own image assets are recorded as notes, not read.
public enum ContributedViewsBuilder {

    /// The container ids VS Code owns. A view may target one of these without
    /// its extension declaring anything, and doing so is not a defect.
    ///
    /// `panel` is in the set and is also the one location that means "the
    /// bottom strip", which is the whole of `preferredAxisIsVertical`.
    private static let builtInContainerIDs: Set<String> = [
        "explorer", "scm", "debug", "test", "remote", "panel"
    ]

    /// The location whose name means a horizontal strip along the bottom.
    private static let bottomPanelLocation = "panel"

    private enum IconReference {
        case codicon(String)
        case file(String)
    }

    /// Everything one extension contributed, plus every compromise made to
    /// reach it.
    ///
    /// Both `views` and `viewsContainers` decode into Swift dictionaries, so
    /// the manifest's own order is gone before this function is called. The
    /// results are sorted — containers by `(location, containerID)`, views by
    /// `(targetContainerID, viewID)` — because a pane list that reshuffles
    /// itself between launches is a defect, not a detail, and because
    /// "which duplicate wins" has to mean something stable.
    public static func build(
        from contributions: ExtensionManifest.Contributions,
        manifest: ExtensionManifest
    ) -> (
        containers: [ContributedViewContainer],
        views: [ContributedView],
        notes: [ContributedViewNote]
    ) {
        let identifier = manifest.identifier
        let containers = self.containers(from: contributions, ofExtension: identifier)

        // First declaration wins for a repeated container id, and `containers`
        // is already sorted, so "first" is a fact about the manifest's content
        // rather than about a dictionary's hash seed.
        var locationsByContainerID: [String: String] = [:]
        for container in containers where locationsByContainerID[container.containerID] == nil {
            locationsByContainerID[container.containerID] = container.location
        }

        var views: [ContributedView] = []
        var notes: [ContributedViewNote] = []
        var seenViewIDs: [String: String] = [:]

        for entry in flattenedViews(from: contributions) {
            let declared = entry.view

            if let firstTarget = seenViewIDs[declared.id] {
                notes.append(ContributedViewNote(
                    extensionIdentifier: identifier,
                    viewID: declared.id,
                    kind: .duplicateViewID,
                    detail: "declared more than once; the declaration in "
                        + "\"\(firstTarget)\" is the one registered."
                ))
                continue
            }
            seenViewIDs[declared.id] = entry.target

            // Two vocabularies meet here and they are not the same one. For a
            // self-declared target, `declaredLocation` is a `viewsContainers`
            // *key* (`activitybar`, `panel`, `secondarySidebar`); for a
            // built-in target there is no such key and the *container id*
            // (`explorer`, `scm`, `panel`, …) is all there is. Both spell the
            // bottom strip `panel`, which is a coincidence this states rather
            // than relies on silently: a seventh built-in id would otherwise be
            // compared against a location constant with nothing to say so.
            let declaredLocation = locationsByContainerID[entry.target]
            let isKnownTarget =
                declaredLocation != nil || builtInContainerIDs.contains(entry.target)
            // `isKnownTarget &&` is what keeps the axis and the note below from
            // drifting apart: the `unknownContainer` note *states* the axis
            // ("arranged along the horizontal axis") while this line *computes*
            // it, and without the conjunction they are two independent
            // expressions that happen to agree. Unreachable today — the only
            // string that makes the comparison true is `panel`, which is always
            // a known target — which is exactly why it needs saying.
            let isBottomStrip =
                isKnownTarget && (declaredLocation ?? entry.target) == bottomPanelLocation
            if !isKnownTarget {
                notes.append(ContributedViewNote(
                    extensionIdentifier: identifier,
                    viewID: declared.id,
                    kind: .unknownContainer,
                    detail: "targets the container \"\(entry.target)\", which neither this "
                        + "extension nor this host declares; the pane is arranged along the "
                        + "horizontal axis."
                ))
            }

            let kind: ContributedView.Kind = declared.type == "webview" ? .webview : .tree
            if kind == .webview {
                notes.append(ContributedViewNote(
                    extensionIdentifier: identifier,
                    viewID: declared.id,
                    kind: .webviewNeedsHost,
                    detail: "is a webview: its content is drawn by the extension's own code, "
                        + "which needs an extension host this app does not run yet."
                ))
            }

            let icon = resolveIcon(
                declared.icon, viewID: declared.id, identifier: identifier, notes: &notes)

            // Ruling GF. `View`'s decoder keeps the view and drops a field
            // whose JSON does not fit; this is where the drop stops being
            // silent. Without it a `when` given as a number would leave a pane
            // offered unconditionally with nothing recording that its author
            // tried to condition it — and `when` is on three quarters of the
            // corpus's view entries.
            for key in declared.unreadableKeys {
                notes.append(ContributedViewNote(
                    extensionIdentifier: identifier,
                    viewID: declared.id,
                    kind: .malformedField,
                    detail: "declares \(key) in a form this host cannot read; the pane is "
                        + "offered without it."
                ))
            }

            if let when = declared.when, !when.isEmpty {
                notes.append(ContributedViewNote(
                    extensionIdentifier: identifier,
                    viewID: declared.id,
                    kind: .whenNotEvaluated,
                    detail: "declares when: \(when). This host does not evaluate when clauses, "
                        + "so the pane is offered whatever the condition would have said."
                ))
            }

            views.append(ContributedView(
                extensionIdentifier: identifier,
                viewID: declared.id,
                registryID: "extension.\(identifier).\(declared.id)",
                targetContainerID: entry.target,
                name: declared.name,
                kind: kind,
                symbolName: icon.symbolName,
                iconPath: icon.path,
                when: declared.when,
                visibility: declared.visibility,
                initialSize: declared.initialSize,
                preferredAxisIsVertical: isBottomStrip
            ))
        }

        return (containers, views, notes)
    }

    // MARK: - Pieces

    private static func containers(
        from contributions: ExtensionManifest.Contributions,
        ofExtension identifier: String
    ) -> [ContributedViewContainer] {
        var flattened: [(index: Int, container: ContributedViewContainer)] = []
        for (location, declared) in contributions.viewsContainers {
            for (index, container) in declared.enumerated() {
                flattened.append((index, ContributedViewContainer(
                    extensionIdentifier: identifier,
                    location: location,
                    containerID: container.id,
                    title: container.title,
                    icon: container.icon,
                    when: container.when
                )))
            }
        }
        // `sort` is not stable, so the declaration index is part of the key
        // rather than something left to chance.
        flattened.sort {
            ($0.container.location, $0.container.containerID, $0.index)
                < ($1.container.location, $1.container.containerID, $1.index)
        }
        return flattened.map(\.container)
    }

    private static func flattenedViews(
        from contributions: ExtensionManifest.Contributions
    ) -> [(target: String, index: Int, view: ExtensionManifest.View)] {
        var flattened: [(target: String, index: Int, view: ExtensionManifest.View)] = []
        for (target, declared) in contributions.views {
            for (index, view) in declared.enumerated() {
                flattened.append((target, index, view))
            }
        }
        flattened.sort {
            ($0.target, $0.view.id, $0.index) < ($1.target, $1.view.id, $1.index)
        }
        return flattened
    }

    /// A declared icon is either a codicon reference or a path into the
    /// extension's own files. Neither can become an image here — the first has
    /// no image at all, only a name, and the second is a file this point does
    /// not open — so both answers are a name and a note.
    private static func resolveIcon(
        _ icon: String?,
        viewID: String,
        identifier: String,
        notes: inout [ContributedViewNote]
    ) -> (symbolName: String?, path: String?) {
        guard let icon, let reference = iconReference(icon) else { return (nil, nil) }

        switch reference {
        case .codicon(let name):
            if let symbol = CodiconSymbols.symbolName(forCodicon: name) {
                return (symbol, nil)
            }
            notes.append(ContributedViewNote(
                extensionIdentifier: identifier,
                viewID: viewID,
                kind: .unmappedIcon,
                detail: "asks for the icon $(\(name)), which has no equivalent in this host's "
                    + "symbol set; the pane is offered without an icon."
            ))
            return (nil, nil)

        case .file(let path):
            notes.append(ContributedViewNote(
                extensionIdentifier: identifier,
                viewID: viewID,
                kind: .fileIcon,
                detail: "asks for the image \(path) from inside the extension; this host does "
                    + "not draw extension image files, so the pane is offered without an icon."
            ))
            return (nil, path)
        }
    }

    private static func iconReference(_ icon: String) -> IconReference? {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.hasPrefix("$("), trimmed.hasSuffix(")") else { return .file(trimmed) }
        // `$(sync~spin)` names the same icon as `$(sync)`; the modifier after
        // the tilde asks for an animation, not a different glyph.
        let inner = trimmed.dropFirst(2).dropLast()
        let name = inner.split(separator: "~", maxSplits: 1).first.map(String.init) ?? ""
        return name.isEmpty ? nil : .codicon(name)
    }
}
