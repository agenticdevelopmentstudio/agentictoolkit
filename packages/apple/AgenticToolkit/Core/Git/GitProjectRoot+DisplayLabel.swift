import Foundation

extension GitProjectRoot {

    /// `~/src/site · main`: a repository's root with the home directory
    /// abbreviated, then its branch — or just the path when there is no branch.
    /// The one way a repository is named in a sentence or a menu, so every
    /// screen names it alike.
    public static func displayLabel(root: String, branch: String) -> String {
        let path = (root as NSString).abbreviatingWithTildeInPath
        return branch.isEmpty ? path : "\(path) · \(branch)"
    }
}
