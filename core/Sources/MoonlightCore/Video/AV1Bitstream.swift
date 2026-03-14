import CMoonlightCommon
import Foundation

enum MoonlightVideoFormat {
    static let fixedNegotiatedFormat = Int32(VIDEO_FORMAT_AV1_MAIN8)

    static func isAV1(_ videoFormat: Int32) -> Bool {
        (videoFormat & Int32(VIDEO_FORMAT_MASK_AV1)) != 0
    }

    static func isAV1Main8(_ videoFormat: Int32) -> Bool {
        videoFormat == fixedNegotiatedFormat
    }

    static func name(for videoFormat: Int32) -> String {
        switch videoFormat {
        case Int32(VIDEO_FORMAT_AV1_MAIN8):
            return "AV1 Main8"
        case Int32(VIDEO_FORMAT_AV1_MAIN10):
            return "AV1 Main10"
        case Int32(VIDEO_FORMAT_AV1_HIGH8_444):
            return "AV1 High8 4:4:4"
        case Int32(VIDEO_FORMAT_AV1_HIGH10_444):
            return "AV1 High10 4:4:4"
        default:
            return "unknown(\(videoFormat))"
        }
    }
}

struct AV1DecoderConfiguration: Equatable {
    let profile: UInt8
    let codecConfigurationRecord: Data
    let bitDepth: Int
    let chromaSubsamplingX: UInt8
    let chromaSubsamplingY: UInt8
    let codedWidth: Int
    let codedHeight: Int
    let sequenceHeaderOBU: Data
}

enum AV1Bitstream {
    static func extractSequenceHeaderOBU(from temporalUnit: Data) -> Data? {
        temporalUnit.withUnsafeBytes { buffer in
            extractSequenceHeaderOBU(from: buffer)
        }
    }

    static func extractSequenceHeaderOBU(from temporalUnit: UnsafeRawBufferPointer) -> Data? {
        var offset = 0

        while offset < temporalUnit.count {
            guard let obu = try? parseOBU(in: temporalUnit, offset: offset) else {
                return nil
            }

            if obu.type == .sequenceHeader {
                return canonicalSequenceHeaderOBU(from: temporalUnit, obu: obu)
            }

            offset = obu.nextOffset
        }

        return nil
    }

    static func makeDecoderConfiguration(from sequenceHeaderOBU: Data) throws -> AV1DecoderConfiguration {
        try sequenceHeaderOBU.withUnsafeBytes { buffer in
            let obu = try parseOBU(in: buffer, offset: 0)
            guard obu.type == .sequenceHeader, obu.nextOffset == buffer.count else {
                throw AV1BitstreamError.invalidSequenceHeader
            }

            let descriptor = try parseSequenceHeader(in: buffer, payloadRange: obu.payloadRange)
            let sequenceHeaderData = dataCopy(from: buffer)
            let configurationRecord = makeCodecConfigurationRecord(
                descriptor: descriptor,
                sequenceHeaderOBU: sequenceHeaderData
            )

            return AV1DecoderConfiguration(
                profile: descriptor.profile,
                codecConfigurationRecord: configurationRecord,
                bitDepth: descriptor.bitDepth,
                chromaSubsamplingX: descriptor.chromaSubsamplingX,
                chromaSubsamplingY: descriptor.chromaSubsamplingY,
                codedWidth: descriptor.codedWidth,
                codedHeight: descriptor.codedHeight,
                sequenceHeaderOBU: sequenceHeaderData
            )
        }
    }
}

private enum AV1BitstreamError: Error {
    case truncatedOBU
    case invalidOBUHeader
    case invalidSequenceHeader
}

private enum AV1OBUType: UInt8 {
    case sequenceHeader = 1
}

private struct AV1OBU {
    let type: AV1OBUType?
    let headerByte: UInt8
    let extensionByte: UInt8?
    let payloadRange: Range<Int>
    let nextOffset: Int
}

private struct AV1SequenceHeaderDescriptor {
    let profile: UInt8
    let level: UInt8
    let tier: UInt8
    let bitDepth: Int
    let monochrome: UInt8
    let chromaSubsamplingX: UInt8
    let chromaSubsamplingY: UInt8
    let chromaSamplePosition: UInt8
    let codedWidth: Int
    let codedHeight: Int
}

private struct AV1DecoderModelInfo {
    let bufferDelayLength: Int
}

private func parseOBU(in bytes: UnsafeRawBufferPointer, offset: Int) throws -> AV1OBU {
    guard offset < bytes.count else {
        throw AV1BitstreamError.truncatedOBU
    }

    let headerByte = bytes[offset]
    guard (headerByte & 0x80) == 0 else {
        throw AV1BitstreamError.invalidOBUHeader
    }

    let type = AV1OBUType(rawValue: (headerByte >> 3) & 0x0F)
    let hasExtension = (headerByte & 0x04) != 0
    let hasSizeField = (headerByte & 0x02) != 0

    var cursor = offset + 1
    let extensionByte: UInt8?
    if hasExtension {
        guard cursor < bytes.count else {
            throw AV1BitstreamError.truncatedOBU
        }
        extensionByte = bytes[cursor]
        cursor += 1
    } else {
        extensionByte = nil
    }

    let payloadLength: Int
    if hasSizeField {
        let decoded = try decodeLEB128(in: bytes, offset: cursor)
        payloadLength = decoded.value
        cursor = decoded.nextOffset
    } else {
        payloadLength = bytes.count - cursor
    }

    guard payloadLength >= 0, cursor + payloadLength <= bytes.count else {
        throw AV1BitstreamError.truncatedOBU
    }

    return AV1OBU(
        type: type,
        headerByte: headerByte,
        extensionByte: extensionByte,
        payloadRange: cursor..<(cursor + payloadLength),
        nextOffset: cursor + payloadLength
    )
}

private func decodeLEB128(in bytes: UnsafeRawBufferPointer, offset: Int) throws -> (value: Int, nextOffset: Int) {
    var value = 0
    var shift = 0
    var cursor = offset

    while true {
        guard cursor < bytes.count, shift < 35 else {
            throw AV1BitstreamError.truncatedOBU
        }

        let byte = Int(bytes[cursor])
        value |= (byte & 0x7F) << shift
        cursor += 1

        if (byte & 0x80) == 0 {
            return (value, cursor)
        }

        shift += 7
    }
}

private func encodeLEB128(_ value: Int) -> Data {
    var remaining = value
    var output = Data()

    while true {
        var byte = UInt8(remaining & 0x7F)
        remaining >>= 7
        if remaining != 0 {
            byte |= 0x80
        }
        output.append(byte)

        if remaining == 0 {
            return output
        }
    }
}

private func canonicalSequenceHeaderOBU(from bytes: UnsafeRawBufferPointer, obu: AV1OBU) -> Data {
    var output = Data([obu.headerByte | 0x02])
    if let extensionByte = obu.extensionByte {
        output.append(extensionByte)
    }
    output.append(encodeLEB128(obu.payloadRange.count))
    if obu.payloadRange.count > 0, let baseAddress = bytes.baseAddress {
        output.append(
            baseAddress.advanced(by: obu.payloadRange.lowerBound).assumingMemoryBound(to: UInt8.self),
            count: obu.payloadRange.count
        )
    }
    return output
}

private func parseSequenceHeader(in bytes: UnsafeRawBufferPointer, payloadRange: Range<Int>) throws -> AV1SequenceHeaderDescriptor {
    var reader = try AV1BitReader(bytes: bytes, range: payloadRange)
    let profile = UInt8(try reader.readBits(3))
    _ = try reader.readFlag()
    let reducedStillPictureHeader = try reader.readFlag()

    var level: UInt8 = 0
    var tier: UInt8 = 0
    var decoderModelInfo: AV1DecoderModelInfo?
    var initialDisplayDelayPresent = false

    if reducedStillPictureHeader {
        level = UInt8(try reader.readBits(5))
    } else {
        let timingInfoPresent = try reader.readFlag()
        if timingInfoPresent {
            try reader.skipBits(32)
            try reader.skipBits(32)

            let equalPictureInterval = try reader.readFlag()
            if equalPictureInterval {
                _ = try reader.readUVLC()
            }

            let decoderModelInfoPresent = try reader.readFlag()
            if decoderModelInfoPresent {
                let bufferDelayLengthMinus1 = Int(try reader.readBits(5))
                try reader.skipBits(32)
                try reader.skipBits(5)
                try reader.skipBits(5)
                decoderModelInfo = AV1DecoderModelInfo(bufferDelayLength: bufferDelayLengthMinus1 + 1)
            }
        }

        initialDisplayDelayPresent = try reader.readFlag()

        let operatingPointsCountMinus1 = Int(try reader.readBits(5))
        for index in 0...operatingPointsCountMinus1 {
            try reader.skipBits(12)
            let operatingPointLevel = UInt8(try reader.readBits(5))
            let operatingPointTier: UInt8 = operatingPointLevel > 7 ? UInt8(try reader.readBits(1)) : 0

            if index == 0 {
                level = operatingPointLevel
                tier = operatingPointTier
            }

            if let decoderModelInfo {
                let presentForThisOp = try reader.readFlag()
                if presentForThisOp {
                    try reader.skipBits(decoderModelInfo.bufferDelayLength)
                    try reader.skipBits(decoderModelInfo.bufferDelayLength)
                    try reader.skipBits(1)
                }
            }

            if initialDisplayDelayPresent {
                let presentForThisOp = try reader.readFlag()
                if presentForThisOp {
                    try reader.skipBits(4)
                }
            }
        }
    }

    let frameWidthBitsMinus1 = Int(try reader.readBits(4))
    let frameHeightBitsMinus1 = Int(try reader.readBits(4))
    let codedWidth = Int(try reader.readBits(frameWidthBitsMinus1 + 1)) + 1
    let codedHeight = Int(try reader.readBits(frameHeightBitsMinus1 + 1)) + 1

    let frameIDNumbersPresent = reducedStillPictureHeader ? false : try reader.readFlag()
    if frameIDNumbersPresent {
        try reader.skipBits(4)
        try reader.skipBits(3)
    }

    try reader.skipBits(1)
    try reader.skipBits(1)
    try reader.skipBits(1)

    let enableOrderHint: Bool
    if reducedStillPictureHeader {
        enableOrderHint = false
    } else {
        try reader.skipBits(1)
        try reader.skipBits(1)
        try reader.skipBits(1)
        try reader.skipBits(1)
        enableOrderHint = try reader.readFlag()
        if enableOrderHint {
            try reader.skipBits(1)
            try reader.skipBits(1)
        }

        let chooseScreenContentTools = try reader.readFlag()
        let forceScreenContentTools: UInt8 = chooseScreenContentTools ? 2 : UInt8(try reader.readBits(1))
        if forceScreenContentTools != 0 {
            let chooseIntegerMV = try reader.readFlag()
            if !chooseIntegerMV {
                try reader.skipBits(1)
            }
        }

        if enableOrderHint {
            try reader.skipBits(3)
        }
    }

    try reader.skipBits(1)
    try reader.skipBits(1)
    try reader.skipBits(1)

    let colorConfig = try parseColorConfig(reader: &reader, profile: profile)
    _ = try reader.readFlag()

    return AV1SequenceHeaderDescriptor(
        profile: profile,
        level: level,
        tier: tier,
        bitDepth: colorConfig.bitDepth,
        monochrome: colorConfig.monochrome,
        chromaSubsamplingX: colorConfig.chromaSubsamplingX,
        chromaSubsamplingY: colorConfig.chromaSubsamplingY,
        chromaSamplePosition: colorConfig.chromaSamplePosition,
        codedWidth: codedWidth,
        codedHeight: codedHeight
    )
}

private func parseColorConfig(reader: inout AV1BitReader, profile: UInt8) throws -> (
    bitDepth: Int,
    monochrome: UInt8,
    chromaSubsamplingX: UInt8,
    chromaSubsamplingY: UInt8,
    chromaSamplePosition: UInt8
) {
    let highBitDepth = try reader.readFlag()
    let bitDepth: Int
    let twelveBit: UInt8
    if profile == 2, highBitDepth {
        twelveBit = try reader.readFlag() ? 1 : 0
        bitDepth = twelveBit == 1 ? 12 : 10
    } else {
        twelveBit = 0
        bitDepth = highBitDepth ? 10 : 8
    }

    let monochrome: UInt8
    if profile == 1 {
        monochrome = 0
    } else {
        monochrome = try reader.readFlag() ? 1 : 0
    }

    let colorDescriptionPresent = try reader.readFlag()
    let colorPrimaries: UInt8
    let transferCharacteristics: UInt8
    let matrixCoefficients: UInt8
    if colorDescriptionPresent {
        colorPrimaries = UInt8(try reader.readBits(8))
        transferCharacteristics = UInt8(try reader.readBits(8))
        matrixCoefficients = UInt8(try reader.readBits(8))
    } else {
        colorPrimaries = 2
        transferCharacteristics = 2
        matrixCoefficients = 2
    }

    let chromaSubsamplingX: UInt8
    let chromaSubsamplingY: UInt8
    let chromaSamplePosition: UInt8

    if monochrome == 1 {
        try reader.skipBits(1)
        _ = try reader.readFlag()
        return (bitDepth, monochrome, 1, 1, 0)
    }

    if colorPrimaries == 1, transferCharacteristics == 13, matrixCoefficients == 0 {
        chromaSubsamplingX = 0
        chromaSubsamplingY = 0
        chromaSamplePosition = 0
    } else {
        try reader.skipBits(1)

        if profile == 0 {
            chromaSubsamplingX = 1
            chromaSubsamplingY = 1
        } else if profile == 1 {
            chromaSubsamplingX = 0
            chromaSubsamplingY = 0
        } else if bitDepth == 12 {
            chromaSubsamplingX = try reader.readFlag() ? 1 : 0
            chromaSubsamplingY = chromaSubsamplingX == 1 ? (try reader.readFlag() ? 1 : 0) : 0
        } else {
            chromaSubsamplingX = 1
            chromaSubsamplingY = 0
        }

        if chromaSubsamplingX == 1, chromaSubsamplingY == 1 {
            chromaSamplePosition = UInt8(try reader.readBits(2))
        } else {
            chromaSamplePosition = 0
        }
    }

    _ = try reader.readFlag()
    _ = twelveBit

    return (bitDepth, monochrome, chromaSubsamplingX, chromaSubsamplingY, chromaSamplePosition)
}

private func makeCodecConfigurationRecord(
    descriptor: AV1SequenceHeaderDescriptor,
    sequenceHeaderOBU: Data
) -> Data {
    let highBitDepth = descriptor.bitDepth > 8 ? UInt8(1) : 0
    let twelveBit = descriptor.bitDepth == 12 ? UInt8(1) : 0
    let secondByte = (descriptor.profile << 5) | (descriptor.level & 0x1F)
    let thirdByte =
        ((descriptor.tier & 0x01) << 7) |
        (highBitDepth << 6) |
        (twelveBit << 5) |
        ((descriptor.monochrome & 0x01) << 4) |
        ((descriptor.chromaSubsamplingX & 0x01) << 3) |
        ((descriptor.chromaSubsamplingY & 0x01) << 2) |
        (descriptor.chromaSamplePosition & 0x03)

    var record = Data([0x81, secondByte, thirdByte, 0x00])
    record.append(sequenceHeaderOBU)
    return record
}

private func dataCopy(from bytes: UnsafeRawBufferPointer) -> Data {
    guard bytes.count > 0, let baseAddress = bytes.baseAddress else {
        return Data()
    }

    return Data(bytes: baseAddress, count: bytes.count)
}

private struct AV1BitReader {
    let bytes: UnsafeRawBufferPointer
    let startByteOffset: Int
    let byteCount: Int
    var bitOffset = 0

    init(bytes: UnsafeRawBufferPointer, range: Range<Int>) throws {
        guard range.lowerBound >= 0, range.upperBound <= bytes.count else {
            throw AV1BitstreamError.invalidSequenceHeader
        }

        self.bytes = bytes
        self.startByteOffset = range.lowerBound
        self.byteCount = range.count
    }

    mutating func readFlag() throws -> Bool {
        try readBits(1) == 1
    }

    mutating func readBits(_ count: Int) throws -> UInt64 {
        guard count >= 0 else {
            throw AV1BitstreamError.invalidSequenceHeader
        }

        var value: UInt64 = 0
        for _ in 0..<count {
            guard bitOffset < byteCount * 8 else {
                throw AV1BitstreamError.invalidSequenceHeader
            }

            let byteIndex = startByteOffset + (bitOffset / 8)
            let bitIndex = 7 - (bitOffset % 8)
            let bit = UInt64((bytes[byteIndex] >> bitIndex) & 0x01)
            value = (value << 1) | bit
            bitOffset += 1
        }
        return value
    }

    mutating func skipBits(_ count: Int) throws {
        _ = try readBits(count)
    }

    mutating func readUVLC() throws -> UInt64 {
        var leadingZeroBits = 0
        while try !readFlag() {
            leadingZeroBits += 1
            if leadingZeroBits > 31 {
                throw AV1BitstreamError.invalidSequenceHeader
            }
        }

        if leadingZeroBits == 0 {
            return 0
        }

        let suffix = try readBits(leadingZeroBits)
        return ((1 as UInt64) << leadingZeroBits) - 1 + suffix
    }
}
