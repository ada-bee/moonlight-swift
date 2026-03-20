import Foundation

public struct StreamConfiguration: Sendable, Codable {
    public struct Input: Sendable, Codable {
        public var rawMouseSensitivity: Double

        public init(rawMouseSensitivity: Double) {
            self.rawMouseSensitivity = Self.clampedRawMouseSensitivity(rawMouseSensitivity)
        }

        public static func clampedRawMouseSensitivity(_ value: Double) -> Double {
            min(max(value, 0.1), 4.0)
        }

        public var effectiveRawMouseScale: Double {
            rawMouseSensitivity
        }
    }

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
        public var requestResume: Bool

        public init(autoConnectOnLaunch: Bool, requestResume: Bool = false) {
            self.autoConnectOnLaunch = autoConnectOnLaunch
            self.requestResume = requestResume
        }

        private enum CodingKeys: String, CodingKey {
            case autoConnectOnLaunch
            case requestResume
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? true
            requestResume = try container.decodeIfPresent(Bool.self, forKey: .requestResume) ?? false
        }
    }

    public struct Video: Sendable, Codable {
        public struct Resolution: Sendable, Codable, Hashable {
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
                width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 1920
                height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1080
            }
        }

        public var resolution: Resolution
        public var fps: Int
        public var bitrateKbps: Int
        public var packetSize: Int

        public init(
            resolution: Resolution,
            fps: Int,
            bitrateKbps: Int,
            packetSize: Int
        ) {
            self.resolution = resolution
            self.fps = fps
            self.bitrateKbps = bitrateKbps
            self.packetSize = packetSize
        }

        private enum CodingKeys: String, CodingKey {
            case resolution
            case fps
            case bitrateKbps
            case packetSize
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            resolution = try container.decodeIfPresent(Resolution.self, forKey: .resolution) ?? .init(width: 1920, height: 1080)
            fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 60
            bitrateKbps = try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? 30_000
            packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? 1392
        }
    }

    public var host: Host
    public var session: Session
    public var input: Input
    public var video: Video

    public init(
        host: Host,
        session: Session,
        input: Input,
        video: Video
    ) {
        self.host = host
        self.session = session
        self.input = input
        self.video = video
    }
}

public extension StreamConfiguration {
    static let fallback = StreamConfiguration(
        host: .init(
            address: "192.168.1.10",
            port: 47989,
            appID: 881448767
        ),
        session: .init(autoConnectOnLaunch: true, requestResume: false),
        input: .init(rawMouseSensitivity: 1.0),
        video: .init(
            resolution: .init(width: 1920, height: 1080),
            fps: 60,
            bitrateKbps: 30000,
            packetSize: 1392
        )
    )
}
