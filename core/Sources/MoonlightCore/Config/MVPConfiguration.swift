import Foundation

public struct MVPConfiguration: Sendable, Codable {
    public struct Host: Sendable, Codable {
        public var address: String
        public var port: Int
        public var appID: Int

        public init(
            address: String,
            port: Int,
            appID: Int
        ) {
            self.address = address
            self.port = port
            self.appID = appID
        }

        private enum CodingKeys: String, CodingKey {
            case address
            case port
            case appID
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try container.decode(String.self, forKey: .address)
            port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 47989
            appID = try container.decodeIfPresent(Int.self, forKey: .appID) ?? 881448767
        }
    }

    public struct Session: Sendable, Codable {
        public var autoConnectOnLaunch: Bool

        public init(autoConnectOnLaunch: Bool) {
            self.autoConnectOnLaunch = autoConnectOnLaunch
        }

        private enum CodingKeys: String, CodingKey {
            case autoConnectOnLaunch
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
        }
    }

    public struct Video: Sendable, Codable {
        public struct Resolution: Sendable, Codable {
            public var width: Int
            public var height: Int

            public init(width: Int, height: Int) {
                self.width = width
                self.height = height
            }

            private enum CodingKeys: String, CodingKey {
                case width
                case height
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 2560
                height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1440
            }
        }

        public var resolution: Resolution
        public var fps: Int
        public var vsync: Bool
        public var bitrateKbps: Int
        public var packetSize: Int

        public init(
            resolution: Resolution,
            fps: Int,
            vsync: Bool,
            bitrateKbps: Int,
            packetSize: Int
        ) {
            self.resolution = resolution
            self.fps = fps
            self.vsync = vsync
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
        }

        private enum CodingKeys: String, CodingKey {
            case resolution
            case fps
            case vsync
            case bitrateKbps
            case packetSize
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resolution = try container.decodeIfPresent(Resolution.self, forKey: .resolution) ?? .init(width: 2560, height: 1440)
            fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 120
            vsync = try container.decodeIfPresent(Bool.self, forKey: .vsync) ?? true
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? 80_000
            packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? 1392
        }
    }

    public var host: Host
    public var session: Session
    public var video: Video

    public init(
        host: Host,
        session: Session,
        video: Video
    ) {
        self.host = host
        self.session = session
        self.video = video
    }
}

public extension MVPConfiguration {
    static let fallback = MVPConfiguration(
        host: .init(
            address: "192.168.1.10",
            port: 47989,
            appID: 881448767
        ),
        session: .init(autoConnectOnLaunch: true),
        video: .init(
            resolution: .init(width: 2560, height: 1440),
            fps: 120,
            vsync: true,
            bitrateKbps: 80000,
            packetSize: 1392
        )
    )
}
