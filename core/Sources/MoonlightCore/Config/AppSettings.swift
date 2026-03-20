import Foundation

public struct AppSettings: Codable, Sendable {
    public struct Input: Codable, Sendable {
        public var rawMouseSensitivity: Double

        public init(rawMouseSensitivity: Double) {
            self.rawMouseSensitivity = Self.clampedRawMouseSensitivity(rawMouseSensitivity)
        }

        private enum CodingKeys: String, CodingKey {
            case rawMouseSensitivity
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rawMouseSensitivity = Self.clampedRawMouseSensitivity(
                try container.decodeIfPresent(Double.self, forKey: .rawMouseSensitivity) ?? Self.defaultRawMouseSensitivity
            )
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rawMouseSensitivity, forKey: .rawMouseSensitivity)
        }

        public static let defaultRawMouseSensitivity = 1.0

        public var effectiveRawMouseScale: Double {
            rawMouseSensitivity
        }

        public static func clampedRawMouseSensitivity(_ value: Double) -> Double {
            min(max(value, 0.1), 4.0)
        }
    }

    public struct Video: Codable, Sendable {
        public var resolution: StreamConfiguration.Video.Resolution
        public var fps: Int
        public var bitrateKbps: Int
        public var packetSize: Int
        public var supportedResolutions: [StreamConfiguration.Video.Resolution]

        public init(
            resolution: StreamConfiguration.Video.Resolution,
            fps: Int,
            bitrateKbps: Int,
            packetSize: Int,
            supportedResolutions: [StreamConfiguration.Video.Resolution]
        ) {
            self.resolution = resolution
            self.fps = fps
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
            self.supportedResolutions = Self.normalizedSupportedResolutions(supportedResolutions)
        }

        private enum CodingKeys: String, CodingKey {
            case resolution
            case width
            case height
            case fps
            case bitrateKbps
            case packetSize
            case supportedResolutions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decodedResolution = try container.decodeIfPresent(StreamConfiguration.Video.Resolution.self, forKey: .resolution) {
                resolution = decodedResolution
            } else {
                resolution = StreamConfiguration.Video.Resolution(
                    width: try container.decodeIfPresent(Int.self, forKey: .width) ?? StreamConfiguration.fallback.video.resolution.width,
                    height: try container.decodeIfPresent(Int.self, forKey: .height) ?? StreamConfiguration.fallback.video.resolution.height
                )
            }
            fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? StreamConfiguration.fallback.video.fps
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? StreamConfiguration.fallback.video.bitrateKbps
            packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? StreamConfiguration.fallback.video.packetSize

            let decodedSupportedResolutions = try container.decodeIfPresent([StreamConfiguration.Video.Resolution].self, forKey: .supportedResolutions)
                ?? Self.defaultSupportedResolutions
            supportedResolutions = Self.normalizedSupportedResolutions(decodedSupportedResolutions)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(resolution, forKey: .resolution)
            try container.encode(fps, forKey: .fps)
            try container.encode(bitrateKbps, forKey: .bitrateKbps)
            try container.encode(packetSize, forKey: .packetSize)
            try container.encode(supportedResolutions, forKey: .supportedResolutions)
        }

        public static let defaultSupportedResolutions: [StreamConfiguration.Video.Resolution] = [
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
            _ resolutions: [StreamConfiguration.Video.Resolution]
        ) -> [StreamConfiguration.Video.Resolution] {
            let filtered = resolutions.filter(Self.isSupportedResolution)
            let unique = Array(Set(filtered))
            let sorted = unique.sorted(by: Self.sortsBefore)
            return sorted.isEmpty ? defaultSupportedResolutions : sorted
        }

        public static func isSupportedResolution(_ resolution: StreamConfiguration.Video.Resolution) -> Bool {
            resolution.width > 0
                && resolution.height > 0
                && resolution.width.isMultiple(of: 2)
                && resolution.height.isMultiple(of: 2)
        }

        private static func sortsBefore(
            _ lhs: StreamConfiguration.Video.Resolution,
            _ rhs: StreamConfiguration.Video.Resolution
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
    public var input: Input
    public var video: Video
    public var streamMode: StreamMode
    public var pendingPairingResetOnNextLaunch: Bool

    private enum CodingKeys: String, CodingKey {
        case host
        case input
        case video
        case streamMode
        case launchesFullscreen
        case pendingPairingResetOnNextLaunch
    }

    public init(
        host: HostAuthority?,
        input: Input,
        video: Video,
        streamMode: StreamMode,
        pendingPairingResetOnNextLaunch: Bool
    ) {
        self.host = host
        self.input = input
        self.video = video
        self.streamMode = streamMode
        self.pendingPairingResetOnNextLaunch = pendingPairingResetOnNextLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(HostAuthority.self, forKey: .host)
        input = try container.decodeIfPresent(Input.self, forKey: .input) ?? AppSettings.initial.input
        video = try container.decodeIfPresent(Video.self, forKey: .video) ?? AppSettings.initial.video
        if let decodedMode = try container.decodeIfPresent(StreamMode.self, forKey: .streamMode) {
            streamMode = decodedMode
        } else {
            streamMode = (try container.decodeIfPresent(Bool.self, forKey: .launchesFullscreen) ?? false) ? .fullscreen : .windowed
        }
        pendingPairingResetOnNextLaunch = try container.decodeIfPresent(Bool.self, forKey: .pendingPairingResetOnNextLaunch) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encode(input, forKey: .input)
        try container.encode(video, forKey: .video)
        try container.encode(streamMode, forKey: .streamMode)
        try container.encode(pendingPairingResetOnNextLaunch, forKey: .pendingPairingResetOnNextLaunch)
    }
}

public extension AppSettings {
    static let initialWindowedVideo = Video(
        resolution: StreamConfiguration.fallback.video.resolution,
        fps: StreamConfiguration.fallback.video.fps,
        bitrateKbps: StreamConfiguration.fallback.video.bitrateKbps,
        packetSize: StreamConfiguration.fallback.video.packetSize,
        supportedResolutions: AppSettings.Video.defaultSupportedResolutions
    )

    static let initial = AppSettings(
        host: nil,
        input: .init(rawMouseSensitivity: AppSettings.Input.defaultRawMouseSensitivity),
        video: initialWindowedVideo,
        streamMode: .windowed,
        pendingPairingResetOnNextLaunch: false
    )

    func makeConfiguration(
        appID: Int,
        autoConnectOnLaunch: Bool = false,
        requestResume: Bool = false,
        resolution: StreamConfiguration.Video.Resolution? = nil,
        fps: Int? = nil
    ) throws -> StreamConfiguration {
        guard let host else {
            throw AppSettingsError.missingHost
        }

        let requestedResolution = resolution ?? video.resolution

        return StreamConfiguration(
            host: .init(address: host.address, port: host.port, appID: appID),
            session: .init(autoConnectOnLaunch: autoConnectOnLaunch, requestResume: requestResume),
            input: .init(rawMouseSensitivity: input.rawMouseSensitivity),
            video: .init(
                resolution: requestedResolution,
                fps: fps ?? video.fps,
                bitrateKbps: video.bitrateKbps,
                packetSize: video.packetSize
            )
        )
    }
}

public enum StreamMode: String, Codable, Sendable, Hashable {
    case windowed
    case fullscreen
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
