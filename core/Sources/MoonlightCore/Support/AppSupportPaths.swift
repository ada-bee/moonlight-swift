import Foundation

public struct AppSupportPaths {
    public let fileManager: FileManager
    public let rootDirectoryURL: URL

    public init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager

        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL.standardizedFileURL
        } else {
            let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                    .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.rootDirectoryURL = applicationSupportDirectory
                .appendingPathComponent("GameStream", isDirectory: true)
                .standardizedFileURL
        }
    }

    public var settingsFileURL: URL {
        rootDirectoryURL.appendingPathComponent("settings.json", isDirectory: false)
    }

    public var pairingDirectoryURL: URL {
        rootDirectoryURL.appendingPathComponent("pairing", isDirectory: true)
    }

    public var currentPairingDirectoryURL: URL {
        pairingDirectoryURL.appendingPathComponent("current", isDirectory: true)
    }

    @discardableResult
    public func prepare() throws -> AppSupportPaths {
        try createDirectoryIfNeeded(rootDirectoryURL)
        try createDirectoryIfNeeded(pairingDirectoryURL)
        return self
    }

    public func createDirectoryIfNeeded(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
