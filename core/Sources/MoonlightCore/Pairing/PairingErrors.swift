import Foundation

public enum PairingError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case invalidResponseStatus(action: String, code: Int?, message: String?)
    case missingField(String)
    case malformedXML(String)
    case invalidHex(String)
    case invalidPEM(String)
    case invalidCertificate(String)
    case cryptoFailure(String)
    case invalidChallengeResponseLength(Int)
    case invalidPairingSecretLength(Int)
    case serverSignatureVerificationFailed
    case pairingRejected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct a GameStream URL."
        case let .requestFailed(message):
            return "Network request failed: \(message)"
        case let .invalidResponseStatus(action, code, message):
            return "\(action) failed with status \(code.map(String.init) ?? "unknown"): \(message ?? "Unknown error")"
        case let .missingField(field):
            return "Missing required GameStream field: \(field)"
        case let .malformedXML(message):
            return "Malformed XML response: \(message)"
        case let .invalidHex(value):
            return "Invalid hexadecimal payload: \(value)"
        case let .invalidPEM(message):
            return "Invalid PEM payload: \(message)"
        case let .invalidCertificate(message):
            return "Invalid certificate payload: \(message)"
        case let .cryptoFailure(message):
            return "Cryptography failed: \(message)"
        case let .invalidChallengeResponseLength(length):
            return "Unexpected challenge response length: \(length)"
        case let .invalidPairingSecretLength(length):
            return "Unexpected pairing secret length: \(length)"
        case .serverSignatureVerificationFailed:
            return "The host pairing signature could not be verified."
        case let .pairingRejected(message):
            return "The host rejected pairing: \(message)"
        }
    }
}
