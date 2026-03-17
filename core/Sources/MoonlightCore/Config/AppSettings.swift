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
        public var bitrateKbps: Int
        public var packetSize: Int
        public var supportedResolutions: [MVPConfiguration.Video.Resolution]

        public init(
            width: Int,
            height: Int,
            fps: Int,
            bitrateKbps: Int,
            packetSize: Int,
            supportedResolutions: [MVPConfiguration.Video.Resolution]
        ) {
            self.width = width
            self.height = height
            self.fps = fps
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
            self.supportedResolutions = Self.normalizedSupportedResolutions(supportedResolutions)
        }

        private enum CodingKeys: String, CodingKey {
            case width
            case height
            case fps
            case bitrateKbps
            case packetSize
            case supportedResolutions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            width = try container.decodeIfPresent(Int.self, forKey: .width) ?? MVPConfiguration.fallback.video.resolution.width
            height = try container.decodeIfPresent(Int.self, forKey: .height) ?? MVPConfiguration.fallback.video.resolution.height
            fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? MVPConfiguration.fallback.video.fps
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? MVPConfiguration.fallback.video.bitrateKbps
            packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? MVPConfiguration.fallback.video.packetSize

            let decodedSupportedResolutions = try container.decodeIfPresent([MVPConfiguration.Video.Resolution].self, forKey: .supportedResolutions)
                ?? Self.defaultSupportedResolutions
            supportedResolutions = Self.normalizedSupportedResolutions(decodedSupportedResolutions)
        }

        public static let defaultSupportedResolutions: [MVPConfiguration.Video.Resolution] = [
            .init(width: 3840, height: 2160),
            .init(width: 2560, height: 1600),
            .init(width: 2560, height: 1440),
            .init(width: 1920, height: 1200),
            .init(width: 1920, height: 1080),
            .init(width: 1680, height: 1050),
            .init(width: 1440, height: 900),
            .init(width: 1280, height: 800)
        ]

        public static func normalizedSupportedResolutions(
            _ resolutions: [MVPConfiguration.Video.Resolution]
        ) -> [MVPConfiguration.Video.Resolution] {
            let filtered = resolutions.filter(Self.isSupportedResolution)
            let unique = Array(Set(filtered))
            let sorted = unique.sorted(by: Self.sortsBefore)
            return sorted.isEmpty ? defaultSupportedResolutions : sorted
        }

        public static func isSupportedResolution(_ resolution: MVPConfiguration.Video.Resolution) -> Bool {
            resolution.width > 0
                && resolution.height > 0
                && resolution.width.isMultiple(of: 2)
                && resolution.height.isMultiple(of: 2)
        }

        private static func sortsBefore(
            _ lhs: MVPConfiguration.Video.Resolution,
            _ rhs: MVPConfiguration.Video.Resolution
        ) -> Bool {
            let lhsPixels = lhs.width * lhs.height
            let rhsPixels = rhs.width * rhs.height

            if lhsPixels != rhsPixels {
                return lhsPixels > rhsPixels
            }

            if lhs.width != rhs.width {
                return lhs.width > rhs.width
            }

            return lhs.height > rhs.height
        }
    }

    public var host: HostAuthority?
    public var video: Video
    public var perGameLaunchPreferences: [String: AppGameLaunchPreferences]
    public var closesLibraryWindowOnStreamStart: Bool
    public var reopensLibraryWindowOnStreamStop: Bool
    public var pendingPairingResetOnNextLaunch: Bool

    private enum CodingKeys: String, CodingKey {
        case host
        case video
        case perGameLaunchPreferences
        case closesLibraryWindowOnStreamStart
        case reopensLibraryWindowOnStreamStop
        case pendingPairingResetOnNextLaunch
    }

    public init(
        host: HostAuthority?,
        video: Video,
        perGameLaunchPreferences: [String: AppGameLaunchPreferences],
        closesLibraryWindowOnStreamStart: Bool,
        reopensLibraryWindowOnStreamStop: Bool,
        pendingPairingResetOnNextLaunch: Bool
    ) {
        self.host = host
        self.video = video
        self.perGameLaunchPreferences = perGameLaunchPreferences
        self.closesLibraryWindowOnStreamStart = closesLibraryWindowOnStreamStart
        self.reopensLibraryWindowOnStreamStop = reopensLibraryWindowOnStreamStop
        self.pendingPairingResetOnNextLaunch = pendingPairingResetOnNextLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(HostAuthority.self, forKey: .host)
        video = try container.decodeIfPresent(Video.self, forKey: .video) ?? AppSettings.initial.video
        perGameLaunchPreferences = try container.decodeIfPresent([String: AppGameLaunchPreferences].self, forKey: .perGameLaunchPreferences) ?? [:]
        closesLibraryWindowOnStreamStart = try container.decodeIfPresent(Bool.self, forKey: .closesLibraryWindowOnStreamStart) ?? false
        reopensLibraryWindowOnStreamStop = try container.decodeIfPresent(Bool.self, forKey: .reopensLibraryWindowOnStreamStop) ?? false
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
            bitrateKbps: MVPConfiguration.fallback.video.bitrateKbps,
            packetSize: MVPConfiguration.fallback.video.packetSize,
            supportedResolutions: AppSettings.Video.defaultSupportedResolutions
        ),
        perGameLaunchPreferences: [:],
        closesLibraryWindowOnStreamStart: false,
        reopensLibraryWindowOnStreamStop: false,
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
