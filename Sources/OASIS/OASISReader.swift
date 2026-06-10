import Foundation
import LayoutIR
import Compression

/// Low-level OASIS binary reader with transparent CBLOCK decompression.
public struct OASISReader: Sendable {
    private var data: Data
    private(set) var offset: Int
    private static let maxDecodedCollectionElements = 1_000_000

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
        guard count >= 0, count <= data.count - offset else {
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
        let compressedByteCount = try checkedByteCount(compressedSize, context: "CBLOCK compressed size")
        let uncompressedByteCount = try checkedInt(uncompressedSize, context: "CBLOCK uncompressed size")

        guard compressedByteCount <= data.count - offset else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }

        let compressedData = data[offset..<(offset + compressedByteCount)]
        let remainingAfterBlock = data[(offset + compressedByteCount)...]

        let decompressed = try decompressDeflate(Data(compressedData), expectedSize: uncompressedByteCount)

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
            let payload = UInt64(b & 0x7F)
            guard shift < 64, !(shift == 63 && payload > 1) else {
                throw OASISError.numericOverflow(context: "unsigned integer", value: "LEB128 at byte offset \(offset - 1)")
            }
            result |= payload << shift
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
        guard magnitude <= UInt64(Int64.max) else {
            throw OASISError.numericOverflow(context: "signed integer", value: String(magnitude))
        }
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
        let byteCount = try checkedByteCount(length, context: "a-string length")
        let bytes = try readBytes(byteCount)
        guard let str = String(data: bytes, encoding: .ascii) else {
            throw OASISError.invalidString(offset: offset - byteCount)
        }
        return str
    }

    public mutating func readBString() throws -> Data {
        let length = try readUnsignedInteger()
        if length == 0 { return Data() }
        let byteCount = try checkedByteCount(length, context: "b-string length")
        return try readBytes(byteCount)
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
        let pointCount = try checkedCollectionCount(count, context: "point list count")

        switch typeCode {
        case 4:
            return try readGeneralPointList(count: pointCount)
        case 0:
            return try readManhattanHFirst(count: pointCount)
        case 1:
            return try readManhattanVFirst(count: pointCount)
        case 2:
            return try readManhattanAny(count: pointCount)
        case 3:
            return try readOctangular(count: pointCount)
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
            points.append(IRPoint(
                x: try checkedInt32(dx, context: "general point-list dx"),
                y: try checkedInt32(dy, context: "general point-list dy")
            ))
        }
        return points
    }

    private mutating func readManhattanHFirst(count: Int) throws -> [IRPoint] {
        var points: [IRPoint] = []
        points.reserveCapacity(count)
        for i in 0..<count {
            let delta = try readSignedInteger()
            if i % 2 == 0 {
                points.append(IRPoint(x: try checkedInt32(delta, context: "manhattan point-list dx"), y: 0))
            } else {
                points.append(IRPoint(x: 0, y: try checkedInt32(delta, context: "manhattan point-list dy")))
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
                points.append(IRPoint(x: 0, y: try checkedInt32(delta, context: "manhattan point-list dy")))
            } else {
                points.append(IRPoint(x: try checkedInt32(delta, context: "manhattan point-list dx"), y: 0))
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
            let mag = try checkedInt64(encoded >> 2, context: "manhattan point-list magnitude")
            switch dir {
            case 0: points.append(IRPoint(x: try checkedInt32(mag, context: "manhattan point-list dx"), y: 0))
            case 1: points.append(IRPoint(x: 0, y: try checkedInt32(mag, context: "manhattan point-list dy")))
            case 2: points.append(IRPoint(x: try checkedInt32(-mag, context: "manhattan point-list dx"), y: 0))
            case 3: points.append(IRPoint(x: 0, y: try checkedInt32(-mag, context: "manhattan point-list dy")))
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
            let mag = try checkedInt32(
                try checkedInt64(encoded >> 3, context: "octangular point-list magnitude"),
                context: "octangular point-list magnitude"
            )
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
            let xDim = try readRepetitionDimension(context: "grid columns")
            let yDim = try readRepetitionDimension(context: "grid rows")
            let xSpace = try readUnsignedInteger()
            let ySpace = try readUnsignedInteger()
            return .grid(columns: xDim, rows: yDim, colSpacing: xSpace, rowSpacing: ySpace)
        case 2:
            let xDim = try readRepetitionDimension(context: "uniform row count")
            let xSpace = try readUnsignedInteger()
            return .uniformRow(count: xDim, spacing: xSpace)
        case 3:
            let yDim = try readRepetitionDimension(context: "uniform column count")
            let ySpace = try readUnsignedInteger()
            return .uniformColumn(count: yDim, spacing: ySpace)
        case 4:
            let xDim = try readRepetitionDimension(context: "variable row count")
            var spacings: [UInt64] = []
            spacings.reserveCapacity(try checkedCollectionCount(xDim - 1, context: "variable row spacings"))
            for _ in 0..<(xDim - 1) {
                spacings.append(try readUnsignedInteger())
            }
            return .variableRow(spacings: spacings)
        case 5:
            let xDim = try readRepetitionDimension(context: "arbitrary grid columns")
            let yDim = try readRepetitionDimension(context: "arbitrary grid rows")
            let colDisp = try readGDelta()
            let rowDisp = try readGDelta()
            return .arbitraryGrid(columns: xDim, rows: yDim, colDisplacement: colDisp, rowDisplacement: rowDisp)
        case 6:
            let yDim = try readRepetitionDimension(context: "variable column count")
            var spacings: [UInt64] = []
            spacings.reserveCapacity(try checkedCollectionCount(yDim - 1, context: "variable column spacings"))
            for _ in 0..<(yDim - 1) {
                spacings.append(try readUnsignedInteger())
            }
            return .variableColumn(spacings: spacings)
        case 7:
            let count = try readRepetitionDimension(context: "variable displacement row count")
            var displacements: [OASISDisplacement] = []
            displacements.reserveCapacity(try checkedCollectionCount(count - 1, context: "variable displacement row"))
            for _ in 0..<(count - 1) {
                displacements.append(try readGDelta())
            }
            return .variableDisplacementRow(displacements: displacements)
        case 8:
            let count = try readRepetitionDimension(context: "variable displacement column count")
            var displacements: [OASISDisplacement] = []
            displacements.reserveCapacity(try checkedCollectionCount(count - 1, context: "variable displacement column"))
            for _ in 0..<(count - 1) {
                displacements.append(try readGDelta())
            }
            return .variableDisplacementColumn(displacements: displacements)
        case 9:
            let count = try readRepetitionDimension(context: "repeated displacement row count")
            let disp = try readGDelta()
            let displacementCount = try checkedCollectionCount(count - 1, context: "repeated displacement row")
            return .variableDisplacementRow(displacements: Array(repeating: disp, count: displacementCount))
        case 10:
            let count = try readRepetitionDimension(context: "repeated displacement column count")
            let disp = try readGDelta()
            let displacementCount = try checkedCollectionCount(count - 1, context: "repeated displacement column")
            return .variableDisplacementColumn(displacements: Array(repeating: disp, count: displacementCount))
        case 11:
            let xDim = try readRepetitionDimension(context: "arbitrary grid columns")
            let yDim = try readRepetitionDimension(context: "arbitrary grid rows")
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
            let mag = try checkedInt64(encoded >> 3, context: "g-delta magnitude")
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

    private func checkedByteCount(_ value: UInt64, context: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        let count = Int(value)
        guard count <= data.count - offset else {
            throw OASISError.unexpectedEndOfData(offset: offset)
        }
        return count
    }

    private func checkedInt(_ value: UInt64, context: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int(value)
    }

    private func checkedCollectionCount(_ value: UInt64, context: String) throws -> Int {
        let count = try checkedInt(value, context: context)
        guard count <= Self.maxDecodedCollectionElements else {
            throw OASISError.numericOverflow(
                context: context,
                value: "\(value) exceeds supported limit \(Self.maxDecodedCollectionElements)"
            )
        }
        return count
    }

    private func checkedInt64(_ value: UInt64, context: String) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int64(value)
    }

    private func checkedInt32(_ value: Int64, context: String) throws -> Int32 {
        guard value >= Int64(Int32.min), value <= Int64(Int32.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int32(value)
    }

    private mutating func readRepetitionDimension(context: String) throws -> UInt64 {
        let raw = try readUnsignedInteger()
        guard raw <= UInt64.max - 2 else {
            throw OASISError.numericOverflow(context: context, value: String(raw))
        }
        return raw + 2
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
