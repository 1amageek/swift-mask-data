import Foundation
import LayoutIR

/// Low-level GDSII record writer. Appends records to a binary buffer.
public struct GDSRecordWriter: Sendable {
    private var buffer: Data

    /// Maximum number of coordinate values per XY record.
    /// Max payload = 65534 - 4 = 65530 bytes. Each Int32 is 4 bytes → 16382 values (8191 pairs).
    private static let maxXYValuesPerRecord = 16382

    public init() {
        self.buffer = Data()
    }

    public var data: Data { buffer }

    public mutating func writeNoData(_ type: GDSRecordType) {
        writeHeader(type: type, dataType: .noData, payloadLength: 0)
    }

    public mutating func writeBitArray(_ type: GDSRecordType, value: UInt16) {
        writeHeader(type: type, dataType: .bitArray, payloadLength: 2)
        buffer.append(UInt8(value >> 8))
        buffer.append(UInt8(value & 0xFF))
    }

    public mutating func writeInt16(_ type: GDSRecordType, values: [Int16]) {
        writeHeader(type: type, dataType: .int16, payloadLength: values.count * 2)
        for v in values {
            let bits = UInt16(bitPattern: v)
            buffer.append(UInt8(bits >> 8))
            buffer.append(UInt8(bits & 0xFF))
        }
    }

    public mutating func writeInt32(_ type: GDSRecordType, values: [Int32]) {
        writeHeader(type: type, dataType: .int32, payloadLength: values.count * 4)
        for v in values {
            let bits = UInt32(bitPattern: v)
            buffer.append(UInt8((bits >> 24) & 0xFF))
            buffer.append(UInt8((bits >> 16) & 0xFF))
            buffer.append(UInt8((bits >> 8) & 0xFF))
            buffer.append(UInt8(bits & 0xFF))
        }
    }

    public mutating func writeReal8(_ type: GDSRecordType, values: [Double]) {
        writeHeader(type: type, dataType: .real8, payloadLength: values.count * 8)
        for v in values {
            let bytes = GDSReal8.fromDouble(v)
            buffer.append(bytes.0)
            buffer.append(bytes.1)
            buffer.append(bytes.2)
            buffer.append(bytes.3)
            buffer.append(bytes.4)
            buffer.append(bytes.5)
            buffer.append(bytes.6)
            buffer.append(bytes.7)
        }
    }

    public mutating func writeString(_ type: GDSRecordType, value: String) {
        let utf8 = value.utf8
        let padded = utf8.count % 2 != 0
        writeHeader(type: type, dataType: .string, payloadLength: utf8.count + (padded ? 1 : 0))
        buffer.append(contentsOf: utf8)
        if padded { buffer.append(0) }
    }

    /// Writes XY coordinate data, splitting into multiple records if needed (Multi-XY).
    public mutating func writeXY(_ points: [IRPoint]) {
        let totalValues = points.count * 2
        let maxValues = Self.maxXYValuesPerRecord

        if totalValues <= maxValues {
            // Fast path: single record, write directly without intermediate array
            writeHeader(type: .xy, dataType: .int32, payloadLength: totalValues * 4)
            for p in points {
                appendInt32(p.x)
                appendInt32(p.y)
            }
        } else {
            // Multi-XY: build values array and chunk
            var values = [Int32]()
            values.reserveCapacity(totalValues)
            for p in points {
                values.append(p.x)
                values.append(p.y)
            }
            var startIndex = 0
            while startIndex < values.count {
                let endIndex = min(startIndex + maxValues, values.count)
                writeInt32(.xy, values: Array(values[startIndex..<endIndex]))
                startIndex = endIndex
            }
        }
    }

    private mutating func appendInt32(_ v: Int32) {
        let bits = UInt32(bitPattern: v)
        buffer.append(UInt8((bits >> 24) & 0xFF))
        buffer.append(UInt8((bits >> 16) & 0xFF))
        buffer.append(UInt8((bits >> 8) & 0xFF))
        buffer.append(UInt8(bits & 0xFF))
    }

    // MARK: - Private

    private mutating func writeHeader(type: GDSRecordType, dataType: GDSDataType, payloadLength: Int) {
        precondition(payloadLength + 4 <= 65534, "Record payload too large for GDSII format")
        let totalLength = UInt16(4 + payloadLength)
        buffer.append(UInt8(totalLength >> 8))
        buffer.append(UInt8(totalLength & 0xFF))
        buffer.append(type.rawValue)
        buffer.append(dataType.rawValue)
    }
}
