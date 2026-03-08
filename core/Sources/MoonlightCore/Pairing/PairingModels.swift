import Foundation

public struct HostAuthority: Codable, Hashable, Sendable {
    public var address: String
    public var port: Int

    public init(address: String, port: Int) {
        self.address = address
        self.port = port
    }

    public var displayString: String {
        "\(address):\(port)"
    }
}

public struct PairingIdentity: Sendable {
    public var uniqueID: String
    public var certificatePEM: Data
    public var privateKeyPEM: Data
    public var certificateSignature: Data

    public init(uniqueID: String, certificatePEM: Data, privateKeyPEM: Data, certificateSignature: Data) {
        self.uniqueID = uniqueID
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.certificateSignature = certificateSignature
    }
}

public struct PairedHostRecord: Codable, Sendable {
    public var host: HostAuthority
    public var httpsPort: Int
    public var deviceName: String
    public var clientUniqueID: String
    public var appVersion: String?
    public var gfeVersion: String?
    public var serverCodecModeSupport: Int
    public var serverHashMatched: Bool
    public var pairedAt: Date

    public init(
        host: HostAuthority,
        httpsPort: Int,
        deviceName: String,
        clientUniqueID: String,
        appVersion: String?,
        gfeVersion: String?,
        serverCodecModeSupport: Int,
        serverHashMatched: Bool,
        pairedAt: Date
    ) {
        self.host = host
        self.httpsPort = httpsPort
        self.deviceName = deviceName
        self.clientUniqueID = clientUniqueID
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.serverCodecModeSupport = serverCodecModeSupport
        self.serverHashMatched = serverHashMatched
        self.pairedAt = pairedAt
    }

    private enum CodingKeys: String, CodingKey {
        case host
        case httpsPort
        case deviceName
        case clientUniqueID
        case appVersion
        case gfeVersion
        case serverCodecModeSupport
        case serverHashMatched
        case pairedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(HostAuthority.self, forKey: .host)
        httpsPort = try container.decodeIfPresent(Int.self, forKey: .httpsPort) ?? max(host.port - 5, 1)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "Moonlight"
        clientUniqueID = try container.decode(String.self, forKey: .clientUniqueID)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        gfeVersion = try container.decodeIfPresent(String.self, forKey: .gfeVersion)
        serverCodecModeSupport = try container.decodeIfPresent(Int.self, forKey: .serverCodecModeSupport) ?? 0
        serverHashMatched = try container.decodeIfPresent(Bool.self, forKey: .serverHashMatched) ?? false
        pairedAt = try container.decodeIfPresent(Date.self, forKey: .pairedAt) ?? .distantPast
    }
}

public struct PairingVerificationSummary: Codable, Sendable {
    public var pairStatus: String?
    public var currentGame: String?
    public var state: String?

    public init(pairStatus: String?, currentGame: String?, state: String?) {
        self.pairStatus = pairStatus
        self.currentGame = currentGame
        self.state = state
    }
}

public struct PairingSessionResult: Sendable {
    public var identity: PairingIdentity
    public var serverCertificatePEM: Data
    public var record: PairedHostRecord
    public var verificationSummary: PairingVerificationSummary?

    public init(
        identity: PairingIdentity,
        serverCertificatePEM: Data,
        record: PairedHostRecord,
        verificationSummary: PairingVerificationSummary?
    ) {
        self.identity = identity
        self.serverCertificatePEM = serverCertificatePEM
        self.record = record
        self.verificationSummary = verificationSummary
    }
}

public struct PairedHostArtifacts: Sendable {
    public var record: PairedHostRecord
    public var clientCertificatePEM: Data
    public var clientPrivateKeyPEM: Data
    public var serverCertificatePEM: Data?
    public var clientCertificateURL: URL
    public var clientPrivateKeyURL: URL
    public var serverCertificateURL: URL?

    public init(
        record: PairedHostRecord,
        clientCertificatePEM: Data,
        clientPrivateKeyPEM: Data,
        serverCertificatePEM: Data?,
        clientCertificateURL: URL,
        clientPrivateKeyURL: URL,
        serverCertificateURL: URL?
    ) {
        self.record = record
        self.clientCertificatePEM = clientCertificatePEM
        self.clientPrivateKeyPEM = clientPrivateKeyPEM
        self.serverCertificatePEM = serverCertificatePEM
        self.clientCertificateURL = clientCertificateURL
        self.clientPrivateKeyURL = clientPrivateKeyURL
        self.serverCertificateURL = serverCertificateURL
    }
}

public enum HostAuthorityParseError: Error, LocalizedError {
    case empty
    case invalidFormat
    case invalidPort

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter a host address in ip:port format."
        case .invalidFormat:
            return "Use host:port for the pairing target."
        case .invalidPort:
            return "The host port must be between 1 and 65535."
        }
    }
}

public extension HostAuthority {
    init(parsing rawValue: String, defaultPort: Int = 47989) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HostAuthorityParseError.empty
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else {
            throw HostAuthorityParseError.invalidFormat
        }

        let address = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            throw HostAuthorityParseError.invalidFormat
        }

        let port: Int
        if parts.count == 2 {
            let rawPort = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsedPort = Int(rawPort), (1...65535).contains(parsedPort) else {
                throw HostAuthorityParseError.invalidPort
            }
            port = parsedPort
        } else {
            port = defaultPort
        }

        self.init(address: address, port: port)
    }
}
