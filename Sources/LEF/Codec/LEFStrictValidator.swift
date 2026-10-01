import Foundation

enum LEFStrictValidator {
    private struct Scope {
        var kind: String
        var endName: String?
        var spacingTableColumns: Int? = nil
        var statements: Set<String> = []
    }

    private static let supportedStatements: Set<String> = [
        "VERSION", "BUSBITCHARS", "DIVIDERCHAR", "DATABASE", "TYPE", "DIRECTION",
        "PITCH", "WIDTH", "SPACING", "OFFSET", "RESISTANCE", "CAPACITANCE",
        "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA", "ENCLOSURE",
        "SPACINGTABLE", "PARALLELRUNLENGTH", "PROPERTY", "DEFAULTCAP", "MINFEATURE",
        "MANUFACTURINGGRID", "NAMESCASESENSITIVE", "CLEARANCEMEASURE", "USEMINSPACING",
        "CLASS", "SYMMETRY", "SIZE", "ORIGIN", "FOREIGN", "SITE", "FIXEDMASK", "SOURCE",
        "EEQ", "USE", "SHAPE", "ANTENNADIFFAREA", "ANTENNAGATEAREA", "ANTENNAMODEL",
        "TAPERRULE", "LAYER", "RECT", "POLYGON", "VIA", "CUTSIZE", "CUTSPACING",
        "ROWCOL", "VIARULE", "MASK", "MINIMUMDENSITY", "MAXIMUMDENSITY",
        "DENSITYCHECKWINDOW", "DENSITYCHECKSTEP"
    ]
    private static let unsupportedStatements: Set<String> = [
        "PROPERTYDEFINITIONS", "NONDEFAULTRULE", "ANTENNAPARTIALMETALAREA",
        "ANTENNAPARTIALMETALSIDEAREA", "ANTENNAPARTIALCUTAREA", "ANTENNAMAXAREACAR",
        "ANTENNAMAXSIDEAREACAR", "ANTENNAMAXCUTCAR", "ANTENNACUMDIFFSIDEAREARATIO",
        "ANTENNACUMROUTINGAREARATIO", "ANTENNADIFFAREARATIO", "ANTENNADIFFSIDEAREARATIO",
        "ANTENNAAREARATIO", "ANTENNASIDEAREARATIO", "ANTENNAAREAFACTOR",
        "ANTENNACUMAREARATIO", "ANTENNADIFFAREAFACTOR", "MINIMUMCUT"
    ]
    private static let numericCommands: Set<String> = [
        "PITCH", "WIDTH", "SPACING", "OFFSET", "EDGECAPACITANCE", "THICKNESS",
        "MINWIDTH", "MAXWIDTH", "AREA", "ANTENNADIFFAREA", "ANTENNAGATEAREA",
        "DEFAULTCAP", "MINFEATURE", "MANUFACTURINGGRID", "PARALLELRUNLENGTH",
        "MINIMUMDENSITY", "MAXIMUMDENSITY", "DENSITYCHECKSTEP"
    ]
    private static let densityCommands: Set<String> = [
        "MINIMUMDENSITY", "MAXIMUMDENSITY", "DENSITYCHECKWINDOW", "DENSITYCHECKSTEP"
    ]
    // Match contexts implemented by the reader, so accepted statements cannot be skipped.
    private static let retainedStatementsByScope: [String: Set<String>] = [
        "LIBRARY": ["VERSION", "BUSBITCHARS", "DIVIDERCHAR", "PROPERTY"],
        "UNITS": ["DATABASE"],
        "LAYER": ["TYPE", "DIRECTION", "PITCH", "WIDTH", "SPACING", "OFFSET", "RESISTANCE",
                  "CAPACITANCE", "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA",
                  "ENCLOSURE", "SPACINGTABLE", "MINIMUMDENSITY", "MAXIMUMDENSITY",
                  "DENSITYCHECKWINDOW", "DENSITYCHECKSTEP"],
        "VIA": ["LAYER", "RECT", "POLYGON", "VIARULE", "CUTSIZE", "CUTSPACING", "ENCLOSURE",
                "ROWCOL", "RESISTANCE"],
        "SITE": ["CLASS", "SYMMETRY", "SIZE"],
        "MACRO": ["CLASS", "SIZE", "SYMMETRY", "ORIGIN", "FOREIGN", "SITE", "EEQ", "SOURCE", "FIXEDMASK", "PROPERTY"],
        "PIN": ["DIRECTION", "USE", "SHAPE", "ANTENNADIFFAREA", "ANTENNAGATEAREA", "ANTENNAMODEL", "TAPERRULE", "PROPERTY"],
        "PORT": ["CLASS", "LAYER", "RECT", "POLYGON", "VIA"],
        "OBS": ["LAYER", "RECT", "POLYGON"]
    ]

    static func validate(_ tokens: [String]) throws {
        var scopes: [Scope] = []
        var index = 0
        var libraryEnded = false
        var libraryStatements: Set<String> = []

        while index < tokens.count {
            let command = tokens[index].uppercased()
            guard command != ";" else { throw LEFError.invalidStructure("unexpected semicolon") }
            guard !libraryEnded else { throw LEFError.invalidStructure("tokens occur after END LIBRARY") }

            if command == "END" {
                if let scope = scopes.last {
                    if let expected = scope.endName {
                        let actual = index + 1 < tokens.count ? tokens[index + 1] : nil
                        guard actual?.uppercased() == expected.uppercased() else {
                            throw LEFError.mismatchedEnd(expected: expected, actual: actual)
                        }
                        index += 2
                    } else {
                        index += 1
                    }
                    scopes.removeLast()
                } else {
                    let actual = index + 1 < tokens.count ? tokens[index + 1] : nil
                    guard actual?.uppercased() == "LIBRARY" else {
                        throw LEFError.mismatchedEnd(expected: "LIBRARY", actual: actual)
                    }
                    libraryEnded = true
                    index += 2
                }
                continue
            }

            if let opening = try openingScope(command: command, tokens: tokens, index: index, scopes: scopes) {
                if command == "UNITS", !libraryStatements.insert(command).inserted {
                    throw LEFError.unsupportedCommand("repeated UNITS")
                }
                scopes.append(opening.scope)
                index = opening.nextIndex
                continue
            }

            if unsupportedStatements.contains(command) {
                throw LEFError.unsupportedCommand(command)
            }
            guard supportedStatements.contains(command) else {
                throw LEFError.unsupportedCommand(command)
            }
            let scopeKind = scopes.last?.kind ?? "LIBRARY"
            guard retainedStatementsByScope[scopeKind]?.contains(command) == true else {
                throw LEFError.unsupportedCommand("\(command) in \(scopeKind)")
            }
            if densityCommands.contains(command), scopes.last?.kind != "LAYER" {
                throw LEFError.invalidStructure("\(command) is only valid inside a LAYER")
            }

            guard let semicolon = tokens[(index + 1)...].firstIndex(of: ";") else {
                throw LEFError.missingSemicolon(command: command)
            }
            let values = Array(tokens[(index + 1)..<semicolon])
            if values.contains(where: { $0.uppercased() == "END" }) {
                throw LEFError.missingSemicolon(command: command)
            }
            let tableColumns = scopes.last?.spacingTableColumns
            try validateValues(command: command, values: values, spacingTableColumns: tableColumns, scopeKind: scopeKind)
            let repeatedGeometry = ["VIA", "PORT", "OBS"].contains(scopeKind)
                && ["LAYER", "RECT", "POLYGON", "VIA"].contains(command)
            let repeatedTableRow = command == "WIDTH" && tableColumns != nil
            if command != "PROPERTY", !repeatedGeometry, !repeatedTableRow {
                let inserted: Bool
                if let scopeIndex = scopes.indices.last {
                    inserted = scopes[scopeIndex].statements.insert(command).inserted
                } else {
                    inserted = libraryStatements.insert(command).inserted
                }
                guard inserted else { throw LEFError.unsupportedCommand("repeated \(command) in \(scopeKind)") }
            }
            if let scopeIndex = scopes.indices.last, scopes[scopeIndex].kind == "LAYER" {
                if command == "SPACINGTABLE" {
                    scopes[scopeIndex].spacingTableColumns = values.count - 1
                } else if command != "WIDTH" {
                    scopes[scopeIndex].spacingTableColumns = nil
                }
            }
            index = semicolon + 1
        }

        guard scopes.isEmpty else {
            throw LEFError.invalidStructure("unterminated \(scopes.last?.kind ?? "scope")")
        }
        guard tokens.isEmpty || libraryEnded else {
            throw LEFError.invalidStructure("END LIBRARY is missing")
        }
    }

    static func validate(_ layer: LEFLayerDef) throws {
        for (command, value) in [("PITCH", layer.pitch), ("OFFSET", layer.offset)] {
            if let value, !value.x.isFinite || !value.y.isFinite {
                throw LEFError.invalidNumber(command: command, value: "non-finite")
            }
        }
        if let minimum = layer.minimumDensity {
            try validateDensity(minimum, command: "MINIMUMDENSITY")
        }
        if let maximum = layer.maximumDensity {
            try validateDensity(maximum, command: "MAXIMUMDENSITY")
        }
        if let minimum = layer.minimumDensity,
           let maximum = layer.maximumDensity,
           minimum > maximum {
            throw LEFError.invalidStructure(
                "LAYER \(layer.name) minimum density exceeds maximum density"
            )
        }
        if let window = layer.densityCheckWindow {
            try validatePositive(window.length, command: "DENSITYCHECKWINDOW")
            try validatePositive(window.width, command: "DENSITYCHECKWINDOW")
        }
        if let step = layer.densityCheckStep {
            try validatePositive(step, command: "DENSITYCHECKSTEP")
        }
    }

    private static func openingScope(
        command: String,
        tokens: [String],
        index: Int,
        scopes: [Scope]
    ) throws -> (scope: Scope, nextIndex: Int)? {
        let parent = scopes.last?.kind
        if command == "UNITS", scopes.isEmpty {
            return (Scope(kind: "UNITS", endName: "UNITS"), index + 1)
        }
        if ["LAYER", "VIA", "SITE", "MACRO"].contains(command), scopes.isEmpty {
            guard index + 1 < tokens.count, tokens[index + 1] != ";" else {
                throw LEFError.missingValue(command: command)
            }
            let name = tokens[index + 1]
            var next = index + 2
            while next < tokens.count, tokens[next] != ";", isOpeningQualifier(tokens[next]) {
                guard command == "VIA" else {
                    throw LEFError.unsupportedCommand("\(tokens[next]) qualifier on \(command)")
                }
                next += 1
            }
            if next < tokens.count, tokens[next] == ";" { next += 1 }
            return (Scope(kind: command, endName: name), next)
        }
        if command == "PIN", parent == "MACRO" {
            guard index + 1 < tokens.count, tokens[index + 1] != ";" else {
                throw LEFError.missingValue(command: command)
            }
            return (Scope(kind: "PIN", endName: tokens[index + 1]), index + 2)
        }
        if command == "PORT", parent == "PIN" {
            return (Scope(kind: "PORT", endName: nil), index + 1)
        }
        if command == "OBS", parent == "MACRO" {
            return (Scope(kind: "OBS", endName: nil), index + 1)
        }
        return nil
    }

    private static func validateValues(
        command: String,
        values: [String],
        spacingTableColumns: Int?,
        scopeKind: String
    ) throws {
        guard !values.isEmpty || command == "FIXEDMASK" else {
            throw LEFError.missingValue(command: command)
        }
        switch command {
        case "VERSION":
            guard values.count == 1 else { throw LEFError.missingValue(command: command) }
            try requireNumbers(values, command: command)
        case "TYPE":
            let allowed = ["ROUTING", "CUT", "MASTERSLICE", "OVERLAP", "IMPLANT"]
            guard values.count == 1, allowed.contains(values[0].uppercased()) else {
                throw LEFError.invalidStructure("unsupported TYPE value \(values.first ?? "")")
            }
        case "DIRECTION":
            let allowed = scopeKind == "PIN" ? ["INPUT", "OUTPUT", "INOUT", "FEEDTHRU"] : ["HORIZONTAL", "VERTICAL"]
            guard values.count == 1, allowed.contains(values[0].uppercased()) else {
                throw LEFError.invalidStructure("unsupported DIRECTION value \(values.first ?? "")")
            }
        case "DATABASE":
            guard values.count == 2, values[0].uppercased() == "MICRONS" else {
                throw LEFError.missingValue(command: command)
            }
            try requirePositiveNumbers([values[1]], command: command)
        case "SIZE":
            guard values.count == 3, values[1].uppercased() == "BY" else {
                throw LEFError.missingValue(command: command)
            }
            try requireNumbers([values[0], values[2]], command: command)
        case "PITCH", "OFFSET":
            guard values.count == 1 || values.count == 2 else {
                throw LEFError.invalidStructure("\(command) requires one scalar or two axis values")
            }
            try requireNumbers(values, command: command)
        case "SPACINGTABLE":
            guard values.first?.uppercased() == "PARALLELRUNLENGTH", values.count >= 2 else {
                throw LEFError.unsupportedCommand("SPACINGTABLE without PARALLELRUNLENGTH")
            }
            try requireNumbers(Array(values.dropFirst()), command: command)
        case "WIDTH":
            let expectedCount = spacingTableColumns.map { $0 + 1 } ?? 1
            guard values.count == expectedCount else {
                throw LEFError.invalidStructure("WIDTH requires \(expectedCount) values in its current context")
            }
            try requireNumbers(values, command: command)
        case "SPACING", "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA",
             "ANTENNADIFFAREA", "ANTENNAGATEAREA", "MANUFACTURINGGRID":
            guard values.count == 1 else {
                throw LEFError.invalidStructure("\(command) requires one supported scalar value")
            }
            try requireNumbers(values, command: command)
        case "ORIGIN", "CUTSIZE", "CUTSPACING":
            guard values.count == 2 else { throw LEFError.missingValue(command: command) }
            try requireNumbers(values, command: command)
        case "VIA":
            guard values.count == 3 else { throw LEFError.missingValue(command: command) }
            try requireNumbers(Array(values.prefix(2)), command: command)
        case "FOREIGN":
            guard values.count == 1 || values.count == 3 else { throw LEFError.missingValue(command: command) }
            if values.count == 3 { try requireNumbers(Array(values.dropFirst()), command: command) }
        case "MASK":
            guard values.count == 1, Int(values[0]) != nil else {
                throw LEFError.invalidNumber(command: command, value: values.first ?? "")
            }
        case "RECT":
            if values.first?.uppercased() == "MASK" {
                guard values.count >= 2, let mask = Int(values[1]), mask > 0 else {
                    throw LEFError.invalidNumber(command: "RECT MASK", value: values.dropFirst().first ?? "")
                }
            }
            let coordinates = values.first?.uppercased() == "MASK" ? Array(values.dropFirst(2)) : values
            guard coordinates.count == 4 else { throw LEFError.missingValue(command: command) }
            try requireNumbers(coordinates, command: command)
        case "POLYGON":
            guard values.first?.uppercased() != "MASK" else {
                throw LEFError.unsupportedCommand("POLYGON MASK")
            }
            let coordinates = values
            guard coordinates.count >= 6, coordinates.count.isMultiple(of: 2) else {
                throw LEFError.missingValue(command: command)
            }
            try requireNumbers(coordinates, command: command)
        case "ENCLOSURE":
            guard values.count == (scopeKind == "VIA" ? 4 : 2) else { throw LEFError.missingValue(command: command) }
            try requireNumbers(values, command: command)
        case "ROWCOL":
            guard values.count == 2, values.allSatisfy({ Int($0) != nil }) else {
                throw LEFError.invalidNumber(command: command, value: values.first ?? "")
            }
        case "RESISTANCE", "CAPACITANCE":
            let prefix = command == "RESISTANCE" ? "RPERSQ" : "CPERSQDIST"
            guard (scopeKind == "VIA" && values.count == 1) ||
                  (scopeKind == "LAYER" && values.count == 2 && values[0].uppercased() == prefix),
                  let value = values.last else { throw LEFError.missingValue(command: command) }
            try requireNumbers([value], command: command)
        case "CLASS":
            let allowed: [String]
            switch scopeKind {
            case "MACRO": allowed = ["CORE", "PAD", "BLOCK", "RING", "ENDCAP", "COVER"]
            case "SITE": allowed = ["CORE", "PAD"]
            default: allowed = ["NONE", "CORE", "BUMP"]
            }
            guard values.count == 1 || (scopeKind == "MACRO" && values.count == 2),
                  allowed.contains(values[0].uppercased()) else {
                throw LEFError.invalidStructure("unrepresentable CLASS in \(scopeKind)")
            }
        case "USE", "SHAPE":
            let allowed = command == "USE" ? ["SIGNAL", "POWER", "GROUND", "CLOCK", "ANALOG"] : ["ABUTMENT", "RING", "FEEDTHRU"]
            guard values.count == 1, allowed.contains(values[0].uppercased()) else {
                throw LEFError.invalidStructure("unrepresentable \(command)")
            }
        case "SYMMETRY":
            guard values.allSatisfy({ ["X", "Y", "R90"].contains($0.uppercased()) }) else {
                throw LEFError.invalidStructure("unrepresentable SYMMETRY")
            }
        case "LAYER", "SITE", "EEQ", "SOURCE", "ANTENNAMODEL", "TAPERRULE", "VIARULE", "BUSBITCHARS", "DIVIDERCHAR":
            guard values.count == 1 else { throw LEFError.missingValue(command: command) }
        case "FIXEDMASK":
            guard values.isEmpty else { throw LEFError.invalidStructure("FIXEDMASK takes no values") }
        case "MINIMUMDENSITY", "MAXIMUMDENSITY":
            guard values.count == 1 else { throw LEFError.missingValue(command: command) }
            try requireNumbers(values, command: command)
            guard let density = Double(values[0]), (0...100).contains(density) else {
                throw LEFError.invalidNumber(command: command, value: values[0])
            }
        case "DENSITYCHECKWINDOW":
            guard values.count == 2 else { throw LEFError.missingValue(command: command) }
            try requirePositiveNumbers(values, command: command)
        case "DENSITYCHECKSTEP":
            guard values.count == 1 else { throw LEFError.missingValue(command: command) }
            try requirePositiveNumbers(values, command: command)
        default:
            if numericCommands.contains(command) {
                try requireNumbers(values, command: command)
            }
        }
    }

    private static func requireNumbers(_ values: [String], command: String) throws {
        for value in values {
            guard let number = Double(value), number.isFinite else {
                throw LEFError.invalidNumber(command: command, value: value)
            }
        }
    }

    private static func requirePositiveNumbers(_ values: [String], command: String) throws {
        try requireNumbers(values, command: command)
        for value in values {
            guard let number = Double(value), number > 0 else {
                throw LEFError.invalidNumber(command: command, value: value)
            }
        }
    }

    private static func validateDensity(_ value: Double, command: String) throws {
        guard value.isFinite, (0...100).contains(value) else {
            throw LEFError.invalidNumber(command: command, value: String(value))
        }
    }

    private static func validatePositive(_ value: Double, command: String) throws {
        guard value.isFinite, value > 0 else {
            throw LEFError.invalidNumber(command: command, value: String(value))
        }
    }

    private static func isOpeningQualifier(_ token: String) -> Bool {
        ["DEFAULT", "GENERATE"].contains(token.uppercased())
    }
}
