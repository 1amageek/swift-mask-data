import Foundation
import TechIR

/// Parses LEF text data into a LEFDocument.
public enum LEFLibraryReader {

    public static func read(_ data: Data) throws -> LEFDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw LEFError.invalidEncoding
        }

        let tokens = try LEFTokenizer.tokenize(text)
        try LEFStrictValidator.validate(tokens)
        var doc = LEFDocument(dbuPerMicron: 100, hasDatabaseUnitsDeclaration: false)
        var i = 0

        while i < tokens.count {
            switch tokens[i].uppercased() {
            case "VERSION":
                i += 1
                if i < tokens.count && tokens[i] != ";" {
                    doc.version = tokens[i]
                    i += 1
                }
                i = skipSemicolon(tokens, i)

            case "BUSBITCHARS":
                i += 1
                if i < tokens.count && tokens[i] != ";" {
                    doc.busbitChars = unquote(tokens[i])
                    i += 1
                }
                i = skipSemicolon(tokens, i)

            case "DIVIDERCHAR":
                i += 1
                if i < tokens.count && tokens[i] != ";" {
                    doc.dividerChar = unquote(tokens[i])
                    i += 1
                }
                i = skipSemicolon(tokens, i)

            case "UNITS":
                i += 1
                i = try parseUnits(tokens, from: i, doc: &doc)

            case "LAYER":
                i += 1
                let (layer, next) = try parseLayer(tokens, from: i, definitions: doc.propertyDefinitions)
                if let layer = layer {
                    try LEFStrictValidator.validate(layer)
                    doc.layers.append(layer)
                }
                i = next

            case "VIA":
                i += 1
                let (via, next) = parseVia(tokens, from: i)
                if let via = via { doc.vias.append(via) }
                i = next

            case "VIARULE":
                let parsed = try LEFViaGenerationCodec.read(tokens, from: i)
                doc.viaGenerationRules.append(parsed.rule)
                i = parsed.next

            case "SITE":
                i += 1
                let (site, next) = parseSite(tokens, from: i)
                if let site = site { doc.sites.append(site) }
                i = next

            case "MACRO":
                i += 1
                let (macro, next) = try parseMacro(tokens, from: i)
                if let macro = macro { doc.macros.append(macro) }
                i = next

            case "PROPERTY":
                i += 1
                let (prop, next) = parseProperty(tokens, from: i)
                if let prop = prop { doc.properties.append(prop) }
                i = next

            case "MANUFACTURINGGRID":
                doc.manufacturingGrid = Double(tokens[i + 1])
                i = skipSemicolon(tokens, i + 2)

            case "USEMINSPACING":
                guard i + 2 < tokens.count, ["ON", "OFF"].contains(tokens[i + 2].uppercased()) else {
                    throw LEFError.invalidStructure("Invalid USEMINSPACING OBS policy")
                }
                doc.obstructionSpacingUsesMinimumWidth = tokens[i + 2].uppercased() == "ON"
                i = skipSemicolon(tokens, i + 3)

            case "PROPERTYDEFINITIONS":
                let parsed = try LEFPropertyDefinitionCodec.read(tokens, from: i + 1)
                doc.propertyDefinitions = parsed.definitions
                i = parsed.next

            case "NONDEFAULTRULE":
                i += 1
                i = skipToEnd(tokens, from: i)

            case "SPACING":
                i += 1
                i = skipToEndKeyword(tokens, from: i, keyword: "SPACING")

            case "END":
                i += 1
                if i < tokens.count { i += 1 }
                break

            default:
                i += 1
            }
        }

        try LEFViaGenerationCodec.validate(doc.viaGenerationRules, layers: doc.layers)
        return doc
    }

    // MARK: - UNITS

    private static func parseUnits(_ tokens: [String], from start: Int, doc: inout LEFDocument) throws -> Int {
        var i = start
        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "UNITS" { i += 1 }
                return i
            }
            guard i + 2 < tokens.count, let value = Double(tokens[i + 2]) else {
                throw LEFError.missingValue(command: upper)
            }
            if upper == "DATABASE" {
                doc.dbuPerMicron = value
                doc.hasDatabaseUnitsDeclaration = true
            }
            else if let statement = LEFUnitStatement.all.first(where: { $0.command == upper }) {
                doc.unitDeclarations[keyPath: statement.keyPath] = value
            } else { throw LEFError.unsupportedCommand(upper) }
            i = skipSemicolon(tokens, i + 3)
        }
        throw LEFError.invalidStructure("unterminated UNITS")
    }

    // MARK: - LAYER

    private static func parseLayer(_ tokens: [String], from start: Int, definitions: [IRTechPropertyDefinition]) throws -> (LEFLayerDef?, Int) {
        guard start < tokens.count else { return (nil, start) }
        let name = tokens[start]
        var i = start + 1
        var type: LEFLayerDef.LayerType = .routing
        var direction: LEFLayerDef.Direction?
        var pitch: IRTechAxisValue?
        var width: Double?
        var spacing: Double?
        var offset: IRTechAxisValue?
        var resistance: Double?
        var cutResistanceOhms: Double?
        var currentDensityStatements: [(kind: IRTechCurrentDensityLimit.Kind, value: Double)] = []
        var capacitance: Double?
        var edgeCapacitance: Double?
        var thickness: Double?
        var minwidth: Double?
        var maxwidth: Double?
        var area: Double?
        var minimumEnclosedAreas: [Double] = []
        var enclosures: [IRTechLayerEnclosure] = []
        var spacingTable: LEFSpacingTable?
        var minimumDensity: Double?
        var maximumDensity: Double?
        var densityCheckWindow: LEFLayerDef.DensityCheckWindow?
        var densityCheckStep: Double?
        var properties: [IRTechPropertyAssignment] = []
        var antennaStatements: [IRTechAntennaStatement] = []

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count { i += 1 }
                return (LEFLayerDef(name: name, type: type, direction: direction,
                                    pitch: pitch, width: width, spacing: spacing,
                                    offset: offset, resistance: resistance,
                                    capacitance: capacitance, edgeCapacitance: edgeCapacitance,
                                    thickness: thickness, minwidth: minwidth,
                                    maxwidth: maxwidth, area: area,
                                    spacingTable: spacingTable,
                                    minimumDensity: minimumDensity,
                                    maximumDensity: maximumDensity,
                                    densityCheckWindow: densityCheckWindow,
                                    densityCheckStep: densityCheckStep, properties: properties,
                                    subtype: try LEFLayerPropertyCodec.subtype(properties, type: type),
                                    antennaStatements: antennaStatements, enclosures: enclosures,
                                    cutResistanceOhms: cutResistanceOhms,
                                    currentDensityLimits: try currentDensityStatements.map {
                                        try LEFCurrentDensityCodec.makeLimit(kind: $0.kind, value: $0.value, layerType: type)
                                    }, minimumEnclosedAreas: minimumEnclosedAreas), i)
            }

            if LEFCurrentDensityCodec.commands.contains(upper) {
                let parsed = try LEFCurrentDensityCodec.read(tokens, from: i)
                currentDensityStatements.append((parsed.kind, parsed.value))
                i = parsed.next
                continue
            }

            if LEFAntennaCodec.commands.contains(upper) {
                let parsed = try LEFAntennaCodec.read(tokens, from: i)
                antennaStatements.append(parsed.statement)
                i = parsed.next
                continue
            }

            switch upper {
            case "TYPE":
                i += 1
                if i < tokens.count {
                    type = LEFLayerDef.LayerType(rawValue: tokens[i].uppercased()) ?? .routing
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "DIRECTION":
                i += 1
                if i < tokens.count {
                    direction = LEFLayerDef.Direction(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "PITCH":
                i += 1
                let first = try validatedDouble(tokens[i], command: upper)
                i += 1
                if tokens[i] != ";" {
                    pitch = .xy(x: first, y: try validatedDouble(tokens[i], command: upper))
                    i += 1
                } else {
                    pitch = .scalar(first)
                }
                i = skipSemicolon(tokens, i)
            case "WIDTH":
                i += 1
                if i < tokens.count { width = Double(tokens[i]); i += 1 }
                i = skipSemicolon(tokens, i)
            case "SPACING":
                i += 1
                if i < tokens.count { spacing = Double(tokens[i]); i += 1 }
                i = skipToSemicolon(tokens, i)
                i = skipSemicolon(tokens, i)
            case "OFFSET":
                i += 1
                let first = try validatedDouble(tokens[i], command: upper)
                i += 1
                if tokens[i] != ";" {
                    offset = .xy(x: first, y: try validatedDouble(tokens[i], command: upper))
                    i += 1
                } else {
                    offset = .scalar(first)
                }
                i = skipSemicolon(tokens, i)
            case "RESISTANCE":
                i += 1
                if tokens[i].uppercased() == "RPERSQ" {
                    resistance = try validatedDouble(tokens[i + 1], command: upper)
                    i += 2
                } else {
                    cutResistanceOhms = try validatedDouble(tokens[i], command: upper)
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "CAPACITANCE":
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "CPERSQDIST" {
                    i += 1
                    if i < tokens.count, let val = Double(tokens[i]) {
                        capacitance = val
                        i += 1
                    }
                }
                i = skipSemicolon(tokens, i)
            case "EDGECAPACITANCE":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    edgeCapacitance = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "THICKNESS":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    thickness = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "MINWIDTH":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    minwidth = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "MAXWIDTH":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    maxwidth = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "AREA":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    area = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "MINENCLOSEDAREA":
                let parsed = try LEFMinimumEnclosedAreaCodec.read(tokens, from: i)
                minimumEnclosedAreas.append(parsed.area)
                i = parsed.next
            case "ENCLOSURE":
                let parsed = try LEFLayerEnclosureCodec.read(tokens, from: i)
                enclosures.append(parsed.enclosure)
                i = parsed.next
            case "SPACINGTABLE":
                i += 1
                let (tbl, next) = parseSpacingTable(tokens, from: i)
                spacingTable = tbl
                i = next
            case "MINIMUMDENSITY":
                i += 1
                minimumDensity = try validatedDouble(tokens[i], command: upper)
                i = skipSemicolon(tokens, i + 1)
            case "MAXIMUMDENSITY":
                i += 1
                maximumDensity = try validatedDouble(tokens[i], command: upper)
                i = skipSemicolon(tokens, i + 1)
            case "DENSITYCHECKWINDOW":
                i += 1
                densityCheckWindow = LEFLayerDef.DensityCheckWindow(
                    length: try validatedDouble(tokens[i], command: upper),
                    width: try validatedDouble(tokens[i + 1], command: upper)
                )
                i = skipSemicolon(tokens, i + 2)
            case "DENSITYCHECKSTEP":
                i += 1
                densityCheckStep = try validatedDouble(tokens[i], command: upper)
                i = skipSemicolon(tokens, i + 1)
            case "PROPERTY":
                let parsed = try LEFLayerPropertyCodec.read(tokens, from: i + 1, definitions: definitions)
                properties.append(contentsOf: parsed.properties)
                try LEFLayerPropertyCodec.validate(properties, definitions: definitions)
                i = parsed.next
            // FIXME(INCOMPLETE_IMPLEMENTATION): Other layer antenna laws and minimum-cut
            // rules lack retained schemas; production preflight refuses them. Source,
            // writer and projection validation must exist before these branches are admitted.
            case "ANTENNACUMDIFFSIDEAREARATIO", "ANTENNACUMROUTINGAREARATIO", "ANTENNAAREARATIO",
                 "ANTENNASIDEAREARATIO", "ANTENNAAREAFACTOR", "ANTENNACUMAREARATIO",
                 "ANTENNADIFFAREAFACTOR", "MINIMUMCUT":
                throw LEFError.unsupportedCommand(upper)
            default:
                i += 1
            }
        }

        return (LEFLayerDef(name: name, type: type, direction: direction,
                            pitch: pitch, width: width, spacing: spacing,
                            offset: offset, resistance: resistance,
                            capacitance: capacitance, edgeCapacitance: edgeCapacitance,
                            thickness: thickness, minwidth: minwidth,
                            maxwidth: maxwidth, area: area,
                            spacingTable: spacingTable,
                            minimumDensity: minimumDensity,
                            maximumDensity: maximumDensity,
                            densityCheckWindow: densityCheckWindow,
                            densityCheckStep: densityCheckStep, properties: properties,
                            subtype: try LEFLayerPropertyCodec.subtype(properties, type: type),
                            antennaStatements: antennaStatements, enclosures: enclosures,
                            cutResistanceOhms: cutResistanceOhms,
                            currentDensityLimits: try currentDensityStatements.map {
                                try LEFCurrentDensityCodec.makeLimit(kind: $0.kind, value: $0.value, layerType: type)
                            }, minimumEnclosedAreas: minimumEnclosedAreas), i)
    }

    private static func validatedDouble(_ token: String, command: String) throws -> Double {
        guard let value = Double(token), value.isFinite else {
            throw LEFError.invalidNumber(command: command, value: token)
        }
        return value
    }

    // MARK: - SPACINGTABLE

    private static func parseSpacingTable(_ tokens: [String], from start: Int) -> (LEFSpacingTable?, Int) {
        var i = start
        guard i < tokens.count && tokens[i].uppercased() == "PARALLELRUNLENGTH" else {
            i = skipToSemicolon(tokens, i)
            i = skipSemicolon(tokens, i)
            return (nil, i)
        }
        i += 1

        var prl: [Double] = []
        while i < tokens.count && tokens[i] != ";" {
            if tokens[i].uppercased() == "WIDTH" { break }
            if let val = Double(tokens[i]) {
                prl.append(val)
            }
            i += 1
        }
        let legacyHeader = i < tokens.count && tokens[i] == ";"
        if legacyHeader { i += 1 }

        var entries: [LEFSpacingTable.WidthEntry] = []
        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "WIDTH" {
                i += 1
                guard i < tokens.count, let w = Double(tokens[i]) else { break }
                i += 1
                var spacings: [Double] = []
                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i].uppercased() == "WIDTH" || tokens[i].uppercased() == "END" { break }
                    if let val = Double(tokens[i]) {
                        spacings.append(val)
                    }
                    i += 1
                }
                let tableEnded = i < tokens.count && tokens[i] == ";" && !legacyHeader
                i = skipSemicolon(tokens, i)
                entries.append(LEFSpacingTable.WidthEntry(width: w, spacings: spacings))
                if tableEnded { break }
            } else {
                break
            }
        }

        if prl.isEmpty && entries.isEmpty { return (nil, i) }
        return (LEFSpacingTable(parallelRunLengths: prl, widthEntries: entries), i)
    }

    // MARK: - VIA

    private static func parseVia(_ tokens: [String], from start: Int) -> (LEFViaDef?, Int) {
        guard start < tokens.count else { return (nil, start) }
        let name = tokens[start]
        var i = start + 1
        var layers: [LEFViaDef.LEFViaLayer] = []
        var isDefault = false
        var isGenerate = false
        var viaRule: String?
        var cutSize: (Double, Double)?
        var cutSpacing: (Double, Double)?
        var enclosure: (Double, Double, Double, Double)?
        var rowCol: (Int, Int)?
        var resistance: Double?

        // Only qualifiers belong to the header; the first body LAYER is not a qualifier.
        while i < tokens.count && ["DEFAULT", "GENERATE"].contains(tokens[i].uppercased()) {
            let upper = tokens[i].uppercased()
            if upper == "DEFAULT" { isDefault = true }
            if upper == "GENERATE" { isGenerate = true }
            i += 1
        }
        i = skipSemicolon(tokens, i)

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count { i += 1 }
                return (LEFViaDef(name: name, layers: layers, isDefault: isDefault,
                                  isGenerate: isGenerate, viaRule: viaRule,
                                  cutSize: cutSize, cutSpacing: cutSpacing,
                                  enclosure: enclosure, rowCol: rowCol,
                                  resistance: resistance), i)
            }
            switch upper {
            case "LAYER":
                i += 1
                if i < tokens.count {
                    let layerName = tokens[i]
                    i += 1
                    i = skipSemicolon(tokens, i)
                    var rects: [LEFRect] = []
                    var polygons: [[LEFPoint]] = []
                    while i < tokens.count {
                        let kw = tokens[i].uppercased()
                        if kw == "RECT" {
                            i += 1
                            if let (rect, next) = parseRect(tokens, from: i) {
                                rects.append(rect)
                                i = next
                            }
                            i = skipSemicolon(tokens, i)
                        } else if kw == "POLYGON" {
                            i += 1
                            let (poly, next) = parsePolygon(tokens, from: i)
                            if !poly.isEmpty { polygons.append(poly) }
                            i = next
                            i = skipSemicolon(tokens, i)
                        } else {
                            break
                        }
                    }
                    layers.append(LEFViaDef.LEFViaLayer(layerName: layerName, rects: rects, polygons: polygons))
                }
            case "VIARULE":
                i += 1
                if i < tokens.count { viaRule = tokens[i]; i += 1 }
                i = skipSemicolon(tokens, i)
            case "CUTSIZE":
                i += 1
                if i + 1 < tokens.count, let w = Double(tokens[i]), let h = Double(tokens[i+1]) {
                    cutSize = (w, h)
                    i += 2
                }
                i = skipSemicolon(tokens, i)
            case "CUTSPACING":
                i += 1
                if i + 1 < tokens.count, let w = Double(tokens[i]), let h = Double(tokens[i+1]) {
                    cutSpacing = (w, h)
                    i += 2
                }
                i = skipSemicolon(tokens, i)
            case "ENCLOSURE":
                i += 1
                if i + 3 < tokens.count,
                   let e1 = Double(tokens[i]), let e2 = Double(tokens[i+1]),
                   let e3 = Double(tokens[i+2]), let e4 = Double(tokens[i+3]) {
                    enclosure = (e1, e2, e3, e4)
                    i += 4
                }
                i = skipSemicolon(tokens, i)
            case "ROWCOL":
                i += 1
                if i + 1 < tokens.count, let r = Int(tokens[i]), let c = Int(tokens[i+1]) {
                    rowCol = (r, c)
                    i += 2
                }
                i = skipSemicolon(tokens, i)
            case "RESISTANCE":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    resistance = val
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            default:
                i += 1
            }
        }

        return (LEFViaDef(name: name, layers: layers, isDefault: isDefault,
                          isGenerate: isGenerate, viaRule: viaRule,
                          cutSize: cutSize, cutSpacing: cutSpacing,
                          enclosure: enclosure, rowCol: rowCol,
                          resistance: resistance), i)
    }

    // MARK: - SITE

    private static func parseSite(_ tokens: [String], from start: Int) -> (LEFSiteDef?, Int) {
        guard start < tokens.count else { return (nil, start) }
        let name = tokens[start]
        var i = start + 1
        var site = LEFSiteDef(name: name)

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count { i += 1 }
                return (site, i)
            }

            switch upper {
            case "CLASS":
                i += 1
                if i < tokens.count {
                    site.siteClass = LEFSiteDef.SiteClass(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "SYMMETRY":
                i += 1
                while i < tokens.count && tokens[i] != ";" {
                    if let sym = LEFMacroDef.Symmetry(rawValue: tokens[i].uppercased()) {
                        site.symmetry.append(sym)
                    }
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "SIZE":
                i += 1
                if i < tokens.count, let w = Double(tokens[i]) {
                    site.width = w; i += 1
                }
                if i < tokens.count && tokens[i].uppercased() == "BY" { i += 1 }
                if i < tokens.count, let h = Double(tokens[i]) {
                    site.height = h; i += 1
                }
                i = skipSemicolon(tokens, i)
            default:
                i += 1
            }
        }

        return (site, i)
    }

    // MARK: - MACRO

    private static func parseMacro(_ tokens: [String], from start: Int) throws -> (LEFMacroDef?, Int) {
        guard start < tokens.count else { return (nil, start) }
        let name = tokens[start]
        var i = start + 1
        var macro = LEFMacroDef(name: name)

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count { i += 1 }
                return (macro, i)
            }

            switch upper {
            case "CLASS":
                i += 1
                if i < tokens.count {
                    macro.macroClass = LEFMacroDef.MacroClass(rawValue: tokens[i].uppercased())
                    // Check for subclass (e.g., "CORE TIEHIGH")
                    i += 1
                    if i < tokens.count && tokens[i] != ";" {
                        macro.subClass = tokens[i]
                        i += 1
                    }
                }
                i = skipSemicolon(tokens, i)
            case "SIZE":
                i += 1
                if i < tokens.count, let w = Double(tokens[i]) {
                    macro.width = w; i += 1
                }
                if i < tokens.count && tokens[i].uppercased() == "BY" { i += 1 }
                if i < tokens.count, let h = Double(tokens[i]) {
                    macro.height = h; i += 1
                }
                i = skipSemicolon(tokens, i)
            case "SYMMETRY":
                i += 1
                while i < tokens.count && tokens[i] != ";" {
                    if let sym = LEFMacroDef.Symmetry(rawValue: tokens[i].uppercased()) {
                        macro.symmetry.append(sym)
                    }
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "ORIGIN":
                i += 1
                if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i+1]) {
                    macro.origin = LEFPoint(x: x, y: y)
                    i += 2
                }
                i = skipSemicolon(tokens, i)
            case "FOREIGN":
                i += 1
                if i < tokens.count {
                    let cellName = tokens[i]; i += 1
                    var pt: LEFPoint?
                    if i + 1 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i+1]) {
                        pt = LEFPoint(x: x, y: y)
                        i += 2
                    }
                    macro.foreign = LEFForeign(cellName: cellName, point: pt)
                }
                i = skipSemicolon(tokens, i)
            case "SITE":
                i += 1
                if i < tokens.count && tokens[i] != ";" {
                    macro.site = tokens[i]; i += 1
                }
                i = skipSemicolon(tokens, i)
            case "FIXEDMASK":
                macro.fixedMask = true
                i += 1
                i = skipSemicolon(tokens, i)
            case "SOURCE":
                i += 1
                if i < tokens.count { macro.source = tokens[i]; i += 1 }
                i = skipSemicolon(tokens, i)
            case "EEQ":
                i += 1
                if i < tokens.count { macro.eeq = tokens[i]; i += 1 }
                i = skipSemicolon(tokens, i)
            case "PROPERTY":
                i += 1
                let (prop, next) = parseProperty(tokens, from: i)
                if let prop = prop { macro.properties.append(prop) }
                i = next
            case "PIN":
                i += 1
                let (pin, next) = try parsePin(tokens, from: i)
                if let pin = pin { macro.pins.append(pin) }
                i = next
            case "OBS":
                i += 1
                let (obs, next) = try parseOBS(tokens, from: i)
                macro.obs = obs
                i = next
            default:
                i += 1
            }
        }

        return (macro, i)
    }

    // MARK: - PIN

    private static func parsePin(_ tokens: [String], from start: Int) throws -> (LEFPinDef?, Int) {
        guard start < tokens.count else { return (nil, start) }
        let name = tokens[start]
        var i = start + 1
        var pin = LEFPinDef(name: name)

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count { i += 1 }
                return (pin, i)
            }

            switch upper {
            case "DIRECTION":
                i += 1
                if i < tokens.count {
                    pin.direction = LEFPinDef.PinDirection(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "USE":
                i += 1
                if i < tokens.count {
                    pin.use = LEFPinDef.PinUse(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "SHAPE":
                i += 1
                if i < tokens.count {
                    pin.shape = LEFPinDef.PinShape(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "ANTENNADIFFAREA":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    pin.antennaDiffArea = val
                    i += 1
                }
                i = skipToSemicolon(tokens, i)
                i = skipSemicolon(tokens, i)
            case "ANTENNAGATEAREA":
                i += 1
                if i < tokens.count, let val = Double(tokens[i]) {
                    pin.antennaGateArea = val
                    i += 1
                }
                i = skipToSemicolon(tokens, i)
                i = skipSemicolon(tokens, i)
            case "ANTENNAMODEL":
                i += 1
                if i < tokens.count {
                    pin.antennaModel = tokens[i]
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "TAPERRULE":
                i += 1
                if i < tokens.count {
                    pin.taperrule = tokens[i]
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "PROPERTY":
                i += 1
                let (prop, next) = parseProperty(tokens, from: i)
                if let prop = prop { pin.properties.append(prop) }
                i = next
            case "PORT":
                i += 1
                let (ports, next) = try parsePortMultiLayer(tokens, from: i)
                pin.ports.append(contentsOf: ports)
                i = next
            case "ANTENNAPARTIALMETALAREA", "ANTENNAPARTIALMETALSIDEAREA",
                 "ANTENNAPARTIALCUTAREA", "ANTENNAMAXAREACAR", "ANTENNAMAXSIDEAREACAR",
                 "ANTENNAMAXCUTCAR":
                i += 1
                i = skipToSemicolon(tokens, i)
                i = skipSemicolon(tokens, i)
            default:
                i += 1
            }
        }

        return (pin, i)
    }

    // MARK: - PORT / OBS

    private static func parsePortMultiLayer(_ tokens: [String], from start: Int) throws -> ([LEFPort], Int) {
        var i = start
        var ports: [LEFPort] = []
        var currentLayer = ""
        var rects: [LEFRect] = []
        var polygons: [[LEFPoint]] = []
        var paths: [LEFPath] = []
        var currentWidth: Double?
        var vias: [LEFPortVia] = []
        var portClass: LEFPort.PortClass?

        func currentPort() -> LEFPort {
            LEFPort(layerName: currentLayer, rects: rects, polygons: polygons,
                paths: paths, vias: vias, portClass: portClass)
        }

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                if !currentLayer.isEmpty { ports.append(currentPort()) }
                return (ports, i + 1)
            }
            switch upper {
            case "CLASS":
                i += 1
                if i < tokens.count {
                    portClass = LEFPort.PortClass(rawValue: tokens[i].uppercased())
                    i += 1
                }
                i = skipSemicolon(tokens, i)
            case "LAYER":
                if !currentLayer.isEmpty { ports.append(currentPort()) }
                rects = []; polygons = []; paths = []; vias = []; currentWidth = nil
                i += 1
                if i < tokens.count { currentLayer = tokens[i]; i += 1 }
                i = skipSemicolon(tokens, i)
            case "WIDTH":
                i += 1
                guard !currentLayer.isEmpty, i < tokens.count, let width = Double(tokens[i]),
                      width.isFinite, width > 0 else {
                    throw LEFError.invalidGeometry("PATH WIDTH requires a selected layer and finite positive value")
                }
                currentWidth = width
                i = skipSemicolon(tokens, i + 1)
            case "PATH":
                i += 1
                guard !currentLayer.isEmpty, let width = currentWidth else {
                    throw LEFError.invalidGeometry("PATH requires a previous WIDTH on its selected layer")
                }
                let (points, next) = parsePolygon(tokens, from: i)
                let path = LEFPath(width: width, points: points)
                try path.validateGeometry()
                paths.append(path)
                i = skipSemicolon(tokens, next)
            case "RECT":
                i += 1
                if let (rect, next) = parseRect(tokens, from: i) {
                    rects.append(rect)
                    i = next
                }
                i = skipSemicolon(tokens, i)
            case "POLYGON":
                i += 1
                let (poly, next) = parsePolygon(tokens, from: i)
                if !poly.isEmpty { polygons.append(poly) }
                i = skipSemicolon(tokens, next)
            case "VIA":
                i += 1
                if i + 2 < tokens.count, let x = Double(tokens[i]), let y = Double(tokens[i+1]) {
                    vias.append(LEFPortVia(viaName: tokens[i+2], point: LEFPoint(x: x, y: y)))
                    i += 3
                }
                i = skipSemicolon(tokens, i)
            default:
                i += 1
            }
        }
        if !currentLayer.isEmpty { ports.append(currentPort()) }
        return (ports, i)
    }

    private static func parseOBS(_ tokens: [String], from start: Int) throws -> ([LEFPort], Int) {
        try parsePortMultiLayer(tokens, from: start)
    }

    // MARK: - Property

    private static func parseProperty(_ tokens: [String], from start: Int) -> (LEFProperty?, Int) {
        var i = start
        guard i < tokens.count else { return (nil, i) }
        let key = tokens[i]; i += 1
        var valueParts: [String] = []
        while i < tokens.count && tokens[i] != ";" {
            valueParts.append(tokens[i])
            i += 1
        }
        i = skipSemicolon(tokens, i)
        let value = valueParts.joined(separator: " ")
        return (LEFProperty(key: key, value: unquote(value)), i)
    }

    // MARK: - Geometry Helpers

    private static func parseRect(_ tokens: [String], from start: Int) -> (LEFRect, Int)? {
        var i = start
        // Handle optional MASK keyword
        var mask: Int?
        if i < tokens.count && tokens[i].uppercased() == "MASK" {
            i += 1
            if i < tokens.count, let m = Int(tokens[i]) { mask = m; i += 1 }
        }
        guard i + 3 < tokens.count,
              let x1 = Double(tokens[i]), let y1 = Double(tokens[i+1]),
              let x2 = Double(tokens[i+2]), let y2 = Double(tokens[i+3]) else { return nil }
        return (LEFRect(x1: x1, y1: y1, x2: x2, y2: y2, mask: mask), i + 4)
    }

    private static func parsePolygon(_ tokens: [String], from start: Int) -> ([LEFPoint], Int) {
        var i = start
        // Handle optional MASK keyword
        if i < tokens.count && tokens[i].uppercased() == "MASK" {
            i += 1
            if i < tokens.count { i += 1 } // skip mask number
        }
        var points: [LEFPoint] = []
        while i + 1 < tokens.count {
            guard let x = Double(tokens[i]) else { break }
            guard let y = Double(tokens[i+1]) else { break }
            points.append(LEFPoint(x: x, y: y))
            i += 2
        }
        return (points, i)
    }

    // MARK: - Helpers

    private static func skipSemicolon(_ tokens: [String], _ i: Int) -> Int {
        if i < tokens.count && tokens[i] == ";" { return i + 1 }
        return i
    }

    private static func skipToSemicolon(_ tokens: [String], _ i: Int) -> Int {
        var j = i
        while j < tokens.count && tokens[j] != ";" { j += 1 }
        return j
    }

    private static func skipToEnd(_ tokens: [String], from start: Int) -> Int {
        var i = start
        let name = i < tokens.count ? tokens[i] : ""
        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i] == name { i += 1 }
                return i
            }
            i += 1
        }
        return i
    }

    private static func skipToEndKeyword(_ tokens: [String], from start: Int, keyword: String) -> Int {
        var i = start
        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == keyword { i += 1 }
                return i
            }
            i += 1
        }
        return i
    }

    private static func unquote(_ s: String) -> String {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}
