import Foundation

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
    public var pendingPairingResetOnNextLaunch: Bool

    public init(
        host: HostAuthority?,
        video: Video,
        pendingPairingResetOnNextLaunch: Bool
    ) {
        self.host = host
        self.video = video
        self.pendingPairingResetOnNextLaunch = pendingPairingResetOnNextLaunch
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
        pendingPairingResetOnNextLaunch: false
    )

    func makeConfiguration(appID: Int, autoConnectOnLaunch: Bool = false) throws -> MVPConfiguration {
        guard let host else {
            throw AppSettingsError.missingHost
        }

        return MVPConfiguration(
            host: .init(address: host.address, port: host.port, appID: appID),
            session: .init(autoConnectOnLaunch: autoConnectOnLaunch),
            video: .init(
                resolution: .init(width: video.width, height: video.height),
                fps: video.fps,
                vsync: video.vsync,
                bitrateKbps: video.bitrateKbps,
                packetSize: video.packetSize
            )
        )
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
