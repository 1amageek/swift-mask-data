import Foundation

/// Converts between GDSII excess-64 base-16 floating point and IEEE 754 Double.
///
/// GDSII Real8 format (8 bytes):
/// - Byte 0: `[Sign(1 bit)][Exponent(7 bits)]`
/// - Bytes 1-7: Mantissa (56 bits, unsigned)
///
/// Value = (-1)^sign × (mantissa / 2^56) × 16^(exponent - 64)
public enum GDSReal8 {

    /// Converts 8 GDSII bytes to an IEEE 754 Double.
    public static func toDouble(
        _ bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    ) -> Double {
        let sign: Double = (bytes.0 & 0x80) != 0 ? -1.0 : 1.0
        let exponent = Int(bytes.0 & 0x7F) - 64

        var mantissa: UInt64 = 0
        mantissa |= UInt64(bytes.1) << 48
        mantissa |= UInt64(bytes.2) << 40
        mantissa |= UInt64(bytes.3) << 32
        mantissa |= UInt64(bytes.4) << 24
        mantissa |= UInt64(bytes.5) << 16
        mantissa |= UInt64(bytes.6) << 8
        mantissa |= UInt64(bytes.7)

        if mantissa == 0 { return 0.0 }

        let fraction = Double(mantissa) / Double(UInt64(1) << 56)
        return sign * fraction * pow(16.0, Double(exponent))
    }

    /// Converts an IEEE 754 Double to 8 GDSII bytes.
    public static func fromDouble(
        _ value: Double
    ) -> (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) {
        if value == 0.0 {
            return (0, 0, 0, 0, 0, 0, 0, 0)
        }

        let signBit: UInt8 = value < 0 ? 0x80 : 0x00
        var absValue = abs(value)

        // Normalize: find exponent such that 1/16 <= fraction < 1
        // fraction = absValue / 16^exponent
        var exponent = 0
        if absValue >= 1.0 {
            while absValue >= 1.0 {
                absValue /= 16.0
                exponent += 1
            }
        } else {
            while absValue < (1.0 / 16.0) {
                absValue *= 16.0
                exponent -= 1
            }
        }
        // Now 1/16 <= absValue < 1

        let biasedExponent = exponent + 64
        guard biasedExponent >= 0, biasedExponent <= 127 else {
            // Overflow or underflow — return zero
            return (0, 0, 0, 0, 0, 0, 0, 0)
        }

        // Convert fraction to 56-bit mantissa
        let mantissa = UInt64(absValue * Double(UInt64(1) << 56) + 0.5)

        let byte0 = signBit | UInt8(biasedExponent)
        let byte1 = UInt8((mantissa >> 48) & 0xFF)
        let byte2 = UInt8((mantissa >> 40) & 0xFF)
        let byte3 = UInt8((mantissa >> 32) & 0xFF)
        let byte4 = UInt8((mantissa >> 24) & 0xFF)
        let byte5 = UInt8((mantissa >> 16) & 0xFF)
        let byte6 = UInt8((mantissa >> 8) & 0xFF)
        let byte7 = UInt8(mantissa & 0xFF)

        return (byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7)
    }
}
