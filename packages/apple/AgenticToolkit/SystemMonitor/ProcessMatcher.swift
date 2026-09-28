import Foundation

/// Which processes belong to a group — "everything that is Docker".
public struct ProcessMatcher: Sendable, Equatable {

    public enum Rule: Sendable, Equatable {
        /// The executable's file name, compared case-insensitively.
        case name(String)
        /// The start of the executable's file name, case-insensitively.
        case namePrefix(String)
        /// Anywhere in the executable's full path — an app bundle, say.
        case pathContains(String)
        /// A Virtualization.framework VM whose open files include a path
        /// containing this text. A VM runs as Apple's own XPC service, so its
        /// name says nothing about whose VM it is; the disk image it holds
        /// open does. This is where Docker's containers actually spend memory.
        case virtualMachineHolding(String)
    }

    /// The executable name every Virtualization.framework VM runs as.
    public static let virtualMachineProcessName = "com.apple.Virtualization.VirtualMachine"

    public let rules: [Rule]

    public init(_ rules: [Rule]) {
        self.rules = rules
    }

    /// - Parameter openFiles: read only for a VM process that a
    ///   `virtualMachineHolding` rule needs to look inside.
    public func matches(_ process: ProcessSample, openFiles: (Int32) -> [String]) -> Bool {
        let name = process.name.lowercased()
        var vmFiles: [String]?
        for rule in rules {
            switch rule {
            case .name(let expected):
                if name == expected.lowercased() { return true }
            case .namePrefix(let prefix):
                if name.hasPrefix(prefix.lowercased()) { return true }
            case .pathContains(let text):
                if process.path.contains(text) { return true }
            case .virtualMachineHolding(let text):
                guard process.name == Self.virtualMachineProcessName else { continue }
                if vmFiles == nil { vmFiles = openFiles(process.pid) }
                if vmFiles?.contains(where: { $0.contains(text) }) == true { return true }
            }
        }
        return false
    }
}

extension ProcessMatcher {

    /// Docker Desktop: its app bundle, its `com.docker.*` helpers, the CLI, and
    /// the VM holding Docker's disk image.
    public static let docker = ProcessMatcher([
        .pathContains("/Docker.app/"),
        .namePrefix("com.docker."),
        .name("docker"),
        .name("docker-compose"),
        .virtualMachineHolding("/Containers/com.docker.docker/")
    ])

    /// Ollama: the server, its app, and the model runners it starts.
    public static let ollama = ProcessMatcher([
        .pathContains("/Ollama.app/"),
        .namePrefix("ollama")
    ])
}
