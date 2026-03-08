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
    private let configuration: MVPConfiguration
    private let pairedIdentity: PairedIdentityState
    private let launchSession: LaunchSessionContext

    public init(configuration: MVPConfiguration, pairedIdentity: PairedIdentityState, launchSession: LaunchSessionContext) {
        self.configuration = configuration
        self.pairedIdentity = pairedIdentity
        self.launchSession = launchSession
    }

    public func bootstrap() async throws -> BootstrappedServerInfo {
        let serverInfoFields = try fetchServerInfoFields()
        let rtspURL = try requestSessionRTSPURL(endpoint: "/launch", verb: "launch")

        let appVersion = serverInfoFields["appversion"] ?? HostSessionBootstrapDefaults.appVersion
        let gfeVersion = serverInfoFields["GfeVersion"] ?? HostSessionBootstrapDefaults.gfeVersion

        return BootstrappedServerInfo(
            appVersion: appVersion,
            gfeVersion: gfeVersion,
            rtspURL: rtspURL
        )
    }

    private func fetchServerInfoFields() throws -> [String: String] {
        let queryItems = [
            URLQueryItem(name: "uniqueid", value: pairedIdentity.uniqueID),
            URLQueryItem(name: "uuid", value: requestUUID())
        ]

        let httpsURL = try makeURL(scheme: "https", port: httpsPort, path: "/serverinfo", queryItems: queryItems)
        do {
            let fields = try requestXMLFields(url: httpsURL, useClientCertificate: true)
            try validateHostResponse(fields, endpoint: "/serverinfo")
            return fields
        } catch {
            let httpURL = try makeURL(scheme: "http", port: configuration.host.port, path: "/serverinfo", queryItems: queryItems)
            let fields = try requestXMLFields(url: httpURL, useClientCertificate: false)
            try validateHostResponse(fields, endpoint: "/serverinfo")
            return fields
        }
    }

    private func requestSessionRTSPURL(endpoint: String, verb: String) throws -> String {
        var queryItems = [
            URLQueryItem(name: "uniqueid", value: pairedIdentity.uniqueID),
            URLQueryItem(name: "uuid", value: requestUUID()),
            URLQueryItem(name: "appid", value: String(configuration.host.appID)),
            URLQueryItem(name: "mode", value: "\(configuration.video.resolution.width)x\(configuration.video.resolution.height)x\(configuration.video.fps)"),
            URLQueryItem(name: "additionalStates", value: "1"),
            URLQueryItem(name: "sops", value: configuration.video.vsync ? "1" : "0"),
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

        let url = try makeURL(scheme: "https", port: httpsPort, path: endpoint, queryItems: queryItems)
        let fields = try requestXMLFields(url: url, useClientCertificate: true)
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

    private func makeURL(scheme: String, port: Int, path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = configuration.host.address
        components.port = port
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw HostSessionBootstrapperError.invalidURL
        }

        return url
    }

    private func requestXMLFields(url: URL, useClientCertificate: Bool) throws -> [String: String] {
        let xmlText = try executeCurl(url: url, useClientCertificate: useClientCertificate)
        let parser = XMLFieldParser()
        parser.parse(data: Data(xmlText.utf8))
        return parser.fields
    }

    private func executeCurl(url: URL, useClientCertificate: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.qualityOfService = .userInitiated

        var arguments = [
            "--silent",
            "--show-error",
            "--fail-with-body",
            "--max-time", "12",
            "--get",
            url.absoluteString
        ]

        if url.scheme == "https" {
            arguments.append(contentsOf: ["--insecure"])
            if useClientCertificate {
                arguments.append(contentsOf: [
                    "--cert", pairedIdentity.certificateURL.path,
                    "--key", pairedIdentity.privateKeyURL.path
                ])
            }
        }

        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw HostSessionBootstrapperError.requestFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorOutput = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw HostSessionBootstrapperError.requestFailed(errorOutput.isEmpty ? output : errorOutput)
        }

        return output
    }
}

extension HostSessionBootstrapper: @unchecked Sendable {}

private final class XMLFieldParser: NSObject, XMLParserDelegate {
    private(set) var fields: [String: String] = [:]
    private var currentText = ""

    func parse(data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""

        if elementName == "root" {
            for (key, value) in attributeDict {
                fields[key] = value
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            fields[elementName] = trimmed
        }
        currentText = ""
    }
}
