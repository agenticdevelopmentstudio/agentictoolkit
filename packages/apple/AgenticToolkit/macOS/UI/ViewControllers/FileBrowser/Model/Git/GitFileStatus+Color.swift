import AgenticToolkitCore
import AppKit
import SwiftUI

extension GitFileStatus {
    public var color: Color {
        switch self {
        case .modified: return .orange
        case .added, .untracked: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        case .conflicted: return .purple
        case .ignored: return .gray
        }
    }

    /// The same colors for AppKit callers. Two spellings of one fact rather
    /// than two facts: whichever framework draws the badge, red still means
    /// deleted (`dry`).
    public var nsColor: NSColor {
        switch self {
        case .modified: return .systemOrange
        case .added, .untracked: return .systemGreen
        case .deleted: return .systemRed
        case .renamed, .copied: return .systemBlue
        case .conflicted: return .systemPurple
        case .ignored: return .systemGray
        }
    }
}
