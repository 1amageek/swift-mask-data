import Foundation

/// A DXF group code + value pair.
public struct DXFGroup: Sendable {
    public var code: Int
    public var value: String

    public init(code: Int, value: String) {
        self.code = code
        self.value = value
    }
}

/// Reads DXF text into group code/value pairs.
public enum DXFGroupReader {
    public static func read(_ text: String) throws -> [DXFGroup] {
        guard !text.isEmpty else { return [] }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }
        guard lines.count.isMultiple(of: 2) else {
            throw DXFError.incompleteGroup(line: lines.count)
        }

        var groups: [DXFGroup] = []
        groups.reserveCapacity(lines.count / 2)
        for index in stride(from: 0, to: lines.count, by: 2) {
            let codeText = lines[index].trimmingCharacters(in: .whitespaces)
            guard let code = Int(codeText), (0...1071).contains(code) else {
                throw DXFError.invalidGroupCode(line: index + 1, value: codeText)
            }
            groups.append(DXFGroup(
                code: code,
                value: lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return groups
    }
}
