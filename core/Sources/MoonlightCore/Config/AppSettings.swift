import Foundation

public struct AppGameLaunchPreferences: Codable, Sendable, Equatable {
    public var launchesFullscreen: Bool
    public var usesRawMouse: Bool
    public var windowedResolution: MVPConfiguration.Video.Resolution
    public var windowedFPS: Int

    public init(
        launchesFullscreen: Bool,
        usesRawMouse: Bool,
        windowedResolution: MVPConfiguration.Video.Resolution,
        windowedFPS: Int
    ) {
        self.launchesFullscreen = launchesFullscreen
        self.usesRawMouse = usesRawMouse
        self.windowedResolution = windowedResolution
        self.windowedFPS = windowedFPS
    }

    private enum CodingKeys: String, CodingKey {
        case launchesFullscreen
        case usesRawMouse
        case windowedResolution
        case windowedFPS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchesFullscreen = try container.decodeIfPresent(Bool.self, forKey: .launchesFullscreen) ?? false
        usesRawMouse = try container.decodeIfPresent(Bool.self, forKey: .usesRawMouse) ?? false
        windowedResolution = try container.decodeIfPresent(MVPConfiguration.Video.Resolution.self, forKey: .windowedResolution) ?? .init(width: 2560, height: 1440)
        windowedFPS = try container.decodeIfPresent(Int.self, forKey: .windowedFPS) ?? 120
    }
}

public struct AppSettings: Codable, Sendable {
    public struct Video: Codable, Sendable {
        public var width: Int
        public var height: Int
        public var fps: Int
        public var vsync: Bool
        public var bitrateKbps: Int
        public var packetSize: Int

        public init(
            width: Int,
            height: Int,
            fps: Int,
            vsync: Bool,
            bitrateKbps: Int,
            packetSize: Int
        ) {
            self.width = width
            self.height = height
            self.fps = fps
            self.vsync = vsync
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
        }
    }

    public var host: HostAuthority?
    public var video: Video
    public var perGameLaunchPreferences: [String: AppGameLaunchPreferences]
    public var pendingPairingResetOnNextLaunch: Bool

    private enum CodingKeys: String, CodingKey {
        case host
        case video
        case perGameLaunchPreferences
        case pendingPairingResetOnNextLaunch
    }

    public init(
        host: HostAuthority?,
        video: Video,
        perGameLaunchPreferences: [String: AppGameLaunchPreferences],
        pendingPairingResetOnNextLaunch: Bool
    ) {
        self.host = host
        self.video = video
        self.perGameLaunchPreferences = perGameLaunchPreferences
        self.pendingPairingResetOnNextLaunch = pendingPairingResetOnNextLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(HostAuthority.self, forKey: .host)
        video = try container.decodeIfPresent(Video.self, forKey: .video) ?? AppSettings.initial.video
        perGameLaunchPreferences = try container.decodeIfPresent([String: AppGameLaunchPreferences].self, forKey: .perGameLaunchPreferences) ?? [:]
        pendingPairingResetOnNextLaunch = try container.decodeIfPresent(Bool.self, forKey: .pendingPairingResetOnNextLaunch) ?? false
    }
}

public extension AppSettings {
    static let initial = AppSettings(
        host: nil,
        video: .init(
            width: MVPConfiguration.fallback.video.resolution.width,
            height: MVPConfiguration.fallback.video.resolution.height,
            fps: MVPConfiguration.fallback.video.fps,
            vsync: MVPConfiguration.fallback.video.vsync,
            bitrateKbps: MVPConfiguration.fallback.video.bitrateKbps,
            packetSize: MVPConfiguration.fallback.video.packetSize
        ),
        perGameLaunchPreferences: [:],
        pendingPairingResetOnNextLaunch: false
    )

    func makeConfiguration(
        appID: Int,
        autoConnectOnLaunch: Bool = false,
        requestResume: Bool = false,
        resolution: MVPConfiguration.Video.Resolution? = nil,
        fps: Int? = nil
    ) throws -> MVPConfiguration {
        guard let host else {
            throw AppSettingsError.missingHost
        }

        let requestedResolution = resolution ?? MVPConfiguration.Video.Resolution(width: video.width, height: video.height)

        return MVPConfiguration(
            host: .init(address: host.address, port: host.port, appID: appID),
            session: .init(autoConnectOnLaunch: autoConnectOnLaunch, requestResume: requestResume),
            video: .init(
                resolution: requestedResolution,
                fps: fps ?? video.fps,
                vsync: video.vsync,
                bitrateKbps: video.bitrateKbps,
                packetSize: video.packetSize
            )
        )
    }

    func launchPreferences(for appID: Int) -> AppGameLaunchPreferences {
        if let storedPreferences = perGameLaunchPreferences[String(appID)] {
            return storedPreferences
        }

        return AppGameLaunchPreferences(
            launchesFullscreen: false,
            usesRawMouse: false,
            windowedResolution: MVPConfiguration.Video.Resolution(width: video.width, height: video.height),
            windowedFPS: video.fps
        )
    }

    mutating func setLaunchPreferences(_ preferences: AppGameLaunchPreferences, for appID: Int) {
        perGameLaunchPreferences[String(appID)] = preferences
    }
}

public enum AppSettingsError: Error, LocalizedError {
    case missingHost

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            return "No host is configured."
        }
    }
}
