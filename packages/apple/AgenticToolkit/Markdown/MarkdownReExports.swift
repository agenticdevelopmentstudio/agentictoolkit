// Re-exported (not merely imported): MarkdownDocument, MarkdownText, Frontmatter
// and friends live in AgenticDeveloperToolkit, but every consumer of this
// module — including its own test target, which never imports
// AgenticDeveloperToolkit directly — reaches them through
// `AgenticToolkitMarkdown`. Mirrors `Core/Theme/ThemeReExports.swift`'s
// re-export of the same module for the theme model.
@_exported import AgenticDeveloperToolkit
