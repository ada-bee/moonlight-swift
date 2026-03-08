import Foundation

public struct AppSettingsStore {
    public let fileManager: FileManager
    public let paths: AppSupportPaths

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        paths: AppSupportPaths = AppSupportPaths(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.paths = paths

        let configuredEncoder = encoder
        configuredEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = configuredEncoder
        self.decoder = decoder
    }

    public func load() throws -> AppSettings {
        try paths.prepare()

        guard fileManager.fileExists(atPath: paths.settingsFileURL.path) else {
            return .initial
        }

        let data = try Data(contentsOf: paths.settingsFileURL)
        return try decoder.decode(AppSettings.self, from: data)
    }

    public func loadOrCreate() throws -> AppSettings {
        let settings = try load()

        if !fileManager.fileExists(atPath: paths.settingsFileURL.path) {
            try save(settings)
        }

        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try paths.prepare()
        let data = try encoder.encode(settings)
        try data.write(to: paths.settingsFileURL, options: .atomic)
    }
}
