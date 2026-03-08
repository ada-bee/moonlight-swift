import Foundation

public struct LaunchSessionContext: Sendable {
    public var riKey: Data
    public var riKeyID: UInt32

    public init(riKey: Data, riKeyID: UInt32) {
        self.riKey = riKey
        self.riKeyID = riKeyID
    }

    public static func makeRandom() -> LaunchSessionContext {
        let keyBytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        return LaunchSessionContext(riKey: Data(keyBytes), riKeyID: UInt32.random(in: 1...UInt32.max))
    }

    public var riKeyHex: String {
        riKey.map { String(format: "%02x", $0) }.joined()
    }
}
