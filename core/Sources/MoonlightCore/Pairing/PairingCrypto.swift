import CommonCrypto
import Foundation
import Security

enum PairingCrypto {
    static let certificateCommonName = "NVIDIA GameStream Client"

    static func generateIdentity() throws -> PairingIdentity {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw PairingError.cryptoFailure(error?.takeRetainedValue().localizedDescription ?? "Failed to create RSA key")
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw PairingError.cryptoFailure("Failed to extract RSA public key")
        }

        guard let publicKeyDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw PairingError.cryptoFailure(error?.takeRetainedValue().localizedDescription ?? "Failed to export public key")
        }
        guard let privateKeyDER = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw PairingError.cryptoFailure(error?.takeRetainedValue().localizedDescription ?? "Failed to export private key")
        }

        let certificate = try X509CertificateBuilder.buildSelfSignedCertificate(
            publicKeyDER: publicKeyDER,
            privateKey: privateKey,
            commonName: certificateCommonName
        )

        let identity = PairingIdentity(
            uniqueID: try randomUniqueID(),
            certificatePEM: certificate.certificatePEM,
            privateKeyPEM: pemEncode(privateKeyDER, header: "RSA PRIVATE KEY"),
            certificateSignature: certificate.signature
        )

        return identity
    }

    static func randomPIN() throws -> String {
        let bytes = try randomBytes(count: 2)
        let value = Int(bytes[0]) << 8 | Int(bytes[1])
        return String(format: "%04d", value % 10_000)
    }

    static func randomUUIDHex() throws -> String {
        hexEncode(try randomBytes(count: 16))
    }

    static func randomUniqueID() throws -> String {
        hexEncode(try randomBytes(count: 8))
    }

    static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, count, rawBuffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw PairingError.cryptoFailure("Failed to generate secure random bytes")
        }
        return data
    }

    static func aesKey(from salt: Data, pin: String) -> Data {
        Data(sha256(salt + Data(pin.utf8)).prefix(16))
    }

    static func aesECBEncrypt(key: Data, plaintext: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCEncrypt), key: key, input: plaintext)
    }

    static func aesECBDecrypt(key: Data, ciphertext: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCDecrypt), key: key, input: ciphertext)
    }

    static func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { rawBuffer in
            _ = CC_SHA256(rawBuffer.baseAddress, CC_LONG(rawBuffer.count), &digest)
        }
        return Data(digest)
    }

    static func sha256(parts: Data...) -> Data {
        sha256(parts.reduce(into: Data(), +=))
    }

    static func sign(privateKey: SecKey, message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            &error
        ) as Data? else {
            throw PairingError.cryptoFailure(error?.takeRetainedValue().localizedDescription ?? "RSA signing failed")
        }
        return signature
    }

    static func sign(privateKeyPEM: Data, message: Data) throws -> Data {
        let privateKeyDER = try derData(fromPEM: privateKeyPEM)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyDER as CFData, attributes as CFDictionary, &error) else {
            throw PairingError.cryptoFailure(error?.takeRetainedValue().localizedDescription ?? "Failed to import RSA private key")
        }

        return try sign(privateKey: privateKey, message: message)
    }

    static func verifyServerSignature(serverCertificatePEM: Data, serverSecret: Data, signature: Data) throws {
        guard let certificate = try secCertificate(fromPEM: serverCertificatePEM),
              let publicKey = SecCertificateCopyKey(certificate)
        else {
            throw PairingError.invalidCertificate("Failed to load server certificate")
        }

        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            serverSecret as CFData,
            signature as CFData,
            &error
        )

        guard isValid else {
            _ = error?.takeRetainedValue()
            throw PairingError.serverSignatureVerificationFailed
        }
    }

    static func certificateSignature(fromPEM pem: Data) throws -> Data {
        let der = try derData(fromPEM: pem)
        let root = try ASN1DERReader.parseRoot(der)
        let children = try ASN1DERReader.childNodes(of: root)
        guard children.count == 3 else {
            throw PairingError.invalidCertificate("Unexpected certificate structure")
        }
        return try ASN1DERReader.bitStringBytes(from: children[2])
    }

    static func derData(fromPEM pem: Data) throws -> Data {
        guard let text = String(data: pem, encoding: .utf8) else {
            throw PairingError.invalidPEM("PEM data is not valid UTF-8")
        }

        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----BEGIN") && !$0.hasPrefix("-----END") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let base64 = lines.joined()

        guard let data = Data(base64Encoded: base64) else {
            throw PairingError.invalidPEM("Base64 decoding failed")
        }

        return data
    }

    static func secCertificate(fromPEM pem: Data) throws -> SecCertificate? {
        let der = try derData(fromPEM: pem)
        return SecCertificateCreateWithData(nil, der as CFData)
    }

    static func pemEncode(_ data: Data, header: String) -> Data {
        let base64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let text = "-----BEGIN \(header)-----\n\(base64)\n-----END \(header)-----\n"
        return Data(text.utf8)
    }

    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hexDecode(_ value: String) throws -> Data {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count.isMultiple(of: 2) else {
            throw PairingError.invalidHex(value)
        }

        var result = Data(capacity: normalized.count / 2)
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let nextIndex = normalized.index(index, offsetBy: 2)
            let byteText = normalized[index..<nextIndex]
            guard let byte = UInt8(byteText, radix: 16) else {
                throw PairingError.invalidHex(value)
            }
            result.append(byte)
            index = nextIndex
        }

        return result
    }

    private static func crypt(operation: CCOperation, key: Data, input: Data) throws -> Data {
        guard input.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw PairingError.cryptoFailure("AES-ECB input must be 16-byte aligned")
        }

        let outputCount = input.count
        var outputBytes = [UInt8](repeating: 0, count: outputCount)
        var outputLength = 0

        let status = outputBytes.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        inputBuffer.baseAddress,
                        input.count,
                        outputBuffer.baseAddress,
                        outputCount,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw PairingError.cryptoFailure("AES-ECB operation failed with status \(status)")
        }

        return Data(outputBytes.prefix(outputLength))
    }
}
