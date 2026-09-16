import SwiftUI

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// The content viewer pane that displays file metadata when a file is selected.
///
/// Shows a placeholder message ("Select a file to view its details") when no file
/// is selected. When a file or directory is selected, shows its name, full path,
/// file size, modification date, and type.
public struct ContentViewerView: View {
    /// The currently selected file tree node, or `nil` if nothing is selected.
    public let selectedNode: FileTreeNode?

    /// Framework configuration. Used for package display names.
    public let config: FileTreeConfig

    public init(selectedNode: FileTreeNode?, config: FileTreeConfig) {
        self.selectedNode = selectedNode
        self.config = config
    }

    public var body: some View {
        Group {
            if let node = selectedNode {
                FileDetailView(node: node, config: config)
            } else {
                PlaceholderView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Placeholder View

/// Shown when no file is selected in the file tree.
private struct PlaceholderView: View {
    @Environment(\.theme) private var theme

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(theme.tertiaryText)

            Text("Select a file to view its details")
                .font(theme.font(.heading))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - File Detail View

/// Displays detailed metadata for a selected file or directory.
private struct FileDetailView: View {
    public let node: FileTreeNode
    public let config: FileTreeConfig

    @Environment(\.theme) private var theme

    /// Formatter for file sizes.
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    /// Formatter for dates.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: node.systemImageName)
                    .font(.system(size: 40))
                    .foregroundStyle(headerIconColor)

                Text(node.name)
                    .font(theme.font(.title))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(typeDescription)
                    .font(theme.font(.caption))
                    .foregroundStyle(theme.secondaryText)
            }
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 40)

            // Metadata grid
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Path:")
                        .foregroundStyle(theme.secondaryText)
                        .gridColumnAlignment(.trailing)
                    Text(node.url.path)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .gridColumnAlignment(.leading)
                }

                if let size = node.fileSize {
                    GridRow {
                        Text("Size:")
                            .foregroundStyle(theme.secondaryText)
                        Text(Self.byteCountFormatter.string(fromByteCount: Int64(size)))
                    }
                }

                if let date = node.modificationDate {
                    GridRow {
                        Text("Modified:")
                            .foregroundStyle(theme.secondaryText)
                        Text(Self.dateFormatter.string(from: date))
                    }
                }

                GridRow {
                    Text("Type:")
                        .foregroundStyle(theme.secondaryText)
                    Text(typeDescription)
                }

                if !node.isDirectory, !node.url.pathExtension.isEmpty {
                    GridRow {
                        Text("Extension:")
                            .foregroundStyle(theme.secondaryText)
                        Text(".\(node.url.pathExtension)")
                    }
                }

                if let children = node.children {
                    GridRow {
                        Text("Items:")
                            .foregroundStyle(theme.secondaryText)
                        Text("\(children.count)")
                    }
                }
            }
            .font(theme.font(.body))
            .padding(.top, 20)
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Human-readable description of the file type.
    private var typeDescription: String {
        if node.isPackage {
            let ext = node.url.pathExtension
            return config.packageDisplayNames[ext] ?? "Package"
        }
        if node.isDirectory {
            return "Directory"
        }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "swift": return "Swift Source File"
        case "json": return "JSON File"
        case "md", "markdown": return "Markdown Document"
        case "txt", "text": return "Text File"
        case "plist": return "Property List"
        case "entitlements": return "Entitlements File"
        case "xcodeproj": return "Xcode Project"
        case "xcworkspace": return "Xcode Workspace"
        case "png": return "PNG Image"
        case "jpg", "jpeg": return "JPEG Image"
        case "svg": return "SVG Image"
        case "gif": return "GIF Image"
        case "sh": return "Shell Script"
        case "zsh": return "Zsh Script"
        case "bash": return "Bash Script"
        case "py": return "Python Script"
        case "js": return "JavaScript File"
        case "ts": return "TypeScript File"
        case "css": return "CSS Stylesheet"
        case "html": return "HTML Document"
        case "yaml", "yml": return "YAML File"
        case "toml": return "TOML File"
        case "gitignore": return "Git Ignore Rules"
        default: return ext.isEmpty ? "File" : "\(ext.uppercased()) File"
        }
    }

    /// Color for the header icon.
    ///
    /// The palette has no per-language "brand color" role, so these map onto
    /// the nearest status role the same way `SwiftUIPalette.color(named:)`
    /// does (orange/yellow → warning, blue → accent) — swift and json land on
    /// the same tone, which is already true of that shared mapping.
    private var headerIconColor: Color {
        if node.isPackage { return theme.warning }
        if node.isDirectory { return theme.accent }
        let ext = node.url.pathExtension.lowercased()
        switch ext {
        case "swift": return theme.warning
        case "json": return theme.warning
        case "md", "markdown": return theme.accent
        default: return theme.secondaryText
        }
    }
}
