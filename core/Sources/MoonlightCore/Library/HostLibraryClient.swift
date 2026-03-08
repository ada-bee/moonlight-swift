import Foundation

public final class HostLibraryClient {
    private let httpClient: PairingHTTPClient

    public init(httpClient: PairingHTTPClient = PairingHTTPClient()) {
        self.httpClient = httpClient
    }

    public func fetchApplications(using artifacts: PairedHostArtifacts) async throws -> [HostApplication] {
        let queryItems = try commonQueryItems(uniqueID: artifacts.record.clientUniqueID)

        let data = try await httpClient.getHTTPSData(
            host: artifacts.record.host,
            httpsPort: artifacts.record.httpsPort,
            path: "/applist",
            queryItems: queryItems,
            identity: HTTPSClientIdentity(
                certificateURL: artifacts.clientCertificateURL,
                privateKeyURL: artifacts.clientPrivateKeyURL,
                pinnedServerCertificatePEM: artifacts.serverCertificatePEM
            ),
            timeout: 15
        )

        return try HostLibraryXML.parseApplications(from: data)
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func commonQueryItems(uniqueID: String) throws -> [URLQueryItem] {
        [
            URLQueryItem(name: "uniqueid", value: uniqueID),
            URLQueryItem(name: "uuid", value: try PairingCrypto.randomUUIDHex())
        ]
    }
}

extension HostLibraryClient: @unchecked Sendable {}
