import AppKit
import CMoonlightCommon
import Foundation

public enum HostSessionBootstrapperError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case invalidResponseStatus(Int)
    case missingField(String)
    case requestRejected(endpoint: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct Sunshine bootstrap URL."
        case let .requestFailed(message):
            return "Sunshine bootstrap request failed: \(message)"
        case let .invalidResponseStatus(statusCode):
            return "Sunshine bootstrap returned HTTP status \(statusCode)."
        case let .missingField(field):
            return "Missing required Sunshine field: \(field)."
        case let .requestRejected(endpoint, message):
            return "Sunshine \(endpoint) rejected the session request: \(message)"
        }
    }
}

public struct BootstrappedServerInfo: Sendable {
    public var appVersion: String
    public var gfeVersion: String
    public var rtspURL: String
}

private enum HostSessionBootstrapDefaults {
    static let appVersion = "7.1.431.0"
    static let gfeVersion = "3.23.0.74"
}

public final class HostSessionBootstrapper {
    private let configuration: StreamConfiguration
    private let pairedIdentity: PairedIdentityState
    private let launchSession: LaunchSessionContext
    private let httpClient: PairingHTTPClient

    public init(
        configuration: StreamConfiguration,
        pairedIdentity: PairedIdentityState,
        launchSession: LaunchSessionContext,
        httpClient: PairingHTTPClient = PairingHTTPClient()
    ) {
        self.configuration = configuration
        self.pairedIdentity = pairedIdentity
        self.launchSession = launchSession
        self.httpClient = httpClient
    }

    public func bootstrap() async throws -> BootstrappedServerInfo {
        let serverInfoFields = try await fetchServerInfoFields()
        let endpoint = configuration.session.requestResume ? "/resume" : "/launch"
        let verb = configuration.session.requestResume ? "resume" : "launch"
        let rtspURL = try await requestSessionRTSPURL(endpoint: endpoint, verb: verb)

        let appVersion = serverInfoFields["appversion"] ?? HostSessionBootstrapDefaults.appVersion
        let gfeVersion = serverInfoFields["GfeVersion"] ?? HostSessionBootstrapDefaults.gfeVersion

        return BootstrappedServerInfo(
            appVersion: appVersion,
            gfeVersion: gfeVersion,
            rtspURL: rtspURL
        )
    }

    private func fetchServerInfoFields() async throws -> [String: String] {
        let queryItems = [
            URLQueryItem(name: "uniqueid", value: pairedIdentity.uniqueID),
            URLQueryItem(name: "uuid", value: requestUUID())
        ]

        do {
            let response = try await httpClient.getHTTPSXML(
                host: .init(address: configuration.host.address, port: configuration.host.port),
                httpsPort: httpsPort,
                path: "/serverinfo",
                queryItems: queryItems,
                identity: HTTPSClientIdentity(
                    certificateURL: pairedIdentity.certificateURL,
                    privateKeyURL: pairedIdentity.privateKeyURL,
                    pinnedServerCertificatePEM: pairedIdentity.serverCertificatePEM
                ),
                timeout: 12
            )
            try response.requireOK(action: "/serverinfo")
            return combinedFields(from: response)
        } catch {
            let response = try await httpClient.getHTTPXML(
                host: .init(address: configuration.host.address, port: configuration.host.port),
                path: "/serverinfo",
                queryItems: queryItems,
                timeout: 12
            )
            try response.requireOK(action: "/serverinfo")
            return combinedFields(from: response)
        }
    }

    private func requestSessionRTSPURL(endpoint: String, verb: String) async throws -> String {
        var queryItems = [
            URLQueryItem(name: "uniqueid", value: pairedIdentity.uniqueID),
            URLQueryItem(name: "uuid", value: requestUUID()),
            URLQueryItem(name: "appid", value: String(configuration.host.appID)),
            URLQueryItem(name: "mode", value: "\(configuration.video.resolution.width)x\(configuration.video.resolution.height)x\(configuration.video.fps)"),
            URLQueryItem(name: "additionalStates", value: "1"),
            URLQueryItem(name: "sops", value: "1"),
            URLQueryItem(name: "rikey", value: launchSession.riKeyHex),
            URLQueryItem(name: "rikeyid", value: String(launchSession.riKeyID)),
            URLQueryItem(name: "localAudioPlayMode", value: "0"),
            URLQueryItem(name: "surroundAudioInfo", value: String((0x3 << 16) | 2)),
            URLQueryItem(name: "remoteControllersBitmap", value: "0"),
            URLQueryItem(name: "gcmap", value: "0")
        ]

        let launchExtras = String(cString: LiGetLaunchUrlQueryParameters())
        if launchExtras.contains("corever=1") {
            queryItems.append(URLQueryItem(name: "corever", value: "1"))
        }

        let response = try await httpClient.getHTTPSXML(
            host: .init(address: configuration.host.address, port: configuration.host.port),
            httpsPort: httpsPort,
            path: endpoint,
            queryItems: queryItems,
            identity: HTTPSClientIdentity(
                certificateURL: pairedIdentity.certificateURL,
                privateKeyURL: pairedIdentity.privateKeyURL,
                pinnedServerCertificatePEM: pairedIdentity.serverCertificatePEM
            ),
            timeout: 12
        )
        try response.requireOK(action: endpoint)
        let fields = combinedFields(from: response)

        try validateHostResponse(fields, endpoint: endpoint)
        try validateSessionResponse(fields, endpoint: endpoint, verb: verb)

        if let sessionURL = fields["sessionUrl0"], !sessionURL.isEmpty {
            return sessionURL
        }

        return "rtsp://\(configuration.host.address):48010"
    }

    private func validateSessionResponse(_ fields: [String: String], endpoint: String, verb: String) throws {
        let statusFieldName = verb == "resume" ? "resume" : "gamesession"
        if let statusField = fields[statusFieldName], statusField != "0", !statusField.isEmpty {
            return
        }

        if let sessionURL = fields["sessionUrl0"], !sessionURL.isEmpty {
            return
        }

        let statusMessage = fields["status_message"] ?? "No session details returned"
        throw HostSessionBootstrapperError.requestRejected(endpoint: endpoint, message: statusMessage)
    }

    private func validateHostResponse(_ fields: [String: String], endpoint: String) throws {
        guard let statusCodeText = fields["status_code"], let statusCode = Int(statusCodeText) else {
            return
        }

        guard statusCode == 200 else {
            let statusMessage = fields["status_message"] ?? "Unknown error"
            throw HostSessionBootstrapperError.requestFailed(
                "Sunshine \(endpoint) returned status \(statusCode): \(statusMessage)"
            )
        }
    }

    private var httpsPort: Int {
        max(configuration.host.port - 5, 1)
    }

    private func requestUUID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func combinedFields(from response: PairingXMLResponse) -> [String: String] {
        response.rootAttributes.merging(response.fields, uniquingKeysWith: { _, new in new })
    }
}

extension HostSessionBootstrapper: @unchecked Sendable {}
