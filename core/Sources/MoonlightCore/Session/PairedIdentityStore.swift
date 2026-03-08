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
            return "No paired identity was found for \(hostAddress). Run the quick pair helper first."
        case let .missingFile(url):
            return "Missing paired identity file at \(url.path)."
        case let .invalidMetadata(url):
            return "Invalid paired identity metadata at \(url.path)."
        }
    }
}

public struct PairedIdentityStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL?
    private let currentDirectoryURL: URL
    private let executableURL: URL

    public init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectory
        self.currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        let argv0 = CommandLine.arguments.first ?? ""
        if argv0.hasPrefix("/") {
            self.executableURL = URL(fileURLWithPath: argv0)
        } else {
            self.executableURL = currentDirectoryURL.appendingPathComponent(argv0)
        }
    }

    public func load(forHostAddress hostAddress: String) throws -> PairedIdentityState {
        try loadDiscoveredIdentity(forHostAddress: hostAddress)
    }

    private func loadDiscoveredIdentity(forHostAddress hostAddress: String) throws -> PairedIdentityState {
        for root in searchRoots() {
            let quickPairDirectory = root.appendingPathComponent("tools/.quick-pair", isDirectory: true)
            guard fileManager.fileExists(atPath: quickPairDirectory.path) else {
                continue
            }

            if let state = try loadLatestIdentity(in: quickPairDirectory, forHostAddress: hostAddress) {
                return state
            }
        }

        throw PairedIdentityStoreError.missingPairedIdentity(hostAddress)
    }

    private func loadLatestIdentity(
        in quickPairDirectory: URL,
        forHostAddress hostAddress: String
    ) throws -> PairedIdentityState? {
        let contents = try fileManager.contentsOfDirectory(
            at: quickPairDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let candidates = contents
            .filter { $0.lastPathComponent.hasPrefix(hostAddress + "-") }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }

        for candidate in candidates {
            let metadataURL = candidate.appendingPathComponent("pairing.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else {
                continue
            }

            let metadataData = try Data(contentsOf: metadataURL)
            let metadata: QuickPairMetadata
            do {
                metadata = try JSONDecoder().decode(QuickPairMetadata.self, from: metadataData)
            } catch {
                throw PairedIdentityStoreError.invalidMetadata(metadataURL)
            }
            let certificateURL = candidate.appendingPathComponent(metadata.paths.clientCert)
            let privateKeyURL = candidate.appendingPathComponent(metadata.paths.clientKey)
            let serverCertificateURL = candidate.appendingPathComponent(metadata.paths.serverCert)

            let certificatePEM = try loadFile(at: certificateURL)
            let privateKeyPEM = try loadFile(at: privateKeyURL)
            let serverCertificatePEM = fileManager.fileExists(atPath: serverCertificateURL.path)
                ? try loadFile(at: serverCertificateURL)
                : nil

            return PairedIdentityState(
                uniqueID: metadata.clientUniqueId,
                certificatePEM: certificatePEM,
                privateKeyPEM: privateKeyPEM,
                serverCertificatePEM: serverCertificatePEM,
                certificateURL: certificateURL,
                privateKeyURL: privateKeyURL,
                serverCertificateURL: serverCertificatePEM == nil ? nil : serverCertificateURL
            )
        }

        return nil
    }

    private func loadFile(at url: URL) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw PairedIdentityStoreError.missingFile(url)
        }

        return try Data(contentsOf: url)
    }

    private static func discoveredRepositoryRoot(fileManager: FileManager) -> URL? {
        var currentURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        while true {
            let packageURL = currentURL.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageURL.path) {
                return currentURL
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                return nil
            }

            currentURL = parentURL
        }
    }

    private func searchRoots() -> [URL] {
        var roots: [URL] = []
        var seen: Set<String> = []

        let directRoots = [
            baseDirectoryURL,
            Self.discoveredRepositoryRoot(fileManager: fileManager),
            currentDirectoryURL,
            executableURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent()
        ].compactMap { $0?.standardizedFileURL }

        for root in directRoots {
            for ancestor in pathAncestors(of: root) {
                if seen.insert(ancestor.path).inserted {
                    roots.append(ancestor)
                }
            }
        }

        return roots
    }

    private func pathAncestors(of start: URL) -> [URL] {
        var results: [URL] = []
        var currentPath = start.standardizedFileURL.path

        while true {
            results.append(URL(fileURLWithPath: currentPath, isDirectory: true))
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }

        if results.last?.path != "/" {
            results.append(URL(fileURLWithPath: "/", isDirectory: true))
        }

        return results
    }
}

private struct QuickPairMetadata: Decodable {
    struct Paths: Decodable {
        var clientCert: String
        var clientKey: String
        var serverCert: String
    }

    var clientUniqueId: String
    var paths: Paths
}
