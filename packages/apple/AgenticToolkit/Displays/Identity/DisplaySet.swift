/// The displays connected together at one moment, as a multiset of identities.
/// `id` is order-independent and keeps duplicates, so two indistinguishable
/// monitors still count as two members.
public struct DisplaySet: Hashable, Codable, Sendable {
    public let members: [DisplayIdentity]

    public init(_ identities: some Sequence<DisplayIdentity>) {
        members = identities.sorted { $0.key < $1.key }
    }

    public var id: String { members.map(\.key).joined(separator: "+") }
}
