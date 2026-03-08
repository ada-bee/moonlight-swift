import Foundation

public struct PairedIdentityState: Sendable {
    public var uniqueID: String
    public var certificatePEM: Data
    public var privateKeyPEM: Data
    public var serverCertificatePEM: Data?
    public var certificateURL: URL
    public var privateKeyURL: URL
    public var serverCertificateURL: URL?

    public init(
        uniqueID: String,
        certificatePEM: Data,
        privateKeyPEM: Data,
        serverCertificatePEM: Data?,
        certificateURL: URL,
        privateKeyURL: URL,
        serverCertificateURL: URL?
    ) {
        self.uniqueID = uniqueID
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.serverCertificatePEM = serverCertificatePEM
        self.certificateURL = certificateURL
        self.privateKeyURL = privateKeyURL
        self.serverCertificateURL = serverCertificateURL
    }
}

public enum PairedIdentityStoreError: Error, LocalizedError {
    case missingPairedIdentity(String)
    case missingFile(URL)
    case invalidMetadata(URL)

    public var errorDescription: String? {
        switch self {
        case let .missingPairedIdentity(hostAddress):
            return "No paired identity was found for \(hostAddress)."
        case let .missingFile(url):
            return "Missing paired identity file at \(url.path)."
        case let .invalidMetadata(url):
            return "Invalid paired identity metadata at \(url.path)."
        }
    }
}

public struct PairedIdentityStore {
    private let pairedHostStore: PairedHostStore

    public init(pairedHostStore: PairedHostStore = PairedHostStore()) {
        self.pairedHostStore = pairedHostStore
    }

    public func load(forHostAddress hostAddress: String) throws -> PairedIdentityState {
        guard let state = try loadApplicationSupportIdentity(forHostAddress: hostAddress) else {
            throw PairedIdentityStoreError.missingPairedIdentity(hostAddress)
        }

        return state
    }

    private func loadApplicationSupportIdentity(forHostAddress hostAddress: String) throws -> PairedIdentityState? {
        guard let artifacts = try pairedHostStore.loadCurrentArtifacts() else {
            return nil
        }

        guard artifacts.record.host.address == hostAddress else {
            return nil
        }

        return PairedIdentityState(
            uniqueID: artifacts.record.clientUniqueID,
            certificatePEM: artifacts.clientCertificatePEM,
            privateKeyPEM: artifacts.clientPrivateKeyPEM,
            serverCertificatePEM: artifacts.serverCertificatePEM,
            certificateURL: artifacts.clientCertificateURL,
            privateKeyURL: artifacts.clientPrivateKeyURL,
            serverCertificateURL: artifacts.serverCertificateURL
        )
    }
}
