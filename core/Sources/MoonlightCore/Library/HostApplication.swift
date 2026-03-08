import Foundation

public struct HostApplication: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var posterURL: URL?
    public var lastUpdated: Date?

    public init(id: Int, name: String, posterURL: URL?, lastUpdated: Date?) {
        self.id = id
        self.name = name
        self.posterURL = posterURL
        self.lastUpdated = lastUpdated
    }
}
