import Foundation

public enum PairedHostStoreError: Error, LocalizedError {
    case invalidMetadata(URL)
    case missingFile(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidMetadata(url):
            return "Invalid paired host metadata at \(url.path)."
        case let .missingFile(url):
            return "Missing paired host file at \(url.path)."
        }
    }
}

public struct PairedHostStore {
    public let fileManager: FileManager
    public let paths: AppSupportPaths

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        paths: AppSupportPaths = AppSupportPaths(),
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.paths = paths

        let configuredEncoder = encoder
        configuredEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = configuredEncoder
        self.decoder = decoder
    }

    public var metadataURL: URL {
        paths.currentPairingDirectoryURL.appendingPathComponent("pairing.json", isDirectory: false)
    }

    public var clientCertificateURL: URL {
        paths.currentPairingDirectoryURL.appendingPathComponent("client-cert.pem", isDirectory: false)
    }

    public var clientPrivateKeyURL: URL {
        paths.currentPairingDirectoryURL.appendingPathComponent("client-key.pem", isDirectory: false)
    }

    public var serverCertificateURL: URL {
        paths.currentPairingDirectoryURL.appendingPathComponent("server-cert.pem", isDirectory: false)
    }

    public func hasPairedHost() -> Bool {
        fileManager.fileExists(atPath: metadataURL.path)
            && fileManager.fileExists(atPath: clientCertificateURL.path)
            && fileManager.fileExists(atPath: clientPrivateKeyURL.path)
    }

    public func loadCurrentRecord() throws -> PairedHostRecord? {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: metadataURL)

        do {
            return try decoder.decode(PairedHostRecord.self, from: data)
        } catch {
            throw PairedHostStoreError.invalidMetadata(metadataURL)
        }
    }

    public func loadCurrentArtifacts() throws -> PairedHostArtifacts? {
        guard let record = try loadCurrentRecord() else {
            return nil
        }

        let clientCertificatePEM = try loadFile(at: clientCertificateURL)
        let clientPrivateKeyPEM = try loadFile(at: clientPrivateKeyURL)
        let serverCertificatePEM = fileManager.fileExists(atPath: serverCertificateURL.path)
            ? try loadFile(at: serverCertificateURL)
            : nil

        return PairedHostArtifacts(
            record: record,
            clientCertificatePEM: clientCertificatePEM,
            clientPrivateKeyPEM: clientPrivateKeyPEM,
            serverCertificatePEM: serverCertificatePEM,
            clientCertificateURL: clientCertificateURL,
            clientPrivateKeyURL: clientPrivateKeyURL,
            serverCertificateURL: serverCertificatePEM == nil ? nil : serverCertificateURL
        )
    }

    public func saveCurrent(
        record: PairedHostRecord,
        clientCertificatePEM: Data,
        clientPrivateKeyPEM: Data,
        serverCertificatePEM: Data?
    ) throws {
        try paths.prepare()
        try paths.createDirectoryIfNeeded(paths.currentPairingDirectoryURL)

        let metadataData = try encoder.encode(record)
        try metadataData.write(to: metadataURL, options: .atomic)
        try clientCertificatePEM.write(to: clientCertificateURL, options: .atomic)
        try clientPrivateKeyPEM.write(to: clientPrivateKeyURL, options: .atomic)

        if let serverCertificatePEM {
            try serverCertificatePEM.write(to: serverCertificateURL, options: .atomic)
        } else if fileManager.fileExists(atPath: serverCertificateURL.path) {
            try fileManager.removeItem(at: serverCertificateURL)
        }
    }

    public func save(result: PairingSessionResult) throws {
        try saveCurrent(
            record: result.record,
            clientCertificatePEM: result.identity.certificatePEM,
            clientPrivateKeyPEM: result.identity.privateKeyPEM,
            serverCertificatePEM: result.serverCertificatePEM
        )
    }

    public func removeCurrent() throws {
        guard fileManager.fileExists(atPath: paths.currentPairingDirectoryURL.path) else {
            return
        }

        try fileManager.removeItem(at: paths.currentPairingDirectoryURL)
    }

    public func removeAll() throws {
        guard fileManager.fileExists(atPath: paths.pairingDirectoryURL.path) else {
            return
        }

        try fileManager.removeItem(at: paths.pairingDirectoryURL)
    }

    private func loadFile(at url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw PairedHostStoreError.missingFile(url)
        }

        return try Data(contentsOf: url)
    }
}
