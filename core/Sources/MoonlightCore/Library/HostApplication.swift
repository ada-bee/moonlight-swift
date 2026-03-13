import Foundation

public struct HostApplication: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var posterURL: URL?
    public var lastUpdated: Date?
    public var isRunning: Bool

    public init(id: Int, name: String, posterURL: URL?, lastUpdated: Date?, isRunning: Bool = false) {
        self.id = id
        self.name = name
        self.posterURL = posterURL
        self.lastUpdated = lastUpdated
        self.isRunning = isRunning
    }
}
