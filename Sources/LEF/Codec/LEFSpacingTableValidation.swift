import Foundation

/// Validates the standard table scope and retained matrix without selecting process rules.
enum LEFSpacingTableValidation {
    static func endIndex(in tokens: [String], from start: Int) throws -> Int {
        guard start < tokens.count, tokens[start].uppercased() == "PARALLELRUNLENGTH" else {
            throw LEFError.unsupportedCommand("SPACINGTABLE without PARALLELRUNLENGTH")
        }
        var index = start + 1
        var columns = 0
        while index < tokens.count, tokens[index] != ";", tokens[index].uppercased() != "WIDTH" {
            try number(tokens[index])
            columns += 1
            index += 1
        }
        guard columns > 0 else { throw LEFError.missingValue(command: "PARALLELRUNLENGTH") }
        // Retain compatibility with the reader's historical header/row terminators.
        let legacyHeader = index < tokens.count && tokens[index] == ";"
        if legacyHeader { index += 1 }
        guard index < tokens.count, tokens[index].uppercased() == "WIDTH" else {
            throw LEFError.invalidStructure("SPACINGTABLE requires WIDTH rows")
        }
        while index < tokens.count, tokens[index].uppercased() == "WIDTH" {
            index += 1
            for _ in 0...columns {
                guard index < tokens.count, tokens[index] != ";", tokens[index].uppercased() != "WIDTH" else {
                    throw LEFError.invalidStructure("SPACINGTABLE row has incomplete width or spacing values")
                }
                try number(tokens[index])
                index += 1
            }
            guard index < tokens.count else { throw LEFError.missingSemicolon(command: "SPACINGTABLE") }
            if tokens[index] == ";" {
                index += 1
                if legacyHeader, index < tokens.count, tokens[index].uppercased() == "WIDTH" { continue }
                return index
            }
            guard tokens[index].uppercased() == "WIDTH" else {
                throw LEFError.invalidStructure("SPACINGTABLE row must end at WIDTH or semicolon")
            }
        }
        throw LEFError.missingSemicolon(command: "SPACINGTABLE")
    }

    static func validate(_ table: LEFSpacingTable) throws {
        guard !table.parallelRunLengths.isEmpty, !table.widthEntries.isEmpty else {
            throw LEFError.invalidStructure("SPACINGTABLE requires nonempty length and width axes")
        }
        var previousLength: Double?
        for length in table.parallelRunLengths {
            try axis(length, previous: previousLength, name: "parallel run length", signed: true)
            previousLength = length
        }
        var previousWidth: Double?
        for row in table.widthEntries.indices {
            let entry = table.widthEntries[row]
            try axis(entry.width, previous: previousWidth, name: "width")
            previousWidth = entry.width
            guard entry.spacings.count == table.parallelRunLengths.count else {
                throw LEFError.invalidStructure("SPACINGTABLE requires one spacing per length column")
            }
            var previousSpacing: Double?
            for column in entry.spacings.indices {
                let spacing = entry.spacings[column]
                guard spacing.isFinite, spacing >= 0 else {
                    throw LEFError.invalidNumber(command: "SPACINGTABLE", value: String(spacing))
                }
                if let previousSpacing, spacing < previousSpacing {
                    throw LEFError.invalidStructure("SPACINGTABLE spacing decreases with parallel run length")
                }
                if row > 0, spacing < table.widthEntries[row - 1].spacings[column] {
                    throw LEFError.invalidStructure("SPACINGTABLE spacing decreases with width")
                }
                previousSpacing = spacing
            }
        }
    }

    private static func axis(_ value: Double, previous: Double?, name: String, signed: Bool = false) throws {
        guard value.isFinite, signed || value >= 0 else {
            throw LEFError.invalidNumber(command: "SPACINGTABLE", value: String(value))
        }
        if let previous, value <= previous {
            throw LEFError.invalidStructure("SPACINGTABLE \(name) axis must be strictly increasing")
        }
    }

    private static func number(_ token: String) throws {
        guard let value = Double(token), value.isFinite else {
            throw LEFError.invalidNumber(command: "SPACINGTABLE", value: token)
        }
    }
}
