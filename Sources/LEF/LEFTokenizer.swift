import Foundation

/// Splits LEF text into tokens (words and punctuation).
public enum LEFTokenizer {

    public static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inComment = false
        var inQuote = false

        for ch in text {
            if inComment {
                if ch == "\n" { inComment = false }
                continue
            }

            if ch == "#" && !inQuote {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
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
                    if !current.isEmpty {
                        tokens.append(current)
                        current = ""
                    }
                    current.append(ch)
                    inQuote = true
                }
                continue
            }

            if inQuote {
                current.append(ch)
                continue
            }

            if ch == ";" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(";")
            } else if ch.isWhitespace {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
