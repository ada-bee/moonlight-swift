import Foundation

public struct HostRunningStatus: Equatable, Sendable {
    public var currentApplicationID: Int

    public init(currentApplicationID: Int) {
        self.currentApplicationID = currentApplicationID
    }
}

public enum HostLibraryClientError: Error, LocalizedError {
    case stopTimedOut

    public var errorDescription: String? {
        switch self {
        case .stopTimedOut:
            return "The host kept the current app running after the stop request. You may need to stop it from the device that launched it."
        }
    }
}

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

    public func fetchRunningStatus(using artifacts: PairedHostArtifacts) async throws -> HostRunningStatus {
        let response = try await httpClient.getHTTPSXML(
            host: artifacts.record.host,
            httpsPort: artifacts.record.httpsPort,
            path: "/serverinfo",
            queryItems: try commonQueryItems(uniqueID: artifacts.record.clientUniqueID),
            identity: HTTPSClientIdentity(
                certificateURL: artifacts.clientCertificateURL,
                privateKeyURL: artifacts.clientPrivateKeyURL,
                pinnedServerCertificatePEM: artifacts.serverCertificatePEM
            ),
            timeout: 12
        )
        try response.requireOK(action: "/serverinfo")

        let state = response.value(for: "state")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentApplicationID: Int
        if state.hasSuffix("_SERVER_BUSY") {
            currentApplicationID = Int(response.value(for: "currentgame") ?? "") ?? 0
        } else {
            currentApplicationID = 0
        }

        return HostRunningStatus(currentApplicationID: currentApplicationID)
    }

    public func stopRunningApplication(using artifacts: PairedHostArtifacts) async throws {
        let response = try await httpClient.getHTTPSXML(
            host: artifacts.record.host,
            httpsPort: artifacts.record.httpsPort,
            path: "/cancel",
            queryItems: try commonQueryItems(uniqueID: artifacts.record.clientUniqueID),
            identity: HTTPSClientIdentity(
                certificateURL: artifacts.clientCertificateURL,
                privateKeyURL: artifacts.clientPrivateKeyURL,
                pinnedServerCertificatePEM: artifacts.serverCertificatePEM
            ),
            timeout: 30
        )
        try response.requireOK(action: "/cancel")

        let timeoutDeadline = Date().addingTimeInterval(30)

        while true {
            try Task.checkCancellation()

            let runningStatus = try await fetchRunningStatus(using: artifacts)
            if runningStatus.currentApplicationID == 0 {
                return
            }

            guard Date() < timeoutDeadline else {
                throw HostLibraryClientError.stopTimedOut
            }

            try await Task.sleep(nanoseconds: 500_000_000)
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
