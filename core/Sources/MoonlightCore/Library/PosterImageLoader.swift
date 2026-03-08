import Foundation

public final class PosterImageLoader {
    private let httpClient: PairingHTTPClient
    private let paths: AppSupportPaths
    private let fileManager: FileManager

    public init(
        httpClient: PairingHTTPClient = PairingHTTPClient(),
        paths: AppSupportPaths = AppSupportPaths(),
        fileManager: FileManager = .default
    ) {
        self.httpClient = httpClient
        self.paths = paths
        self.fileManager = fileManager
    }

    public func cachedPosterURL(for applicationID: Int) -> URL? {
        let candidates = ["png", "jpg", "jpeg", "webp", "img"].map {
            paths.posterCacheDirectoryURL.appendingPathComponent("\(applicationID).\($0)")
        }
        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    public func ensurePoster(for application: HostApplication, using artifacts: PairedHostArtifacts) async -> URL? {
        if let cached = cachedPosterURL(for: application.id) {
            return cached
        }

        do {
            try paths.prepare()
            let queryItems = [
                URLQueryItem(name: "uniqueid", value: artifacts.record.clientUniqueID),
                URLQueryItem(name: "uuid", value: try PairingCrypto.randomUUIDHex()),
                URLQueryItem(name: "appid", value: String(application.id)),
                URLQueryItem(name: "AssetType", value: "2"),
                URLQueryItem(name: "AssetIdx", value: "0")
            ]

            let data = try await httpClient.getHTTPSData(
                host: artifacts.record.host,
                httpsPort: artifacts.record.httpsPort,
                path: "/appasset",
                queryItems: queryItems,
                identity: HTTPSClientIdentity(
                    certificateURL: artifacts.clientCertificateURL,
                    privateKeyURL: artifacts.clientPrivateKeyURL,
                    pinnedServerCertificatePEM: artifacts.serverCertificatePEM
                ),
                timeout: 15
            )

            guard let fileExtension = imageFileExtension(for: data) else {
                return nil
            }

            let destinationURL = paths.posterCacheDirectoryURL.appendingPathComponent("\(application.id).\(fileExtension)")
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            return nil
        }
    }

    private func imageFileExtension(for data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count >= 12,
           data.subdata(in: 8..<12) == Data([0x57, 0x45, 0x42, 0x50]) {
            return "webp"
        }
        return nil
    }
}

extension PosterImageLoader: @unchecked Sendable {}
