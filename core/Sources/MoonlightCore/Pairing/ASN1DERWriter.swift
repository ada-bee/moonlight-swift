import Foundation

enum ASN1DERWriter {
    static func sequence(_ elements: [Data]) -> Data {
        tagged(0x30, contents: elements.reduce(into: Data(), +=))
    }

    static func set(_ elements: [Data]) -> Data {
        tagged(0x31, contents: elements.reduce(into: Data(), +=))
    }

    static func integer(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        let raw = withUnsafeBytes(of: &bigEndian) { Data($0) }.drop { $0 == 0 }
        let bytes: [UInt8] = raw.isEmpty ? [0] : Array(raw)
        return integer(Data(bytes))
    }

    static func integer(_ value: Data) -> Data {
        var normalized = value
        while normalized.count > 1 && normalized.first == 0 {
            normalized.removeFirst()
        }
        if normalized.first.map({ $0 & 0x80 != 0 }) == true {
            normalized.insert(0, at: 0)
        }
        return tagged(0x02, contents: normalized)
    }

    static func utf8String(_ value: String) -> Data {
        tagged(0x0C, contents: Data(value.utf8))
    }

    static func null() -> Data {
        tagged(0x05, contents: Data())
    }

    static func objectIdentifier(_ components: [UInt64]) -> Data {
        precondition(components.count >= 2)
        var bytes = Data([UInt8(components[0] * 40 + components[1])])
        for component in components.dropFirst(2) {
            bytes.append(encodeBase128(component))
        }
        return tagged(0x06, contents: bytes)
    }

    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return tagged(0x17, contents: Data(formatter.string(from: date).utf8))
    }

    static func bitString(_ value: Data) -> Data {
        tagged(0x03, contents: Data([0]) + value)
    }

    static func contextSpecificConstructed(tagNumber: UInt8, value: Data) -> Data {
        tagged(0xA0 | tagNumber, contents: value)
    }

    static func tagged(_ tag: UInt8, contents: Data) -> Data {
        Data([tag]) + encodeLength(contents.count) + contents
    }

    private static func encodeLength(_ length: Int) -> Data {
        precondition(length >= 0)
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    private static func encodeBase128(_ value: UInt64) -> Data {
        var remaining = value
        var bytes = [UInt8(remaining & 0x7F)]
        remaining >>= 7

        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }

        return Data(bytes)
    }
}

struct ASN1DERNode {
    let tag: UInt8
    let value: Data
}

enum ASN1DERReader {
    static func parseRoot(_ data: Data) throws -> ASN1DERNode {
        var offset = 0
        let node = try readNode(from: data, offset: &offset)
        guard offset == data.count else {
            throw PairingError.invalidCertificate("Unexpected trailing DER data")
        }
        return node
    }

    static func childNodes(of node: ASN1DERNode) throws -> [ASN1DERNode] {
        var nodes: [ASN1DERNode] = []
        var offset = 0
        while offset < node.value.count {
            nodes.append(try readNode(from: node.value, offset: &offset))
        }
        return nodes
    }

    static func bitStringBytes(from node: ASN1DERNode) throws -> Data {
        guard node.tag == 0x03 else {
            throw PairingError.invalidCertificate("Expected BIT STRING")
        }
        guard let unusedBits = node.value.first, unusedBits == 0 else {
            throw PairingError.invalidCertificate("Unsupported BIT STRING padding")
        }
        return node.value.dropFirst()
    }

    private static func readNode(from data: Data, offset: inout Int) throws -> ASN1DERNode {
        guard offset < data.count else {
            throw PairingError.invalidCertificate("Unexpected end of DER data")
        }

        let tag = data[offset]
        offset += 1
        let length = try readLength(from: data, offset: &offset)

        guard offset + length <= data.count else {
            throw PairingError.invalidCertificate("DER length extends past end of buffer")
        }

        let value = data.subdata(in: offset..<(offset + length))
        offset += length
        return ASN1DERNode(tag: tag, value: value)
    }

    private static func readLength(from data: Data, offset: inout Int) throws -> Int {
        guard offset < data.count else {
            throw PairingError.invalidCertificate("Missing DER length")
        }

        let first = data[offset]
        offset += 1

        if first & 0x80 == 0 {
            return Int(first)
        }

        let byteCount = Int(first & 0x7F)
        guard byteCount > 0, byteCount <= 4, offset + byteCount <= data.count else {
            throw PairingError.invalidCertificate("Unsupported DER length encoding")
        }

        var length = 0
        for index in 0..<byteCount {
            length = (length << 8) | Int(data[offset + index])
        }
        offset += byteCount
        return length
    }
}
