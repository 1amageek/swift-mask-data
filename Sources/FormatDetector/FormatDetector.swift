import Foundation

/// Detects layout file format from raw data by inspecting magic bytes and content patterns.
public enum FormatDetector {

    /// Detect the format of the given data.
    public static func detect(_ data: Data) -> LayoutFormat {
        guard data.count >= 4 else { return .unknown }

        // OASIS: starts with "%SEMI-OASIS\r\n"
        let oasisMagic = Data("%SEMI-OASIS\r\n".utf8)
        if data.count >= oasisMagic.count && data.prefix(oasisMagic.count) == oasisMagic {
            return .oasis
        }

        // GDSII: bytes [2..3] == 0x00 0x02 (HEADER record type)
        // First 2 bytes are record length, next 2 are record type 0x0002
        if data.count >= 4 && data[2] == 0x00 && data[3] == 0x02 {
            return .gdsii
        }

        // Text-based formats: try to interpret as UTF-8
        guard let text = textPrefix(data, maxBytes: 4096) else {
            return .unknown
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // DXF: starts with group code pattern "  0\nSECTION" or "0\nSECTION"
        if isDXF(trimmed) {
            return .dxf
        }

        // DEF: contains "VERSION" and "DESIGN" in the header area
        if isDEF(trimmed) {
            return .def
        }

        // LEF: contains "VERSION" and ("LAYER" or "MACRO") in the header area
        if isLEF(trimmed) {
            return .lef
        }

        // CIF: first non-whitespace non-comment character is a CIF command
        if isCIF(trimmed) {
            return .cif
        }

        return .unknown
    }

    // MARK: - Private

    private static func textPrefix(_ data: Data, maxBytes: Int) -> String? {
        let prefix = data.prefix(maxBytes)
        return String(data: prefix, encoding: .utf8)
    }

    private static func isDXF(_ text: String) -> Bool {
        // DXF files start with group code 0 followed by SECTION
        let lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return false }
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let second = lines[1].trimmingCharacters(in: .whitespaces)
        return first == "0" && second == "SECTION"
    }

    private static func isDEF(_ text: String) -> Bool {
        let upper = text.uppercased()
        return containsWord(upper, "VERSION") && containsWord(upper, "DESIGN")
    }

    private static func isLEF(_ text: String) -> Bool {
        let upper = text.uppercased()
        guard containsWord(upper, "VERSION") else { return false }
        return containsWord(upper, "MACRO") || containsWord(upper, "LAYER")
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex
                || !text[text.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == text.endIndex
                || !text[range.upperBound].isLetter
            if beforeOK && afterOK { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func isCIF(_ text: String) -> Bool {
        // Skip CIF comments (parenthesized)
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch.isWhitespace {
                index = text.index(after: index)
                continue
            }
            if ch == "(" {
                // Skip comment
                var depth = 1
                index = text.index(after: index)
                while index < text.endIndex && depth > 0 {
                    if text[index] == "(" { depth += 1 }
                    if text[index] == ")" { depth -= 1 }
                    index = text.index(after: index)
                }
                continue
            }
            // First non-whitespace, non-comment character
            // CIF commands: D (DS/DF), B, W, P, L, C, E, R, etc.
            return "DBWPLCERS0123456789".contains(ch)
        }
        return false
    }
}
