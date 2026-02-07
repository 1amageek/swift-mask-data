import Testing
import Foundation
import LayoutIR
@testable import OASIS

// MARK: - Step 1: Record Types

@Suite("OASISRecordType")
struct OASISRecordTypeTests {
    @Test func coreRecordIDs() {
        #expect(OASISRecordType.pad.rawValue == 0)
        #expect(OASISRecordType.start.rawValue == 1)
        #expect(OASISRecordType.end.rawValue == 2)
    }

    @Test func nameRecordIDs() {
        #expect(OASISRecordType.cellname.rawValue == 3)
        #expect(OASISRecordType.cellnameRef.rawValue == 4)
        #expect(OASISRecordType.textstring.rawValue == 5)
        #expect(OASISRecordType.textstringRef.rawValue == 6)
        #expect(OASISRecordType.propname.rawValue == 7)
        #expect(OASISRecordType.propnameRef.rawValue == 8)
    }

    @Test func geometryRecordIDs() {
        #expect(OASISRecordType.cell.rawValue == 13)
        #expect(OASISRecordType.cellRef.rawValue == 14)
        #expect(OASISRecordType.xyAbsolute.rawValue == 15)
        #expect(OASISRecordType.xyRelative.rawValue == 16)
        #expect(OASISRecordType.placement.rawValue == 17)
        #expect(OASISRecordType.placementT.rawValue == 18)
        #expect(OASISRecordType.text.rawValue == 19)
        #expect(OASISRecordType.rectangle.rawValue == 20)
        #expect(OASISRecordType.polygon.rawValue == 21)
        #expect(OASISRecordType.path.rawValue == 22)
        #expect(OASISRecordType.cblock.rawValue == 34)
    }
}

// MARK: - Step 2: LEB128

@Suite("LEB128 Unsigned")
struct LEB128UnsignedTests {
    @Test func readZero() throws {
        var reader = OASISReader(data: Data([0x00]))
        let value = try reader.readUnsignedInteger()
        #expect(value == 0)
    }

    @Test func read127() throws {
        var reader = OASISReader(data: Data([0x7F]))
        let value = try reader.readUnsignedInteger()
        #expect(value == 127)
    }

    @Test func read128() throws {
        var reader = OASISReader(data: Data([0x80, 0x01]))
        let value = try reader.readUnsignedInteger()
        #expect(value == 128)
    }

    @Test func read300() throws {
        var reader = OASISReader(data: Data([0xAC, 0x02]))
        let value = try reader.readUnsignedInteger()
        #expect(value == 300)
    }

    @Test func read16384() throws {
        // 16384 = 0x80 0x80 0x01
        var reader = OASISReader(data: Data([0x80, 0x80, 0x01]))
        let value = try reader.readUnsignedInteger()
        #expect(value == 16384)
    }

    @Test func writeReadRoundTrip() throws {
        let testValues: [UInt64] = [0, 1, 127, 128, 255, 256, 16383, 16384, 1_000_000]
        for original in testValues {
            var writer = OASISWriter()
            writer.writeUnsignedInteger(original)
            var reader = OASISReader(data: writer.data)
            let decoded = try reader.readUnsignedInteger()
            #expect(decoded == original, "Round-trip failed for \(original)")
        }
    }

    @Test func emptyDataThrows() {
        var reader = OASISReader(data: Data())
        #expect(throws: OASISError.self) {
            _ = try reader.readUnsignedInteger()
        }
    }
}

@Suite("LEB128 Signed (Zigzag)")
struct LEB128SignedTests {
    @Test func readZero() throws {
        // zigzag(0) = 0
        var reader = OASISReader(data: Data([0x00]))
        let value = try reader.readSignedInteger()
        #expect(value == 0)
    }

    @Test func readPositiveOne() throws {
        // zigzag(1) = 2 → 0x02
        var reader = OASISReader(data: Data([0x02]))
        let value = try reader.readSignedInteger()
        #expect(value == 1)
    }

    @Test func readNegativeOne() throws {
        // zigzag(-1) = 1 → 0x01
        var reader = OASISReader(data: Data([0x01]))
        let value = try reader.readSignedInteger()
        #expect(value == -1)
    }

    @Test func readPositiveTwo() throws {
        // zigzag(2) = 4 → 0x04
        var reader = OASISReader(data: Data([0x04]))
        let value = try reader.readSignedInteger()
        #expect(value == 2)
    }

    @Test func readNegativeTwo() throws {
        // zigzag(-2) = 3 → 0x03
        var reader = OASISReader(data: Data([0x03]))
        let value = try reader.readSignedInteger()
        #expect(value == -2)
    }

    @Test func writeReadRoundTrip() throws {
        let testValues: [Int64] = [0, 1, -1, 127, -128, 1000, -1000, 1_000_000, -1_000_000]
        for original in testValues {
            var writer = OASISWriter()
            writer.writeSignedInteger(original)
            var reader = OASISReader(data: writer.data)
            let decoded = try reader.readSignedInteger()
            #expect(decoded == original, "Round-trip failed for \(original)")
        }
    }
}

// MARK: - Step 3: Real Numbers

@Suite("OASIS Real Numbers")
struct OASISRealTests {
    @Test func positiveInteger() throws {
        // Type 0: value = 42
        var writer = OASISWriter()
        writer.writeUnsignedInteger(0)  // type
        writer.writeUnsignedInteger(42) // value
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(value == 42.0)
    }

    @Test func negativeInteger() throws {
        // Type 1: value = -42
        var writer = OASISWriter()
        writer.writeUnsignedInteger(1)
        writer.writeUnsignedInteger(42)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(value == -42.0)
    }

    @Test func positiveReciprocal() throws {
        // Type 2: 1/4 = 0.25
        var writer = OASISWriter()
        writer.writeUnsignedInteger(2)
        writer.writeUnsignedInteger(4)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(abs(value - 0.25) < 1e-15)
    }

    @Test func negativeReciprocal() throws {
        // Type 3: -1/4
        var writer = OASISWriter()
        writer.writeUnsignedInteger(3)
        writer.writeUnsignedInteger(4)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(abs(value - (-0.25)) < 1e-15)
    }

    @Test func positiveRatio() throws {
        // Type 4: 3/7
        var writer = OASISWriter()
        writer.writeUnsignedInteger(4)
        writer.writeUnsignedInteger(3)
        writer.writeUnsignedInteger(7)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(abs(value - (3.0 / 7.0)) < 1e-15)
    }

    @Test func negativeRatio() throws {
        // Type 5: -3/7
        var writer = OASISWriter()
        writer.writeUnsignedInteger(5)
        writer.writeUnsignedInteger(3)
        writer.writeUnsignedInteger(7)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(abs(value - (-3.0 / 7.0)) < 1e-15)
    }

    @Test func ieeeFloat64() throws {
        // Type 7: IEEE 754 double
        let original = 3.14159265358979
        var writer = OASISWriter()
        writer.writeUnsignedInteger(7)
        var bits = original.bitPattern
        for _ in 0..<8 {
            writer.writeByte(UInt8(bits & 0xFF))
            bits >>= 8
        }
        var reader = OASISReader(data: writer.data)
        let value = try reader.readReal()
        #expect(abs(value - original) < 1e-13)
    }

    @Test func writeReadRealRoundTrip() throws {
        let values: [Double] = [0.0, 1.0, -1.0, 0.5, -0.5, 42.0, 0.001, 1e-6]
        for original in values {
            var writer = OASISWriter()
            writer.writeReal(original)
            var reader = OASISReader(data: writer.data)
            let decoded = try reader.readReal()
            if original == 0.0 {
                #expect(decoded == 0.0)
            } else {
                let relError = abs(decoded - original) / abs(original)
                #expect(relError < 1e-13, "Round-trip failed for \(original)")
            }
        }
    }
}

// MARK: - Step 4: Strings

@Suite("OASIS Strings")
struct OASISStringTests {
    @Test func emptyString() throws {
        var writer = OASISWriter()
        writer.writeAString("")
        var reader = OASISReader(data: writer.data)
        let value = try reader.readAString()
        #expect(value == "")
    }

    @Test func simpleASCII() throws {
        var writer = OASISWriter()
        writer.writeAString("NAND2")
        var reader = OASISReader(data: writer.data)
        let value = try reader.readAString()
        #expect(value == "NAND2")
    }

    @Test func longerString() throws {
        let original = "METAL1_ROUTING_LAYER"
        var writer = OASISWriter()
        writer.writeAString(original)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readAString()
        #expect(value == original)
    }

    @Test func binaryString() throws {
        let original = Data([0x00, 0xFF, 0x42, 0x7E])
        var writer = OASISWriter()
        writer.writeBString(original)
        var reader = OASISReader(data: writer.data)
        let value = try reader.readBString()
        #expect(value == original)
    }
}

// MARK: - Step 5: Magic

@Suite("OASIS Magic")
struct OASISMagicTests {
    @Test func validMagic() throws {
        let magic = Array("%SEMI-OASIS\r\n".utf8)
        var reader = OASISReader(data: Data(magic))
        try reader.validateMagic()
    }

    @Test func invalidMagicThrows() {
        var reader = OASISReader(data: Data([0x00, 0x01, 0x02]))
        #expect(throws: OASISError.self) {
            try reader.validateMagic()
        }
    }

    @Test func writeMagicCorrectBytes() {
        var writer = OASISWriter()
        writer.writeMagic()
        let expected = Array("%SEMI-OASIS\r\n".utf8)
        #expect(Array(writer.data) == expected)
    }
}
