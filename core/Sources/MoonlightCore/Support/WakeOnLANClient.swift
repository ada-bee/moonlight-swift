import Darwin
import Foundation

public enum WakeOnLANError: Error, LocalizedError {
    case invalidMACAddress
    case invalidBroadcastAddress
    case socketCreationFailed
    case socketConfigurationFailed
    case sendFailed

    public var errorDescription: String? {
        switch self {
        case .invalidMACAddress:
            return "Use a MAC address like 00:11:22:33:44:55."
        case .invalidBroadcastAddress:
            return "Use an IPv4 broadcast address like 255.255.255.255."
        case .socketCreationFailed:
            return "Failed to create the Wake-on-LAN socket."
        case .socketConfigurationFailed:
            return "Failed to configure the Wake-on-LAN socket."
        case .sendFailed:
            return "Failed to send the Wake-on-LAN packet."
        }
    }
}

public final class WakeOnLANClient {
    public init() {}

    public func normalizedConfiguration(macAddress: String, broadcastAddress: String?) throws -> WakeOnLANConfiguration {
        let macBytes = try Self.parseMACAddress(macAddress)
        let normalizedBroadcastAddress = try Self.normalizeBroadcastAddress(broadcastAddress)

        return WakeOnLANConfiguration(
            macAddress: Self.formattedMACAddress(from: macBytes),
            broadcastAddress: normalizedBroadcastAddress
        )
    }

    public func sendMagicPacket(configuration: WakeOnLANConfiguration, port: UInt16 = 9) throws {
        let macBytes = try Self.parseMACAddress(configuration.macAddress)
        let destinationAddress = try Self.resolveDestinationAddress(configuration.broadcastAddress)
        let packet = Self.makeMagicPacket(macBytes: macBytes)

        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw WakeOnLANError.socketCreationFailed
        }
        defer { close(socketDescriptor) }

        var broadcastEnabled: Int32 = 1
        let broadcastStatus = setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &broadcastEnabled,
            socklen_t(MemoryLayout.size(ofValue: broadcastEnabled))
        )
        guard broadcastStatus == 0 else {
            throw WakeOnLANError.socketConfigurationFailed
        }

        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = in_port_t(port).bigEndian
        socketAddress.sin_addr = destinationAddress

        let bytesSent = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                packet.withUnsafeBytes { packetBytes in
                    sendto(
                        socketDescriptor,
                        packetBytes.baseAddress,
                        packetBytes.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard bytesSent == packet.count else {
            throw WakeOnLANError.sendFailed
        }
    }

    private static func parseMACAddress(_ rawValue: String) throws -> [UInt8] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexDigits = trimmed.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")

        guard hexDigits.count == 12 else {
            throw WakeOnLANError.invalidMACAddress
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)

        var index = hexDigits.startIndex
        while index < hexDigits.endIndex {
            let nextIndex = hexDigits.index(index, offsetBy: 2)
            let byteString = String(hexDigits[index..<nextIndex])
            guard let value = UInt8(byteString, radix: 16) else {
                throw WakeOnLANError.invalidMACAddress
            }
            bytes.append(value)
            index = nextIndex
        }

        return bytes
    }

    private static func formattedMACAddress(from bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private static func normalizeBroadcastAddress(_ rawValue: String?) throws -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        guard isValidIPv4Address(trimmed) else {
            throw WakeOnLANError.invalidBroadcastAddress
        }

        return trimmed
    }

    private static func resolveDestinationAddress(_ rawValue: String?) throws -> in_addr {
        let addressString = try normalizeBroadcastAddress(rawValue) ?? "255.255.255.255"
        var address = in_addr()

        let parseStatus = addressString.withCString { pointer in
            inet_pton(AF_INET, pointer, &address)
        }
        guard parseStatus == 1 else {
            throw WakeOnLANError.invalidBroadcastAddress
        }

        return address
    }

    private static func isValidIPv4Address(_ value: String) -> Bool {
        var address = in_addr()
        return value.withCString { pointer in
            inet_pton(AF_INET, pointer, &address) == 1
        }
    }

    private static func makeMagicPacket(macBytes: [UInt8]) -> Data {
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }
}

extension WakeOnLANClient: @unchecked Sendable {}
