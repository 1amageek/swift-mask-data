import Foundation
import LayoutIR
import Compression

/// Low-level OASIS binary writer.
public struct OASISWriter: Sendable {
    public private(set) var data: Data

    public init() {
        self.data = Data()
    }

    // MARK: - Byte

    public mutating func writeByte(_ value: UInt8) {
        data.append(value)
    }

    public mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    // MARK: - Unsigned Integer (LEB128)

    public mutating func writeUnsignedInteger(_ value: UInt64) {
        var v = value
        while true {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                byte |= 0x80
            }
            data.append(byte)
            if v == 0 { break }
        }
    }

    // MARK: - Signed Integer (Zigzag)

    public mutating func writeSignedInteger(_ value: Int64) {
        // Zigzag encode: (n << 1) ^ (n >> 63)
        let encoded: UInt64
        if value >= 0 {
            encoded = UInt64(value) << 1
        } else {
            encoded = (UInt64(bitPattern: -(value + 1)) << 1) | 1
        }
        writeUnsignedInteger(encoded)
    }

    // MARK: - Real Number

    public mutating func writeReal(_ value: Double) {
        if value == 0.0 {
            // Type 0: positive integer 0
            writeUnsignedInteger(0)
            writeUnsignedInteger(0)
            return
        }

        // Check if it's an exact integer
        if value == value.rounded(.towardZero) && abs(value) < Double(UInt64.max) {
            if value > 0 {
                // Type 0: positive integer
                writeUnsignedInteger(0)
                writeUnsignedInteger(UInt64(value))
            } else {
                // Type 1: negative integer
                writeUnsignedInteger(1)
                writeUnsignedInteger(UInt64(-value))
            }
            return
        }

        // Check if it's a simple reciprocal (1/n)
        if value != 0 {
            let reciprocal = 1.0 / abs(value)
            if reciprocal == reciprocal.rounded(.towardZero) && reciprocal >= 1 && reciprocal < Double(UInt64.max) {
                let n = UInt64(reciprocal)
                if abs(1.0 / Double(n) - abs(value)) < 1e-15 {
                    if value > 0 {
                        writeUnsignedInteger(2)
                    } else {
                        writeUnsignedInteger(3)
                    }
                    writeUnsignedInteger(n)
                    return
                }
            }
        }

        // Fallback: Type 7 IEEE float64
        writeUnsignedInteger(7)
        var bits = value.bitPattern
        for _ in 0..<8 {
            data.append(UInt8(bits & 0xFF))
            bits >>= 8
        }
    }

    // MARK: - Strings

    public mutating func writeAString(_ value: String) {
        let utf8 = value.utf8
        writeUnsignedInteger(UInt64(utf8.count))
        data.append(contentsOf: utf8)
    }

    public mutating func writeBString(_ value: Data) {
        writeUnsignedInteger(UInt64(value.count))
        data.append(value)
    }

    // MARK: - Magic

    public mutating func writeMagic() {
        data.append(contentsOf: "%SEMI-OASIS\r\n".utf8)
    }

    // MARK: - Point List

    public mutating func writePointList(_ points: [IRPoint]) {
        // Try optimized encodings first
        if let manhattanType = detectManhattanHV(points) {
            writeManhattanHVPointList(points, type: manhattanType)
            return
        }

        if isManhattanAny(points) {
            writeManhattanAnyPointList(points)
            return
        }

        if isOctangular(points) {
            writeOctangularPointList(points)
            return
        }

        // Fallback: type 4 (general delta pairs)
        writeUnsignedInteger(4)
        writeUnsignedInteger(UInt64(points.count))
        for point in points {
            writeSignedInteger(Int64(point.x))
            writeSignedInteger(Int64(point.y))
        }
    }

    /// Detect if points are Manhattan H-first (type 0) or V-first (type 1).
    private func detectManhattanHV(_ points: [IRPoint]) -> UInt64? {
        guard !points.isEmpty else { return nil }
        // Check if all deltas are pure H or V, alternating
        var isHFirst = true
        var isVFirst = true
        for (i, p) in points.enumerated() {
            let isH = (p.y == 0 && p.x != 0)
            let isV = (p.x == 0 && p.y != 0)
            let isZero = (p.x == 0 && p.y == 0)
            if !isH && !isV && !isZero { return nil }
            if i % 2 == 0 {
                if !isH && !isZero { isHFirst = false }
                if !isV && !isZero { isVFirst = false }
            } else {
                if !isV && !isZero { isHFirst = false }
                if !isH && !isZero { isVFirst = false }
            }
        }
        if isHFirst { return 0 }
        if isVFirst { return 1 }
        return nil
    }

    private mutating func writeManhattanHVPointList(_ points: [IRPoint], type: UInt64) {
        writeUnsignedInteger(type)
        writeUnsignedInteger(UInt64(points.count))
        for (i, p) in points.enumerated() {
            if type == 0 {
                // H-first: even=H, odd=V
                writeSignedInteger(i % 2 == 0 ? Int64(p.x) : Int64(p.y))
            } else {
                // V-first: even=V, odd=H
                writeSignedInteger(i % 2 == 0 ? Int64(p.y) : Int64(p.x))
            }
        }
    }

    private func isManhattanAny(_ points: [IRPoint]) -> Bool {
        for p in points {
            if p.x != 0 && p.y != 0 { return false }
            if p.x == 0 && p.y == 0 { return false }
        }
        return !points.isEmpty
    }

    private mutating func writeManhattanAnyPointList(_ points: [IRPoint]) {
        writeUnsignedInteger(2)
        writeUnsignedInteger(UInt64(points.count))
        for p in points {
            let dir: UInt64
            let mag: UInt64
            if p.x > 0 { dir = 0; mag = UInt64(p.x) }
            else if p.y > 0 { dir = 1; mag = UInt64(p.y) }
            else if p.x < 0 { dir = 2; mag = UInt64(-Int64(p.x)) }
            else { dir = 3; mag = UInt64(-Int64(p.y)) }
            writeUnsignedInteger((mag << 2) | dir)
        }
    }

    private func isOctangular(_ points: [IRPoint]) -> Bool {
        for p in points {
            if p.x == 0 || p.y == 0 { continue }
            if abs(p.x) == abs(p.y) { continue }
            return false
        }
        return !points.isEmpty
    }

    private mutating func writeOctangularPointList(_ points: [IRPoint]) {
        writeUnsignedInteger(3)
        writeUnsignedInteger(UInt64(points.count))
        for p in points {
            let dir: UInt64
            let mag: UInt64
            if p.y == 0 && p.x > 0 { dir = 0; mag = UInt64(p.x) }
            else if p.x == 0 && p.y > 0 { dir = 1; mag = UInt64(p.y) }
            else if p.y == 0 && p.x < 0 { dir = 2; mag = UInt64(-Int64(p.x)) }
            else if p.x == 0 && p.y < 0 { dir = 3; mag = UInt64(-Int64(p.y)) }
            else if p.x > 0 && p.y > 0 { dir = 4; mag = UInt64(p.x) }
            else if p.x < 0 && p.y > 0 { dir = 5; mag = UInt64(p.y) }
            else if p.x > 0 && p.y < 0 { dir = 6; mag = UInt64(p.x) }
            else { dir = 7; mag = UInt64(-Int64(p.x)) }
            writeUnsignedInteger((mag << 3) | dir)
        }
    }

    // MARK: - Repetition

    public mutating func writeRepetition(_ rep: OASISRepetition) {
        switch rep {
        case .grid(let columns, let rows, let colSpacing, let rowSpacing):
            writeUnsignedInteger(1)
            writeUnsignedInteger(columns - 2)
            writeUnsignedInteger(rows - 2)
            writeUnsignedInteger(colSpacing)
            writeUnsignedInteger(rowSpacing)
        case .uniformRow(let count, let spacing):
            writeUnsignedInteger(2)
            writeUnsignedInteger(count - 2)
            writeUnsignedInteger(spacing)
        case .uniformColumn(let count, let spacing):
            writeUnsignedInteger(3)
            writeUnsignedInteger(count - 2)
            writeUnsignedInteger(spacing)
        case .variableRow(let spacings):
            writeUnsignedInteger(4)
            writeUnsignedInteger(UInt64(spacings.count + 1) - 2)
            for s in spacings {
                writeUnsignedInteger(s)
            }
        case .variableColumn(let spacings):
            writeUnsignedInteger(6)
            writeUnsignedInteger(UInt64(spacings.count + 1) - 2)
            for s in spacings {
                writeUnsignedInteger(s)
            }
        case .arbitraryGrid(let columns, let rows, let colDisp, let rowDisp):
            writeUnsignedInteger(5)
            writeUnsignedInteger(columns - 2)
            writeUnsignedInteger(rows - 2)
            writeGDelta(colDisp)
            writeGDelta(rowDisp)
        case .variableDisplacementRow(let displacements):
            writeUnsignedInteger(7)
            writeUnsignedInteger(UInt64(displacements.count + 1) - 2)
            for d in displacements {
                writeGDelta(d)
            }
        case .variableDisplacementColumn(let displacements):
            writeUnsignedInteger(8)
            writeUnsignedInteger(UInt64(displacements.count + 1) - 2)
            for d in displacements {
                writeGDelta(d)
            }
        }
    }

    private mutating func writeGDelta(_ d: OASISDisplacement) {
        if d.dy == 0 && d.dx > 0 {
            writeUnsignedInteger(UInt64(d.dx) << 3 | 0 << 1 | 0) // east
        } else if d.dx == 0 && d.dy > 0 {
            writeUnsignedInteger(UInt64(d.dy) << 3 | 1 << 1 | 0) // north
        } else if d.dy == 0 && d.dx < 0 {
            writeUnsignedInteger(UInt64(-d.dx) << 3 | 2 << 1 | 0) // west
        } else if d.dx == 0 && d.dy < 0 {
            writeUnsignedInteger(UInt64(-d.dy) << 3 | 3 << 1 | 0) // south
        } else {
            // General delta
            writeUnsignedInteger(1) // flag bit = 1
            writeSignedInteger(d.dx)
            writeSignedInteger(d.dy)
        }
    }

    // MARK: - CBLOCK Compression

    public mutating func writeCBlock(_ uncompressedData: Data) {
        writeByte(OASISRecordType.cblock.rawValue)
        writeUnsignedInteger(0) // compression type: DEFLATE

        let compressed = compressDeflate(uncompressedData)
        writeUnsignedInteger(UInt64(uncompressedData.count))
        writeUnsignedInteger(UInt64(compressed.count))
        data.append(compressed)
    }

    private func compressDeflate(_ source: Data) -> Data {
        let sourceSize = source.count
        let destSize = sourceSize + 512 // extra room for compression overhead
        var dest = Data(count: destSize)

        let result = dest.withUnsafeMutableBytes { destBuffer in
            source.withUnsafeBytes { srcBuffer in
                guard let destPtr = destBuffer.baseAddress,
                      let srcPtr = srcBuffer.baseAddress else { return 0 }
                return compression_encode_buffer(
                    destPtr.assumingMemoryBound(to: UInt8.self),
                    destSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        if result > 0 {
            return dest.prefix(result)
        }
        // Fallback: return uncompressed (should not happen)
        return source
    }

    // MARK: - Property Value

    public mutating func writePropertyValue(_ value: OASISPropertyValue) {
        switch value {
        case .real(let v):
            writeUnsignedInteger(0)
            writeReal(v)
        case .unsignedInteger(let v):
            writeUnsignedInteger(1)
            writeUnsignedInteger(v)
        case .signedInteger(let v):
            writeUnsignedInteger(2)
            writeSignedInteger(v)
        case .aString(let s):
            writeUnsignedInteger(3)
            writeAString(s)
        case .bString(let bytes):
            writeUnsignedInteger(4)
            writeBString(Data(bytes))
        case .reference(let ref):
            writeUnsignedInteger(14)
            writeUnsignedInteger(ref)
        }
    }
}
