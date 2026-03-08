import Foundation

public final class PairingService {
    private let httpClient: PairingHTTPClient

    public init(httpClient: PairingHTTPClient = PairingHTTPClient()) {
        self.httpClient = httpClient
    }

    public func pair(
        host: HostAuthority,
        deviceName: String,
        pin: String,
        requestTimeout: TimeInterval = 300,
        skipVerifyCheck: Bool = false,
        progress: (@Sendable (String) async -> Void)? = nil
    ) async throws -> PairingSessionResult {
        try Task.checkCancellation()
        await progress?("Generating client credentials")
        let identity = try PairingCrypto.generateIdentity()

        try Task.checkCancellation()
        await progress?("Fetching host info")
        let serverInfo = try await httpClient.getHTTPXML(
            host: host,
            path: "/serverinfo",
            queryItems: [
                URLQueryItem(name: "uniqueid", value: identity.uniqueID),
                URLQueryItem(name: "uuid", value: try PairingCrypto.randomUUIDHex())
            ],
            timeout: 15
        )
        try serverInfo.requireOK(action: "serverinfo")

        let httpsPort = Int(serverInfo.value(for: "HttpsPort") ?? "") ?? max(host.port - 5, 1)
        let appVersion = serverInfo.value(for: "appversion")
        let gfeVersion = serverInfo.value(for: "GfeVersion")
        let serverCodecModeSupport = Int(serverInfo.value(for: "ServerCodecModeSupport") ?? "0") ?? 0

        try Task.checkCancellation()
        await progress?("Requesting server certificate")
        let salt = try PairingCrypto.randomBytes(count: 16)
        let phase1 = try await pairRequest(
            host: host,
            params: [
                "uniqueid": identity.uniqueID,
                "uuid": try PairingCrypto.randomUUIDHex(),
                "devicename": deviceName,
                "updateState": "1",
                "phrase": "getservercert",
                "salt": PairingCrypto.hexEncode(salt),
                "clientcert": PairingCrypto.hexEncode(identity.certificatePEM)
            ],
            timeout: requestTimeout
        )

        guard let plainCertificateHex = phase1.value(for: "plaincert") else {
            throw PairingError.missingField("plaincert")
        }
        let serverCertificatePEM = try PairingCrypto.hexDecode(plainCertificateHex)

        try Task.checkCancellation()
        await progress?("Waiting for PIN approval")
        let aesKey = PairingCrypto.aesKey(from: salt, pin: pin)
        let clientChallenge = try PairingCrypto.randomBytes(count: 16)
        let phase2 = try await pairRequest(
            host: host,
            params: [
                "uniqueid": identity.uniqueID,
                "uuid": try PairingCrypto.randomUUIDHex(),
                "clientchallenge": PairingCrypto.hexEncode(try PairingCrypto.aesECBEncrypt(key: aesKey, plaintext: clientChallenge))
            ],
            timeout: 30
        )

        guard let challengeResponseHex = phase2.value(for: "challengeresponse") else {
            throw PairingError.missingField("challengeresponse")
        }
        let challengeResponse = try PairingCrypto.aesECBDecrypt(key: aesKey, ciphertext: try PairingCrypto.hexDecode(challengeResponseHex))
        guard challengeResponse.count >= 48 else {
            throw PairingError.invalidChallengeResponseLength(challengeResponse.count)
        }

        let serverHash = challengeResponse.prefix(32)
        let serverChallenge = challengeResponse.subdata(in: 32..<48)
        let clientSecret = try PairingCrypto.randomBytes(count: 16)
        let clientHash = PairingCrypto.sha256(parts: serverChallenge, identity.certificateSignature, clientSecret)

        try Task.checkCancellation()
        await progress?("Verifying host response")
        let phase3 = try await pairRequest(
            host: host,
            params: [
                "uniqueid": identity.uniqueID,
                "uuid": try PairingCrypto.randomUUIDHex(),
                "serverchallengeresp": PairingCrypto.hexEncode(try PairingCrypto.aesECBEncrypt(key: aesKey, plaintext: clientHash))
            ],
            timeout: 30
        )

        guard let pairingSecretHex = phase3.value(for: "pairingsecret") else {
            throw PairingError.missingField("pairingsecret")
        }
        let pairingSecret = try PairingCrypto.hexDecode(pairingSecretHex)
        guard pairingSecret.count > 16 else {
            throw PairingError.invalidPairingSecretLength(pairingSecret.count)
        }

        let serverSecret = pairingSecret.prefix(16)
        let serverSignature = pairingSecret.dropFirst(16)
        try PairingCrypto.verifyServerSignature(serverCertificatePEM: serverCertificatePEM, serverSecret: Data(serverSecret), signature: Data(serverSignature))

        let serverCertificateSignature = try PairingCrypto.certificateSignature(fromPEM: serverCertificatePEM)
        let expectedServerHash = PairingCrypto.sha256(parts: clientChallenge, serverCertificateSignature, Data(serverSecret))
        let serverHashMatched = Data(serverHash) == expectedServerHash

        let clientSignature = try PairingCrypto.sign(privateKeyPEM: identity.privateKeyPEM, message: clientSecret)

        try Task.checkCancellation()
        await progress?("Finalizing pairing")
        let phase4 = try await pairRequest(
            host: host,
            params: [
                "uniqueid": identity.uniqueID,
                "uuid": try PairingCrypto.randomUUIDHex(),
                "clientpairingsecret": PairingCrypto.hexEncode(clientSecret + clientSignature)
            ],
            timeout: 30
        )

        let pairedValue = phase4.value(for: "paired")
        guard pairedValue == "1" else {
            throw PairingError.pairingRejected("paired=\(pairedValue ?? "nil")")
        }

        let record = PairedHostRecord(
            host: host,
            httpsPort: httpsPort,
            deviceName: deviceName,
            clientUniqueID: identity.uniqueID,
            appVersion: appVersion,
            gfeVersion: gfeVersion,
            serverCodecModeSupport: serverCodecModeSupport,
            serverHashMatched: serverHashMatched,
            pairedAt: Date()
        )

        let verificationSummary: PairingVerificationSummary?
        if skipVerifyCheck {
            verificationSummary = nil
        } else {
            let paths = try temporaryIdentityFiles(for: identity)
            defer { cleanupTemporaryFiles(paths.directoryURL) }

            do {
                try Task.checkCancellation()
                await progress?("Running HTTPS verification")
                let verification = try await httpClient.getHTTPSXML(
                    host: host,
                    httpsPort: httpsPort,
                    path: "/serverinfo",
                    queryItems: [
                        URLQueryItem(name: "uniqueid", value: identity.uniqueID),
                        URLQueryItem(name: "uuid", value: try PairingCrypto.randomUUIDHex())
                    ],
                    identity: HTTPSClientIdentity(
                        certificateURL: paths.certificateURL,
                        privateKeyURL: paths.privateKeyURL,
                        pinnedServerCertificatePEM: serverCertificatePEM
                    ),
                    timeout: 15
                )
                try verification.requireOK(action: "https serverinfo verification")
                verificationSummary = PairingVerificationSummary(
                    pairStatus: verification.value(for: "PairStatus"),
                    currentGame: verification.value(for: "currentgame"),
                    state: verification.value(for: "state")
                )
            } catch {
                verificationSummary = nil
            }
        }

        return PairingSessionResult(
            identity: identity,
            serverCertificatePEM: serverCertificatePEM,
            record: record,
            verificationSummary: verificationSummary
        )
    }

    private func pairRequest(host: HostAuthority, params: [String: String], timeout: TimeInterval) async throws -> PairingXMLResponse {
        let response = try await httpClient.getHTTPXML(
            host: host,
            path: "/pair",
            queryItems: params.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name },
            timeout: timeout
        )
        try response.requireOK(action: "pair")
        return response
    }

    private func temporaryIdentityFiles(for identity: PairingIdentity) throws -> (directoryURL: URL, certificateURL: URL, privateKeyURL: URL) {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let certificateURL = directoryURL.appendingPathComponent("client-cert.pem")
        let privateKeyURL = directoryURL.appendingPathComponent("client-key.pem")
        try identity.certificatePEM.write(to: certificateURL, options: .atomic)
        try identity.privateKeyPEM.write(to: privateKeyURL, options: .atomic)
        return (directoryURL, certificateURL, privateKeyURL)
    }

    private func cleanupTemporaryFiles(_ directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

extension PairingService: @unchecked Sendable {}
