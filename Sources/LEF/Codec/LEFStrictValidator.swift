import Foundation
import TechIR

enum LEFStrictValidator {
    private struct Scope {
        var kind: String
        var endName: String?
        var statements: Set<String> = []
    }

    private static let supportedStatements: Set<String> = Set([
        "VERSION", "BUSBITCHARS", "DIVIDERCHAR", "DATABASE", "TYPE", "DIRECTION",
        "PITCH", "WIDTH", "SPACING", "OFFSET", "RESISTANCE", "CAPACITANCE",
        "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA", "MINENCLOSEDAREA", "ENCLOSURE",
        "SPACINGTABLE", "PARALLELRUNLENGTH", "PROPERTY", "DEFAULTCAP", "MINFEATURE",
        "MANUFACTURINGGRID", "NAMESCASESENSITIVE", "CLEARANCEMEASURE", "USEMINSPACING",
        "CLASS", "SYMMETRY", "SIZE", "ORIGIN", "FOREIGN", "SITE", "FIXEDMASK", "SOURCE",
        "EEQ", "USE", "SHAPE", "ANTENNADIFFAREA", "ANTENNAGATEAREA", "ANTENNAMODEL",
        "TAPERRULE", "LAYER", "RECT", "POLYGON", "PATH", "VIA", "CUTSIZE", "CUTSPACING",
        "ROWCOL", "VIARULE", "MASK", "MINIMUMDENSITY", "MAXIMUMDENSITY",
        "DENSITYCHECKWINDOW", "DENSITYCHECKSTEP"
    ]).union(LEFUnitStatement.all.map(\.command)).union(LEFAntennaCodec.commands).union(LEFCurrentDensityCodec.commands)
    // FIXME(INCOMPLETE_IMPLEMENTATION): Other layer antenna laws are not retained.
    // LEFLibraryReader refuses these commands during preflight; typed source/writer/
    // projection coverage and downstream rule admission are required before support.
    private static let unsupportedStatements: Set<String> = [
        "NONDEFAULTRULE", "ANTENNAPARTIALMETALAREA",
        "ANTENNAPARTIALMETALSIDEAREA", "ANTENNAPARTIALCUTAREA", "ANTENNAMAXAREACAR",
        "ANTENNAMAXSIDEAREACAR", "ANTENNAMAXCUTCAR", "ANTENNACUMDIFFSIDEAREARATIO",
        "ANTENNACUMROUTINGAREARATIO",
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
        "LIBRARY": ["VERSION", "BUSBITCHARS", "DIVIDERCHAR", "PROPERTY", "MANUFACTURINGGRID", "USEMINSPACING"],
        "UNITS": Set(["DATABASE"]).union(LEFUnitStatement.all.map(\.command)),
        "LAYER": ["TYPE", "DIRECTION", "PITCH", "WIDTH", "SPACING", "OFFSET", "RESISTANCE",
                  "CAPACITANCE", "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA", "MINENCLOSEDAREA",
                  "ENCLOSURE", "SPACINGTABLE", "MINIMUMDENSITY", "MAXIMUMDENSITY",
                  "DENSITYCHECKWINDOW", "DENSITYCHECKSTEP", "PROPERTY", "ANTENNAMODEL",
                  "ANTENNADIFFAREARATIO", "ANTENNADIFFSIDEAREARATIO", "DCCURRENTDENSITY", "ACCURRENTDENSITY"],
        "VIA": ["LAYER", "RECT", "POLYGON", "VIARULE", "CUTSIZE", "CUTSPACING", "ENCLOSURE",
                "ROWCOL", "RESISTANCE"],
        "SITE": ["CLASS", "SYMMETRY", "SIZE"],
        "MACRO": ["CLASS", "SIZE", "SYMMETRY", "ORIGIN", "FOREIGN", "SITE", "EEQ", "SOURCE", "FIXEDMASK", "PROPERTY"],
        "PIN": ["DIRECTION", "USE", "SHAPE", "ANTENNADIFFAREA", "ANTENNAGATEAREA", "ANTENNAMODEL", "TAPERRULE", "PROPERTY"],
        "PORT": ["CLASS", "LAYER", "WIDTH", "RECT", "POLYGON", "PATH", "VIA"],
        "OBS": ["LAYER", "WIDTH", "RECT", "POLYGON", "PATH"]
    ]

    static func validate(_ tokens: [String]) throws {
        var scopes: [Scope] = []
        var index = 0
        var sawLayer = false
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

            if command == "VIARULE", scopes.isEmpty {
                index = try LEFViaGenerationCodec.read(tokens, from: index).next
                continue
            }
            if command == "PROPERTYDEFINITIONS" {
                guard scopes.isEmpty, libraryStatements.insert(command).inserted else {
                    throw LEFError.invalidStructure("PROPERTYDEFINITIONS requires one library block")
                }
                index = try LEFPropertyDefinitionCodec.read(tokens, from: index + 1).next
                continue
            }

            if let opening = try openingScope(command: command, tokens: tokens, index: index, scopes: scopes) {
                if command == "LAYER", scopes.isEmpty { sawLayer = true }
                if command == "UNITS", sawLayer { throw LEFError.invalidStructure("UNITS must precede LAYER declarations") }
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
            if scopeKind == "LAYER", LEFCurrentDensityCodec.commands.contains(command) {
                let parsed = try LEFCurrentDensityCodec.read(tokens, from: index)
                guard let scopeIndex = scopes.indices.last,
                      scopes[scopeIndex].statements.insert("CURRENTDENSITY:" + parsed.kind.rawValue).inserted else {
                    throw LEFError.unsupportedCommand("repeated \(command) \(parsed.kind.rawValue) in LAYER")
                }
                index = parsed.next
                continue
            }
            if scopeKind == "LAYER", command == "MINENCLOSEDAREA" {
                let parsed = try LEFMinimumEnclosedAreaCodec.read(tokens, from: index)
                guard let scopeIndex = scopes.indices.last,
                      scopes[scopeIndex].statements.insert(command).inserted else {
                    throw LEFError.unsupportedCommand("repeated MINENCLOSEDAREA in LAYER")
                }
                index = parsed.next
                continue
            }
            if scopeKind == "LAYER", command == "ENCLOSURE" {
                index = try LEFLayerEnclosureCodec.read(tokens, from: index).next
                continue
            }
            if scopeKind == "LAYER", LEFAntennaCodec.commands.contains(command) {
                index = try LEFAntennaCodec.read(tokens, from: index).next
                continue
            }
            if densityCommands.contains(command), scopes.last?.kind != "LAYER" {
                throw LEFError.invalidStructure("\(command) is only valid inside a LAYER")
            }

            if command == "SPACINGTABLE", let scopeIndex = scopes.indices.last {
                guard scopes[scopeIndex].statements.insert(command).inserted else {
                    throw LEFError.unsupportedCommand("repeated SPACINGTABLE in LAYER")
                }
                index = try LEFSpacingTableValidation.endIndex(in: tokens, from: index + 1)
                continue
            }

            guard let semicolon = tokens[(index + 1)...].firstIndex(of: ";") else {
                throw LEFError.missingSemicolon(command: command)
            }
            let values = Array(tokens[(index + 1)..<semicolon])
            if values.contains(where: { $0.uppercased() == "END" }) {
                throw LEFError.missingSemicolon(command: command)
            }
            try validateValues(command: command, values: values, scopeKind: scopeKind)
            let repeatedGeometry = ["VIA", "PORT", "OBS"].contains(scopeKind)
                && ["LAYER", "WIDTH", "RECT", "POLYGON", "PATH", "VIA"].contains(command)
            if command != "PROPERTY", !repeatedGeometry {
                let inserted: Bool
                if let scopeIndex = scopes.indices.last {
                    inserted = scopes[scopeIndex].statements.insert(command).inserted
                } else {
                    inserted = libraryStatements.insert(command).inserted
                }
                guard inserted else { throw LEFError.unsupportedCommand("repeated \(command) in \(scopeKind)") }
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

    static func validate(_ declarations: IRTechUnitDeclarations) throws {
        for statement in LEFUnitStatement.all {
            if let value = declarations[keyPath: statement.keyPath], !value.isFinite || value <= 0 {
                throw LEFError.invalidNumber(command: statement.command, value: String(value))
            }
        }
    }

    static func validate(_ layer: LEFLayerDef) throws {
        try LEFAntennaCodec.validate(layer.antennaStatements, layerType: layer.type)
        try LEFLayerEnclosureCodec.validate(layer.enclosures, layerType: layer.type)
        try LEFLayerResistanceCodec.validate(layer)
        try LEFCurrentDensityCodec.validate(layer)
        try LEFMinimumEnclosedAreaCodec.validate(layer)
        if let table = layer.spacingTable {
            guard layer.spacing == nil else {
                throw LEFError.invalidStructure("Unqualified SPACING cannot coexist with SPACINGTABLE")
            }
            try LEFSpacingTableValidation.validate(table)
        }
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
        scopeKind: String
    ) throws {
        guard !values.isEmpty || command == "FIXEDMASK" else {
            throw LEFError.missingValue(command: command)
        }
        if scopeKind == "UNITS", command != "DATABASE" {
            guard let statement = LEFUnitStatement.all.first(where: { $0.command == command }),
                  values.count == 2, values[0].uppercased() == statement.unit else {
                throw LEFError.invalidStructure("Invalid unit name or arity for \(command)")
            }
            try requirePositiveNumbers([values[1]], command: command)
            return
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
        case "USEMINSPACING":
            guard values.count == 2, values[0].uppercased() == "OBS", ["ON", "OFF"].contains(values[1].uppercased()) else {
                throw LEFError.invalidStructure("USEMINSPACING requires OBS ON or OBS OFF")
            }
        case "DATABASE":
            guard values.count == 2, values[0].uppercased() == "MICRONS" else {
                throw LEFError.missingValue(command: command)
            }
            try requirePositiveNumbers([values[1]], command: command)
            guard let database = Double(values[1]) else { throw LEFError.invalidNumber(command: command, value: values[1]) }
            try LEFUnitStatement.validateDatabase(database)
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
        case "WIDTH":
            guard values.count == 1 else {
                throw LEFError.invalidStructure("WIDTH requires one value outside a spacing table")
            }
            try requireNumbers(values, command: command)
        case "SPACING", "EDGECAPACITANCE", "THICKNESS", "MINWIDTH", "MAXWIDTH", "AREA", "MINENCLOSEDAREA",
             "ANTENNADIFFAREA", "ANTENNAGATEAREA", "MANUFACTURINGGRID":
            guard values.count == 1 else {
                throw LEFError.invalidStructure("\(command) requires one supported scalar value")
            }
            try requireNumbers(values, command: command)
            if command == "MANUFACTURINGGRID" {
                try requirePositiveNumbers(values, command: command)
            }
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
        case "PATH":
            guard values.count >= 2, values.count.isMultiple(of: 2) else {
                throw LEFError.missingValue(command: command)
            }
            try requireNumbers(values, command: command)
        case "ENCLOSURE":
            guard values.count == (scopeKind == "VIA" ? 4 : 2) else { throw LEFError.missingValue(command: command) }
            try requireNumbers(values, command: command)
        case "ROWCOL":
            guard values.count == 2, values.allSatisfy({ Int($0) != nil }) else {
                throw LEFError.invalidNumber(command: command, value: values.first ?? "")
            }
        case "RESISTANCE", "CAPACITANCE":
            if command == "RESISTANCE", scopeKind == "LAYER" {
                try LEFLayerResistanceCodec.validateValues(values)
                return
            }
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
