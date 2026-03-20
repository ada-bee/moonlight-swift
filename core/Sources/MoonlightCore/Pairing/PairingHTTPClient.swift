import CMoonlightBridgeSupport
import Foundation

public struct HTTPSClientIdentity: Sendable {
    public var certificateURL: URL
    public var privateKeyURL: URL
    public var pinnedServerCertificatePEM: Data?

    public init(certificateURL: URL, privateKeyURL: URL, pinnedServerCertificatePEM: Data?) {
        self.certificateURL = certificateURL
        self.privateKeyURL = privateKeyURL
        self.pinnedServerCertificatePEM = pinnedServerCertificatePEM
    }
}

public final class PairingHTTPClient {
    private let session: URLSession
    private let identityMaterialCache = HTTPSIdentityMaterialCache()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func getHTTPXML(host: HostAuthority, path: String, queryItems: [URLQueryItem], timeout: TimeInterval) async throws -> PairingXMLResponse {
        let data = try await getHTTPData(host: host, path: path, queryItems: queryItems, timeout: timeout)
        return try PairingXML.parseResponse(data: data)
    }

    public func getHTTPData(host: HostAuthority, path: String, queryItems: [URLQueryItem], timeout: TimeInterval) async throws -> Data {
        let url = try makeURL(scheme: "http", host: host.address, port: host.port, path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PairingError.requestFailed(error.localizedDescription)
        }

        try validateHTTPResponse(response, data: data, action: path)
        return data
    }

    public func getHTTPSXML(
        host: HostAuthority,
        httpsPort: Int,
        path: String,
        queryItems: [URLQueryItem],
        identity: HTTPSClientIdentity,
        timeout: TimeInterval
    ) async throws -> PairingXMLResponse {
        let data = try await getHTTPSData(
            host: host,
            httpsPort: httpsPort,
            path: path,
            queryItems: queryItems,
            identity: identity,
            timeout: timeout
        )
        return try PairingXML.parseResponse(data: data)
    }

    public func getHTTPSData(
        host: HostAuthority,
        httpsPort: Int,
        path: String,
        queryItems: [URLQueryItem],
        identity: HTTPSClientIdentity,
        timeout: TimeInterval
    ) async throws -> Data {
        let url = try makeURL(scheme: "https", host: host.address, port: httpsPort, path: path, queryItems: queryItems)
        let identityMaterial = try await identityMaterialCache.material(for: identity)
        let pathAndQuery = url.path + (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery.map { "?\($0)" } ?? "")

        return try await Task.detached(priority: .userInitiated) {
            try Self.performHTTPSGet(
                host: host.address,
                port: httpsPort,
                pathAndQuery: pathAndQuery,
                certificatePEM: identityMaterial.certificatePEM,
                privateKeyPEM: identityMaterial.privateKeyPEM,
                pinnedServerCertificatePEM: identity.pinnedServerCertificatePEM,
                action: path,
                timeout: timeout
            )
        }.value
    }

    private func makeURL(scheme: String, host: String, port: Int, path: String, queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PairingError.invalidURL
        }

        return url
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, action: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PairingError.requestFailed("Missing HTTP response metadata")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PairingError.invalidResponseStatus(
                action: action,
                code: httpResponse.statusCode,
                message: String(data: data, encoding: .utf8)
            )
        }
    }

    private static func performHTTPSGet(
        host: String,
        port: Int,
        pathAndQuery: String,
        certificatePEM: Data,
        privateKeyPEM: Data,
        pinnedServerCertificatePEM: Data?,
        action: String,
        timeout: TimeInterval
    ) throws -> Data {
        _ = timeout

        var outputBytes: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        var statusCode: Int32 = 0
        var errorMessage: UnsafeMutablePointer<CChar>?

        let result = certificatePEM.withUnsafeBytes { certificateBuffer in
            privateKeyPEM.withUnsafeBytes { privateKeyBuffer in
                pinnedServerCertificatePEM.withOptionalUnsafeBytes { pinnedBuffer, pinnedLength in
                    MoonlightBridgeHTTPSGet(
                        host,
                        Int32(port),
                        pathAndQuery,
                        certificateBuffer.bindMemory(to: UInt8.self).baseAddress,
                        certificatePEM.count,
                        privateKeyBuffer.bindMemory(to: UInt8.self).baseAddress,
                        privateKeyPEM.count,
                        pinnedBuffer,
                        pinnedLength,
                        &outputBytes,
                        &outputLength,
                        &statusCode,
                        &errorMessage
                    )
                }
            }
        }

        if let errorMessage {
            defer { MoonlightBridgeFreeBytes(errorMessage) }
            let message = String(cString: errorMessage)
            guard result == 0 else {
                throw PairingError.requestFailed(message)
            }
        }

        guard result == 0, let outputBytes else {
            throw PairingError.requestFailed("HTTPS request failed")
        }

        defer { MoonlightBridgeFreeBytes(outputBytes) }
        let data = Data(bytes: outputBytes, count: outputLength)

        guard (200..<300).contains(statusCode) else {
            throw PairingError.invalidResponseStatus(
                action: action,
                code: Int(statusCode),
                message: String(data: data, encoding: .utf8)
            )
        }

        return data
    }
}

extension PairingHTTPClient: @unchecked Sendable {}

private actor HTTPSIdentityMaterialCache {
    private struct CacheKey: Hashable, Sendable {
        let certificateURL: URL
        let privateKeyURL: URL
    }

    private struct CachedFileData: Sendable {
        let modificationDate: Date?
        let fileSize: Int?
        let data: Data
    }

    private struct CachedIdentityMaterial: Sendable {
        let certificate: CachedFileData
        let privateKey: CachedFileData

        var material: HTTPSIdentityMaterial {
            HTTPSIdentityMaterial(
                certificatePEM: certificate.data,
                privateKeyPEM: privateKey.data
            )
        }
    }

    private var cache: [CacheKey: CachedIdentityMaterial] = [:]

    func material(for identity: HTTPSClientIdentity) throws -> HTTPSIdentityMaterial {
        let key = CacheKey(certificateURL: identity.certificateURL, privateKeyURL: identity.privateKeyURL)
        let cachedMaterial = cache[key]

        let certificate = try loadFileData(at: identity.certificateURL, cached: cachedMaterial?.certificate)
        let privateKey = try loadFileData(at: identity.privateKeyURL, cached: cachedMaterial?.privateKey)
        let refreshedMaterial = CachedIdentityMaterial(certificate: certificate, privateKey: privateKey)
        cache[key] = refreshedMaterial
        return refreshedMaterial.material
    }

    private func loadFileData(at url: URL, cached: CachedFileData?) throws -> CachedFileData {
        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationDate = resourceValues.contentModificationDate
        let fileSize = resourceValues.fileSize

        if let cached,
           cached.modificationDate == modificationDate,
           cached.fileSize == fileSize {
            return cached
        }

        return CachedFileData(
            modificationDate: modificationDate,
            fileSize: fileSize,
            data: try Data(contentsOf: url)
        )
    }
}

private struct HTTPSIdentityMaterial: Sendable {
    let certificatePEM: Data
    let privateKeyPEM: Data
}

private extension Optional where Wrapped == Data {
    func withOptionalUnsafeBytes<T>(_ body: (UnsafePointer<UInt8>?, Int) throws -> T) rethrows -> T {
        switch self {
        case let .some(data):
            return try data.withUnsafeBytes { rawBuffer in
                try body(rawBuffer.bindMemory(to: UInt8.self).baseAddress, data.count)
            }
        case .none:
            return try body(nil, 0)
        }
    }
}
