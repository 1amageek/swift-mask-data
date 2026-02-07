import Foundation

/// Splits CIF text into semicolon-delimited command strings.
public enum CIFTokenizer {

    /// Tokenize CIF text into command strings (without trailing semicolons).
    /// Comments (parenthesized text) are stripped.
    public static func tokenize(_ text: String) -> [String] {
        let stripped = stripComments(text)
        return stripped
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stripComments(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var depth = 0
        for ch in text {
            if ch == "(" {
                depth += 1
            } else if ch == ")" {
                depth = max(0, depth - 1)
            } else if depth == 0 {
                result.append(ch)
            }
        }
        return result
    }
}
