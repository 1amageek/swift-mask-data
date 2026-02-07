import Foundation

/// Low-level GDSII record reader. Reads records one at a time from binary data.
public struct GDSRecordReader: Sendable {
    private let data: Data
    private var offset: Int

    public init(data: Data) {
        self.data = data
        self.offset = 0
    }

    public var hasMore: Bool { offset < data.count }
    public var currentOffset: Int { offset }

    /// Reads the next record from the stream.
    public mutating func readRecord() throws -> GDSRecord {
        let startOffset = offset

        guard offset + 4 <= data.count else {
            throw GDSError.unexpectedEndOfData(offset: startOffset)
        }

        let length = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        let recordTypeByte = data[offset + 2]
        let dataTypeByte = data[offset + 3]

        guard length >= 4 else {
            throw GDSError.invalidRecordLength(offset: startOffset, length: length)
        }

        guard offset + Int(length) <= data.count else {
            throw GDSError.unexpectedEndOfData(offset: startOffset)
        }

        guard let recordType = GDSRecordType(validating: recordTypeByte) else {
            throw GDSError.unknownRecordType(offset: startOffset, rawValue: recordTypeByte)
        }

        guard let dataType = GDSDataType(rawValue: dataTypeByte) else {
            throw GDSError.unknownDataType(offset: startOffset, rawValue: dataTypeByte)
        }

        let payloadLength = Int(length) - 4
        let payloadStart = offset + 4
        let payload = try parsePayload(dataType: dataType, start: payloadStart, length: payloadLength, offset: startOffset)

        offset += Int(length)
        return GDSRecord(recordType: recordType, payload: payload)
    }

    /// Peeks at the next record type without advancing.
    public func peekRecordType() throws -> GDSRecordType {
        guard offset + 4 <= data.count else {
            throw GDSError.unexpectedEndOfData(offset: offset)
        }
        let recordTypeByte = data[offset + 2]
        guard let recordType = GDSRecordType(validating: recordTypeByte) else {
            throw GDSError.unknownRecordType(offset: offset, rawValue: recordTypeByte)
        }
        return recordType
    }

    // MARK: - Payload parsing

    private func parsePayload(dataType: GDSDataType, start: Int, length: Int, offset: Int) throws -> GDSRecordPayload {
        switch dataType {
        case .noData:
            return .noData

        case .bitArray:
            guard length >= 2 else { return .bitArray(0) }
            let value = UInt16(data[start]) << 8 | UInt16(data[start + 1])
            return .bitArray(value)

        case .int16:
            let count = length / 2
            var values: [Int16] = []
            values.reserveCapacity(count)
            for i in 0..<count {
                let pos = start + i * 2
                let value = Int16(bitPattern: UInt16(data[pos]) << 8 | UInt16(data[pos + 1]))
                values.append(value)
            }
            return .int16(values)

        case .int32:
            let count = length / 4
            var values: [Int32] = []
            values.reserveCapacity(count)
            for i in 0..<count {
                let pos = start + i * 4
                let value = Int32(bitPattern:
                    UInt32(data[pos]) << 24 |
                    UInt32(data[pos + 1]) << 16 |
                    UInt32(data[pos + 2]) << 8 |
                    UInt32(data[pos + 3])
                )
                values.append(value)
            }
            return .int32(values)

        case .real4:
            // Real4 is essentially unused in GDSII. Treat as raw data / skip.
            return .noData

        case .real8:
            let count = length / 8
            var values: [Double] = []
            values.reserveCapacity(count)
            for i in 0..<count {
                let pos = start + i * 8
                let bytes = (
                    data[pos], data[pos + 1], data[pos + 2], data[pos + 3],
                    data[pos + 4], data[pos + 5], data[pos + 6], data[pos + 7]
                )
                values.append(GDSReal8.toDouble(bytes))
            }
            return .real8(values)

        case .string:
            var end = start + length
            // Strip trailing null/padding bytes
            while end > start && data[end - 1] == 0 {
                end -= 1
            }
            let stringData = data[start..<end]
            guard let str = String(data: stringData, encoding: .ascii) else {
                throw GDSError.invalidString(offset: offset)
            }
            return .string(str)
        }
    }
}
