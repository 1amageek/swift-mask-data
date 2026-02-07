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

    public static func read(_ text: String) -> [DXFGroup] {
        let lines = text.components(separatedBy: .newlines)
        var groups: [DXFGroup] = []
        var i = 0

        while i + 1 < lines.count {
            let codeLine = lines[i].trimmingCharacters(in: .whitespaces)
            let valueLine = lines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = Int(codeLine) {
                groups.append(DXFGroup(code: code, value: valueLine))
            }
            i += 2
        }

        return groups
    }
}
