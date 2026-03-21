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

    public struct StreamPreset: Codable, Sendable, Hashable {
        public var screenMode: StreamMode
        public var resolution: StreamConfiguration.Video.Resolution
        public var fps: Int
        public var mouseMode: StreamMouseModePreference

        public init(
            screenMode: StreamMode,
            resolution: StreamConfiguration.Video.Resolution,
            fps: Int,
            mouseMode: StreamMouseModePreference
        ) {
            self.screenMode = screenMode
            self.resolution = Self.normalizedResolution(resolution)
            self.fps = Self.normalizedFPS(fps)
            self.mouseMode = mouseMode
        }

        private static func normalizedResolution(
            _ resolution: StreamConfiguration.Video.Resolution
        ) -> StreamConfiguration.Video.Resolution {
            AppSettings.Video.isSupportedResolution(resolution) ? resolution : StreamConfiguration.fallback.video.resolution
        }

        private static func normalizedFPS(_ fps: Int) -> Int {
            AppSettings.Video.isSupportedFPS(fps) ? fps : StreamConfiguration.fallback.video.fps
        }
    }

    public struct Video: Codable, Sendable {
        public var presets: [StreamPreset]
        public var bitrateKbps: Int
        public var packetSize: Int
        public var supportedResolutions: [StreamConfiguration.Video.Resolution]

        public init(
            presets: [StreamPreset],
            bitrateKbps: Int,
            packetSize: Int,
            supportedResolutions: [StreamConfiguration.Video.Resolution]
        ) {
            self.presets = Self.normalizedPresets(presets)
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
            self.supportedResolutions = Self.normalizedSupportedResolutions(supportedResolutions)
        }

        private enum CodingKeys: String, CodingKey {
            case presets
            case resolution
            case width
            case height
            case fps
            case fullscreenResolution
            case fullscreenFPS
            case prefersNativeFullscreenVideoMode
            case prefersNativeFullscreenRawMouseInput
            case bitrateKbps
            case packetSize
            case supportedResolutions
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decodedPresets = try container.decodeIfPresent([StreamPreset].self, forKey: .presets) {
                presets = Self.normalizedPresets(decodedPresets)
            } else {
                let windowedResolution: StreamConfiguration.Video.Resolution
                if let decodedResolution = try container.decodeIfPresent(StreamConfiguration.Video.Resolution.self, forKey: .resolution) {
                    windowedResolution = decodedResolution
                } else {
                    windowedResolution = StreamConfiguration.Video.Resolution(
                    width: try container.decodeIfPresent(Int.self, forKey: .width) ?? StreamConfiguration.fallback.video.resolution.width,
                    height: try container.decodeIfPresent(Int.self, forKey: .height) ?? StreamConfiguration.fallback.video.resolution.height
                )
                }

                let windowedFPS = Self.normalizedFPS(
                    try container.decodeIfPresent(Int.self, forKey: .fps) ?? StreamConfiguration.fallback.video.fps
                )
                let fullscreenResolution = try container.decodeIfPresent(StreamConfiguration.Video.Resolution.self, forKey: .fullscreenResolution)
                    ?? windowedResolution
                let fullscreenFPS = Self.normalizedFPS(
                    try container.decodeIfPresent(Int.self, forKey: .fullscreenFPS) ?? windowedFPS
                )
                let fullscreenMouseMode: StreamMouseModePreference =
                    (try container.decodeIfPresent(Bool.self, forKey: .prefersNativeFullscreenRawMouseInput) ?? true) ? .raw : .absolute

                presets = Self.normalizedPresets([
                    .init(
                        screenMode: .windowed,
                        resolution: windowedResolution,
                        fps: windowedFPS,
                        mouseMode: .absolute
                    ),
                    .init(
                        screenMode: .fullscreen,
                        resolution: fullscreenResolution,
                        fps: fullscreenFPS,
                        mouseMode: fullscreenMouseMode
                    ),
                    .init(
                        screenMode: .fullscreen,
                        resolution: fullscreenResolution,
                        fps: fullscreenFPS,
                        mouseMode: fullscreenMouseMode
                    ),
                    .init(
                        screenMode: .fullscreen,
                        resolution: fullscreenResolution,
                        fps: fullscreenFPS,
                        mouseMode: fullscreenMouseMode
                    )
                ])
            }
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? StreamConfiguration.fallback.video.bitrateKbps
            packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? StreamConfiguration.fallback.video.packetSize

            let decodedSupportedResolutions = try container.decodeIfPresent([StreamConfiguration.Video.Resolution].self, forKey: .supportedResolutions)
                ?? Self.defaultSupportedResolutions
            supportedResolutions = Self.normalizedSupportedResolutions(decodedSupportedResolutions)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(presets, forKey: .presets)
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

        public static func isSupportedFPS(_ fps: Int) -> Bool {
            fps > 0
        }

        public static func normalizedPresets(_ presets: [StreamPreset]) -> [StreamPreset] {
            var normalized = presets.prefix(StreamPresetID.allCases.count).map { preset in
                StreamPreset(
                    screenMode: preset.screenMode,
                    resolution: preset.resolution,
                    fps: preset.fps,
                    mouseMode: preset.mouseMode
                )
            }

            let defaults = defaultPresets
            while normalized.count < StreamPresetID.allCases.count {
                normalized.append(defaults[normalized.count])
            }

            return normalized
        }

        public func preset(_ id: StreamPresetID) -> StreamPreset {
            let normalized = Self.normalizedPresets(presets)
            return normalized[id.index]
        }

        public mutating func setPreset(_ preset: StreamPreset, for id: StreamPresetID) {
            presets = Self.normalizedPresets(presets)
            presets[id.index] = StreamPreset(
                screenMode: preset.screenMode,
                resolution: preset.resolution,
                fps: preset.fps,
                mouseMode: preset.mouseMode
            )
        }

        public static let defaultPresets: [StreamPreset] = [
            .init(
                screenMode: .windowed,
                resolution: StreamConfiguration.fallback.video.resolution,
                fps: StreamConfiguration.fallback.video.fps,
                mouseMode: .absolute
            ),
            .init(
                screenMode: .fullscreen,
                resolution: StreamConfiguration.fallback.video.resolution,
                fps: StreamConfiguration.fallback.video.fps,
                mouseMode: .raw
            ),
            .init(
                screenMode: .fullscreen,
                resolution: StreamConfiguration.fallback.video.resolution,
                fps: StreamConfiguration.fallback.video.fps,
                mouseMode: .raw
            ),
            .init(
                screenMode: .fullscreen,
                resolution: StreamConfiguration.fallback.video.resolution,
                fps: StreamConfiguration.fallback.video.fps,
                mouseMode: .raw
            )
        ]

        private static func normalizedFPS(_ fps: Int) -> Int {
            isSupportedFPS(fps) ? fps : StreamConfiguration.fallback.video.fps
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
    public var selectedStreamPresetID: StreamPresetID
    public var pendingPairingResetOnNextLaunch: Bool

    private enum CodingKeys: String, CodingKey {
        case host
        case input
        case video
        case selectedStreamPresetID
        case streamMode
        case launchesFullscreen
        case pendingPairingResetOnNextLaunch
    }

    public init(
        host: HostAuthority?,
        input: Input,
        video: Video,
        selectedStreamPresetID: StreamPresetID,
        pendingPairingResetOnNextLaunch: Bool
    ) {
        self.host = host
        self.input = input
        self.video = video
        self.selectedStreamPresetID = selectedStreamPresetID
        self.pendingPairingResetOnNextLaunch = pendingPairingResetOnNextLaunch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decodeIfPresent(HostAuthority.self, forKey: .host)
        input = try container.decodeIfPresent(Input.self, forKey: .input) ?? AppSettings.initial.input
        video = try container.decodeIfPresent(Video.self, forKey: .video) ?? AppSettings.initial.video
        if let decodedPresetID = try container.decodeIfPresent(StreamPresetID.self, forKey: .selectedStreamPresetID) {
            selectedStreamPresetID = decodedPresetID
        } else {
            let legacyMode: StreamMode
            if let decodedMode = try container.decodeIfPresent(StreamMode.self, forKey: .streamMode) {
                legacyMode = decodedMode
            } else {
                legacyMode = (try container.decodeIfPresent(Bool.self, forKey: .launchesFullscreen) ?? false) ? .fullscreen : .windowed
            }

            selectedStreamPresetID = legacyMode == .fullscreen ? .two : .one
        }
        pendingPairingResetOnNextLaunch = try container.decodeIfPresent(Bool.self, forKey: .pendingPairingResetOnNextLaunch) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encode(input, forKey: .input)
        try container.encode(video, forKey: .video)
        try container.encode(selectedStreamPresetID, forKey: .selectedStreamPresetID)
        try container.encode(pendingPairingResetOnNextLaunch, forKey: .pendingPairingResetOnNextLaunch)
    }
}

public extension AppSettings {
    static let initialWindowedVideo = Video(
        presets: Video.defaultPresets,
        bitrateKbps: StreamConfiguration.fallback.video.bitrateKbps,
        packetSize: StreamConfiguration.fallback.video.packetSize,
        supportedResolutions: AppSettings.Video.defaultSupportedResolutions
    )

    static let initial = AppSettings(
        host: nil,
        input: .init(rawMouseSensitivity: AppSettings.Input.defaultRawMouseSensitivity),
        video: initialWindowedVideo,
        selectedStreamPresetID: .one,
        pendingPairingResetOnNextLaunch: false
    )

    var selectedStreamPreset: StreamPreset {
        video.preset(selectedStreamPresetID)
    }

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

        let preset = selectedStreamPreset
        let requestedResolution = resolution ?? preset.resolution
        let requestedFPS = fps ?? preset.fps

        return StreamConfiguration(
            host: .init(address: host.address, port: host.port, appID: appID),
            session: .init(autoConnectOnLaunch: autoConnectOnLaunch, requestResume: requestResume),
            input: .init(rawMouseSensitivity: input.rawMouseSensitivity),
            video: .init(
                resolution: requestedResolution,
                fps: requestedFPS,
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

public enum StreamPresetID: String, Codable, CaseIterable, Sendable, Hashable {
    case one
    case two
    case three
    case four

    public var index: Int {
        switch self {
        case .one:
            return 0
        case .two:
            return 1
        case .three:
            return 2
        case .four:
            return 3
        }
    }
}

public enum StreamMouseModePreference: String, Codable, Sendable, Hashable {
    case absolute
    case raw
}

public enum AppSettingsError: Error, LocalizedError {
    case missingHost
    case unsupportedResolution
    case unsupportedFrameRate

    public var errorDescription: String? {
        switch self {
        case .missingHost:
            return "No host is configured."
        case .unsupportedResolution:
            return "Resolution must use positive even numbers."
        case .unsupportedFrameRate:
            return "Frame rate must be a positive integer."
        }
    }
}
