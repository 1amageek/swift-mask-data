import Foundation

/// Splits CIF text into validated semicolon-delimited command strings.
public enum CIFTokenizer {
    /// Tokenizes CIF text into command strings without trailing semicolons.
    /// A terminal `E` command may omit its semicolon, as permitted by common CIF files.
    public static func tokenize(_ text: String) throws -> [String] {
        var commands: [String] = []
        var current = ""
        var commentDepth = 0

        for character in text {
            if character == "(" {
                commentDepth += 1
                continue
            }
            if character == ")" {
                guard commentDepth > 0 else {
                    throw CIFError.invalidCommand(command: String(character), reason: "unmatched closing comment delimiter")
                }
                commentDepth -= 1
                continue
            }
            guard commentDepth == 0 else { continue }

            if character == ";" {
                let command = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !command.isEmpty {
                    commands.append(command)
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }

        guard commentDepth == 0 else { throw CIFError.unterminatedComment }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            guard trailing == "E" else { throw CIFError.unterminatedCommand(trailing) }
            commands.append(trailing)
        }
        return commands
    }
}
