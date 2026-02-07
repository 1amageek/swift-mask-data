import Testing
@testable import GDSII

@Suite("GDSReal8")
struct GDSReal8Tests {

    // MARK: - toDouble: known byte patterns

    @Test func zeroBytes() {
        let result = GDSReal8.toDouble((0, 0, 0, 0, 0, 0, 0, 0))
        #expect(result == 0.0)
    }

    @Test func onePointZero() {
        // 1.0 = (1/16) * 16^1 → exponent=65 (0x41), mantissa=0x10000000000000
        // Byte 0: 0x41, Byte 1: 0x10, rest: 0
        let result = GDSReal8.toDouble((0x41, 0x10, 0, 0, 0, 0, 0, 0))
        #expect(abs(result - 1.0) < 1e-15)
    }

    @Test func negativeOne() {
        // -1.0: sign bit set → 0xC1
        let result = GDSReal8.toDouble((0xC1, 0x10, 0, 0, 0, 0, 0, 0))
        #expect(abs(result - (-1.0)) < 1e-15)
    }

    @Test func zeroPointOne() {
        // 0.1 = 0x40 19999999999999 (approximately)
        // 0.1 = (mantissa/2^56) * 16^0 where mantissa ≈ 0.1 * 2^56
        let result = GDSReal8.toDouble((0x40, 0x19, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9A))
        #expect(abs(result - 0.1) < 1e-15)
    }

    @Test func oneMicronInMeters() {
        // 1e-6: typical GDSII user unit — verify via round-trip
        let bytes = GDSReal8.fromDouble(1e-6)
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - 1e-6) / 1e-6 < 1e-13)
    }

    @Test func oneNanometerInMeters() {
        // 1e-9: typical GDSII database unit for nm resolution — verify via round-trip
        let bytes = GDSReal8.fromDouble(1e-9)
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - 1e-9) / 1e-9 < 1e-13)
    }

    // MARK: - fromDouble: basic values

    @Test func fromDoubleZero() {
        let bytes = GDSReal8.fromDouble(0.0)
        let result = GDSReal8.toDouble(bytes)
        #expect(result == 0.0)
        #expect(bytes.0 == 0)
        #expect(bytes.1 == 0)
    }

    @Test func fromDoubleOne() {
        let bytes = GDSReal8.fromDouble(1.0)
        // Must decode back to 1.0
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - 1.0) < 1e-15)
        // Check exponent byte: should be 0x41
        #expect(bytes.0 == 0x41)
    }

    @Test func fromDoubleNegativeOne() {
        let bytes = GDSReal8.fromDouble(-1.0)
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - (-1.0)) < 1e-15)
        #expect(bytes.0 & 0x80 != 0) // sign bit set
    }

    // MARK: - Round-trip tests

    @Test func roundTripTypicalValues() {
        let values: [Double] = [
            0.0, 1.0, -1.0, 0.5, -0.5,
            0.001,    // user units per DBU (µm)
            1e-6,     // meters per µm
            1e-9,     // meters per nm
            3.14159265358979,
            100.0, 0.0001, 1e-12,
        ]
        for original in values {
            let bytes = GDSReal8.fromDouble(original)
            let decoded = GDSReal8.toDouble(bytes)
            if original == 0.0 {
                #expect(decoded == 0.0, "Round-trip failed for 0.0")
            } else {
                let relativeError = abs(decoded - original) / abs(original)
                #expect(relativeError < 1e-13, "Round-trip failed for \(original): got \(decoded), relative error \(relativeError)")
            }
        }
    }

    @Test func roundTripSmallValues() {
        let values: [Double] = [1e-15, 1e-18, 1e-20]
        for original in values {
            let bytes = GDSReal8.fromDouble(original)
            let decoded = GDSReal8.toDouble(bytes)
            let relativeError = abs(decoded - original) / abs(original)
            #expect(relativeError < 1e-10, "Round-trip failed for \(original)")
        }
    }

    @Test func roundTripLargeValues() {
        let values: [Double] = [1e6, 1e9, 1e12]
        for original in values {
            let bytes = GDSReal8.fromDouble(original)
            let decoded = GDSReal8.toDouble(bytes)
            let relativeError = abs(decoded - original) / abs(original)
            #expect(relativeError < 1e-13, "Round-trip failed for \(original)")
        }
    }
}
