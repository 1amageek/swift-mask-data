import Foundation
import LayoutIR
import Compression

/// Low-level OASIS binary reader with transparent CBLOCK decompression.
public struct OASISReader: Sendable {
    private var data: Data
    private(set) var offset: Int

    public init(data: Data) {
        self.data = data
        self.offset = 0
    }

    public var hasMore: Bool { offset < data.count }
    public var currentOffset: Int { offset }

    // MARK: - Byte

    public mutating func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }
        let b = data[offset]
        offset += 1
        return b
    }

    public func peekByte() throws -> UInt8 {
        guard offset < data.count else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }
        return data[offset]
    }

    public mutating func readBytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }
        let result = data[offset..<(offset + count)]
        offset += count
        return result
    }

    // MARK: - CBLOCK Decompression

    /// Called by the library reader when a CBLOCK record type is encountered.
    /// Decompresses the data and replaces the remaining stream.
    public mutating func handleCBlock() throws {
        let compressionType = try readUnsignedInteger()
        guard compressionType == 0 else {
            throw OASISError.decompressFailure(offset: offset)
        }
        let uncompressedSize = try readUnsignedInteger()
        let compressedSize = try readUnsignedInteger()

        guard offset + Int(compressedSize) <= data.count else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }

        let compressedData = data[offset..<(offset + Int(compressedSize))]
        let remainingAfterBlock = data[(offset + Int(compressedSize))...]

        let decompressed = try decompressDeflate(Data(compressedData), expectedSize: Int(uncompressedSize))

        // Replace data stream: decompressed content followed by remaining data
        var newData = decompressed
        newData.append(contentsOf: remainingAfterBlock)
        self.data = newData
        self.offset = 0
    }

    private func decompressDeflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        let sourceSize = compressed.count
        var decompressed = Data(count: expectedSize)

        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            compressed.withUnsafeBytes { srcBuffer in
                guard let destPtr = destBuffer.baseAddress,
                      let srcPtr = srcBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destPtr.assumingMemoryBound(to: UInt8.self),
                    expectedSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else {
            throw OASISError.decompressFailure(offset: offset)
        }

        if result < expectedSize {
            decompressed = decompressed.prefix(result)
        }

        return decompressed
    }

    // MARK: - Unsigned Integer (LEB128)

    public mutating func readUnsignedInteger() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let b = try readByte()
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 {
                return result
            }
            shift += 7
        }
    }

    // MARK: - Signed Integer (Zigzag)

    public mutating func readSignedInteger() throws -> Int64 {
        let unsigned = try readUnsignedInteger()
        let sign = unsigned & 1
        let magnitude = unsigned >> 1
        if sign == 0 {
            return Int64(magnitude)
        } else {
            return -(Int64(magnitude)) - 1
        }
    }

    // MARK: - Real Number

    public mutating func readReal() throws -> Double {
        let startOffset = offset
        let typeCode = try readUnsignedInteger()
        switch typeCode {
        case 0:
            let n = try readUnsignedInteger()
            return Double(n)
        case 1:
            let n = try readUnsignedInteger()
            return -Double(n)
        case 2:
            let n = try readUnsignedInteger()
            return 1.0 / Double(n)
        case 3:
            let n = try readUnsignedInteger()
            return -1.0 / Double(n)
        case 4:
            let num = try readUnsignedInteger()
            let den = try readUnsignedInteger()
            return Double(num) / Double(den)
        case 5:
            let num = try readUnsignedInteger()
            let den = try readUnsignedInteger()
            return -Double(num) / Double(den)
        case 6:
            let bytes = try readBytes(4)
            let bits = UInt32(bytes[bytes.startIndex])
                | (UInt32(bytes[bytes.startIndex + 1]) << 8)
                | (UInt32(bytes[bytes.startIndex + 2]) << 16)
                | (UInt32(bytes[bytes.startIndex + 3]) << 24)
            return Double(Float(bitPattern: bits))
        case 7:
            let bytes = try readBytes(8)
            var bits: UInt64 = 0
            for i in 0..<8 {
                bits |= UInt64(bytes[bytes.startIndex + i]) << (i * 8)
            }
            return Double(bitPattern: bits)
        default:
            throw OASISError.unknownRealType(offset: startOffset, typeCode: typeCode)
        }
    }

    // MARK: - Strings

    public mutating func readAString() throws -> String {
        let length = try readUnsignedInteger()
        if length == 0 { return "" }
        let bytes = try readBytes(Int(length))
        guard let str = String(data: bytes, encoding: .ascii) else {
            throw OASISError.invalidString(offset: offset - Int(length))
        }
        return str
    }

    public mutating func readBString() throws -> Data {
        let length = try readUnsignedInteger()
        if length == 0 { return Data() }
        return try readBytes(Int(length))
    }

    // MARK: - Magic

    public mutating func validateMagic() throws {
        let expected = Array("%SEMI-OASIS\r\n".utf8)
        guard offset + expected.count <= data.count else {
            throw OASISError.invalidMagic(offset: offset)
        }
        for i in 0..<expected.count {
            if data[offset + i] != expected[i] {
                throw OASISError.invalidMagic(offset: offset)
            }
        }
        offset += expected.count
    }

    // MARK: - Point List

    public mutating func readPointList() throws -> [IRPoint] {
        let typeCode = try readUnsignedInteger()
        let count = try readUnsignedInteger()

        switch typeCode {
        case 4:
            return try readGeneralPointList(count: Int(count))
        case 0:
            return try readManhattanHFirst(count: Int(count))
        case 1:
            return try readManhattanVFirst(count: Int(count))
        case 2:
            return try readManhattanAny(count: Int(count))
        case 3:
            return try readOctangular(count: Int(count))
        default:
            throw OASISError.invalidPointListType(offset: offset, typeCode: typeCode)
        }
    }

    private mutating func readGeneralPointList(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for _ in 0..<count {
            let dx = try readSignedInteger()
            let dy = try readSignedInteger()
            points.append(IRPoint(x: Int32(dx), y: Int32(dy)))
        }
        return points
    }

    private mutating func readManhattanHFirst(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let delta = try readSignedInteger()
            if i % 2 == 0 {
                points.append(IRPoint(x: Int32(delta), y: 0))
            } else {
                points.append(IRPoint(x: 0, y: Int32(delta)))
            }
        }
        return points
    }

    private mutating func readManhattanVFirst(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let delta = try readSignedInteger()
            if i % 2 == 0 {
                points.append(IRPoint(x: 0, y: Int32(delta)))
            } else {
                points.append(IRPoint(x: Int32(delta), y: 0))
            }
        }
        return points
    }

    private mutating func readManhattanAny(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for _ in 0..<count {
            let encoded = try readUnsignedInteger()
            let dir = encoded & 0x03
            let mag = Int64(encoded >> 2)
            switch dir {
            case 0: points.append(IRPoint(x: Int32(mag), y: 0))
            case 1: points.append(IRPoint(x: 0, y: Int32(mag)))
            case 2: points.append(IRPoint(x: Int32(-mag), y: 0))
            case 3: points.append(IRPoint(x: 0, y: Int32(-mag)))
            default: break
            }
        }
        return points
    }

    private mutating func readOctangular(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for _ in 0..<count {
            let encoded = try readUnsignedInteger()
            let dir = encoded & 0x07
            let mag = Int32(encoded >> 3)
            switch dir {
            case 0: points.append(IRPoint(x: mag, y: 0))
            case 1: points.append(IRPoint(x: 0, y: mag))
            case 2: points.append(IRPoint(x: -mag, y: 0))
            case 3: points.append(IRPoint(x: 0, y: -mag))
            case 4: points.append(IRPoint(x: mag, y: mag))
            case 5: points.append(IRPoint(x: -mag, y: mag))
            case 6: points.append(IRPoint(x: mag, y: -mag))
            case 7: points.append(IRPoint(x: -mag, y: -mag))
            default: break
            }
        }
        return points
    }

    // MARK: - Repetition

    public mutating func readRepetition() throws -> OASISRepetition {
        let startOffset = offset
        let typeCode = try readUnsignedInteger()
        switch typeCode {
        case 0:
            throw OASISError.invalidRepetitionType(offset: startOffset, typeCode: 0)
        case 1:
            let xDim = try readUnsignedInteger() + 2
            let yDim = try readUnsignedInteger() + 2
            let xSpace = try readUnsignedInteger()
            let ySpace = try readUnsignedInteger()
            return .grid(columns: xDim, rows: yDim, colSpacing: xSpace, rowSpacing: ySpace)
        case 2:
            let xDim = try readUnsignedInteger() + 2
            let xSpace = try readUnsignedInteger()
            return .uniformRow(count: xDim, spacing: xSpace)
        case 3:
            let yDim = try readUnsignedInteger() + 2
            let ySpace = try readUnsignedInteger()
            return .uniformColumn(count: yDim, spacing: ySpace)
        case 4:
            let xDim = try readUnsignedInteger() + 2
            var spacings: [UInt64] = []
            for _ in 0..<(xDim - 1) {
                spacings.append(try readUnsignedInteger())
            }
            return .variableRow(spacings: spacings)
        case 5:
            let xDim = try readUnsignedInteger() + 2
            let yDim = try readUnsignedInteger() + 2
            let colDisp = try readGDelta()
            let rowDisp = try readGDelta()
            return .arbitraryGrid(columns: xDim, rows: yDim, colDisplacement: colDisp, rowDisplacement: rowDisp)
        case 6:
            let yDim = try readUnsignedInteger() + 2
            var spacings: [UInt64] = []
            for _ in 0..<(yDim - 1) {
                spacings.append(try readUnsignedInteger())
            }
            return .variableColumn(spacings: spacings)
        case 7:
            let count = try readUnsignedInteger() + 2
            var displacements: [OASISDisplacement] = []
            for _ in 0..<(count - 1) {
                displacements.append(try readGDelta())
            }
            return .variableDisplacementRow(displacements: displacements)
        case 8:
            let count = try readUnsignedInteger() + 2
            var displacements: [OASISDisplacement] = []
            for _ in 0..<(count - 1) {
                displacements.append(try readGDelta())
            }
            return .variableDisplacementColumn(displacements: displacements)
        case 9:
            let count = try readUnsignedInteger() + 2
            let disp = try readGDelta()
            return .variableDisplacementRow(displacements: Array(repeating: disp, count: Int(count) - 1))
        case 10:
            let count = try readUnsignedInteger() + 2
            let disp = try readGDelta()
            return .variableDisplacementColumn(displacements: Array(repeating: disp, count: Int(count) - 1))
        case 11:
            let xDim = try readUnsignedInteger() + 2
            let yDim = try readUnsignedInteger() + 2
            let colDisp = try readGDelta()
            let rowDisp = try readGDelta()
            return .arbitraryGrid(columns: xDim, rows: yDim, colDisplacement: colDisp, rowDisplacement: rowDisp)
        default:
            throw OASISError.invalidRepetitionType(offset: startOffset, typeCode: typeCode)
        }
    }

    private mutating func readGDelta() throws -> OASISDisplacement {
        let encoded = try readUnsignedInteger()
        if encoded & 1 == 0 {
            let dir = (encoded >> 1) & 0x03
            let mag = Int64(encoded >> 3)
            switch dir {
            case 0: return OASISDisplacement(dx: mag, dy: 0)
            case 1: return OASISDisplacement(dx: 0, dy: mag)
            case 2: return OASISDisplacement(dx: -mag, dy: 0)
            case 3: return OASISDisplacement(dx: 0, dy: -mag)
            default: return OASISDisplacement(dx: 0, dy: 0)
            }
        } else {
            let dx = try readSignedInteger()
            let dy = try readSignedInteger()
            return OASISDisplacement(dx: dx, dy: dy)
        }
    }

    // MARK: - Property Value

    public mutating func readPropertyValue() throws -> OASISPropertyValue {
        let typeCode = try readUnsignedInteger()
        switch typeCode {
        case 0: return .real(try readReal())
        case 1: return .unsignedInteger(try readUnsignedInteger())
        case 2: return .signedInteger(try readSignedInteger())
        case 3: return .aString(try readAString())
        case 4:
            let bdata = try readBString()
            return .bString(Array(bdata))
        case 5: return .aString(try readAString())
        case 6: return .aString(try readAString())
        case 7:
            let bdata = try readBString()
            return .bString(Array(bdata))
        case 8: return .real(try readReal())
        case 9: return .unsignedInteger(try readUnsignedInteger())
        case 10: return .signedInteger(try readSignedInteger())
        case 11: return .aString(try readAString())
        case 12:
            let bdata = try readBString()
            return .bString(Array(bdata))
        case 13: return .aString(try readAString())
        case 14: return .reference(try readUnsignedInteger())
        case 15: return .reference(try readUnsignedInteger())
        default: return .unsignedInteger(typeCode)
        }
    }
}
