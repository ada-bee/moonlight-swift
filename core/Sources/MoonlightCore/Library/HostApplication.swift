import Foundation

public struct HostApplication: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isRunning: Bool

    public init(id: Int, name: String, isRunning: Bool = false) {
        self.id = id
        self.name = name
        self.isRunning = isRunning
    }
}
