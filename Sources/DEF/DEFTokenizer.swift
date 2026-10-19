import Foundation

/// Splits DEF text into tokens.
public enum DEFTokenizer {

    public static func tokenize(_ text: String) -> [String] {
        tokenize(text, checkingCancellation: {})
    }

    static func tokenize(_ text: String, checkingCancellation: () throws -> Void) rethrows -> [String] {
        try checkingCancellation()
        var tokens: [String] = []
        var current = ""
        var inComment = false
        var inQuote = false
        var traversed = 0

        for ch in text {
            if traversed == 4096 {
                try checkingCancellation()
                traversed = 0
            }
            traversed += 1
            if inComment {
                if ch == "\n" { inComment = false }
                continue
            }

            if ch == "#" && !inQuote {
                if !current.isEmpty { tokens.append(current); current = "" }
                inComment = true
                continue
            }

            if ch == "\"" {
                if inQuote {
                    current.append(ch)
                    tokens.append(current)
                    current = ""
                    inQuote = false
                } else {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    current.append(ch)
                    inQuote = true
                }
                continue
            }

            if inQuote { current.append(ch); continue }

            if ch == ";" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(";")
            } else if ch == "(" || ch == ")" {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        try checkingCancellation()
        return tokens
    }
}
