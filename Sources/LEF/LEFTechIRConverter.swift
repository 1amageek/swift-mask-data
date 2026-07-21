import TechIR

/// Converts between LEF technology data and the `IRTechLibrary` intermediate representation.
public enum LEFTechIRConverter {

    // MARK: - LEFDocument → IRTechLibrary

    public static func toIRTechLibrary(_ doc: LEFDocument) throws -> IRTechLibrary {
        var layers: [IRTechLayerDef] = []
        var designRules: [IRTechDesignRule] = []
        var enclosureRules: [IRTechEnclosureRule] = []

        for lefLayer in doc.layers {
            layers.append(try convertLayer(lefLayer))

            let rule = extractDesignRule(from: lefLayer)
            if rule.minWidth != nil || rule.minSpacing != nil || rule.minArea != nil {
                designRules.append(rule)
            }

            if let enc = lefLayer.enclosure, lefLayer.type == .cut {
                enclosureRules.append(IRTechEnclosureRule(
                    outerLayerName: lefLayer.name,
                    innerLayerName: lefLayer.name,
                    minEnclosure: min(enc.overhang1, enc.overhang2)
                ))
            }
        }

        let vias = doc.vias.map { convertVia($0) }
        let sites = doc.sites.map { convertSite($0) }

        return IRTechLibrary(
            name: "",
            dbuPerMicron: doc.dbuPerMicron,
            layers: layers,
            vias: vias,
            sites: sites,
            designRules: designRules,
            enclosureRules: enclosureRules,
            metadata: ["lef.version": doc.version]
        )
    }

    // MARK: - IRTechLibrary → LEFDocument

    public static func toLEFDocument(_ lib: IRTechLibrary) -> LEFDocument {
        let layers = lib.layers.map { convertLayerBack($0, rules: lib.designRules) }
        let vias = lib.vias.map { convertViaBack($0) }
        let sites = lib.sites.map { convertSiteBack($0) }

        return LEFDocument(
            version: lib.metadata["lef.version"] ?? "5.8",
            dbuPerMicron: lib.dbuPerMicron,
            layers: layers,
            vias: vias,
            sites: sites
        )
    }

    // MARK: - Layer Conversion

    private static func convertLayer(_ lef: LEFLayerDef) throws -> IRTechLayerDef {
        var spacingTable: IRTechSpacingTable?
        if let lefTable = lef.spacingTable {
            var entries: [IRTechSpacingWidthEntry] = []
            for entry in lefTable.widthEntries {
                guard let spacing = entry.spacings.first else {
                    throw LEFError.invalidGeometry("spacing-table width entry has no spacing value")
                }
                entries.append(IRTechSpacingWidthEntry(width: entry.width, spacing: spacing))
            }
            spacingTable = IRTechSpacingTable(entries: entries)
        }

        return IRTechLayerDef(
            name: lef.name,
            type: convertLayerType(lef.type),
            direction: lef.direction.map { convertDirection($0) },
            pitch: lef.pitch,
            width: lef.width,
            spacing: lef.spacing,
            resistance: lef.resistance,
            capacitance: lef.capacitance,
            thickness: lef.thickness,
            spacingTable: spacingTable,
            minArea: lef.area
        )
    }

    private static func extractDesignRule(from lef: LEFLayerDef) -> IRTechDesignRule {
        IRTechDesignRule(
            layerName: lef.name,
            minWidth: lef.minwidth ?? lef.width,
            minSpacing: lef.spacing,
            minArea: lef.area
        )
    }

    private static func convertLayerType(_ type: LEFLayerDef.LayerType) -> IRTechLayerType {
        switch type {
        case .routing:     return .routing
        case .cut:         return .cut
        case .masterslice: return .masterslice
        case .overlap:     return .overlap
        case .implant:     return .implant
        }
    }

    private static func convertDirection(_ dir: LEFLayerDef.Direction) -> IRTechLayerDirection {
        switch dir {
        case .horizontal: return .horizontal
        case .vertical:   return .vertical
        }
    }

    private static func convertLayerBack(_ ir: IRTechLayerDef, rules: [IRTechDesignRule]) -> LEFLayerDef {
        let rule = rules.first { $0.layerName == ir.name }

        let direction: LEFLayerDef.Direction? = ir.direction.map { d in
            switch d {
            case .horizontal: return .horizontal
            case .vertical:   return .vertical
            }
        }

        let layerType: LEFLayerDef.LayerType = {
            switch ir.type {
            case .routing:     return .routing
            case .cut:         return .cut
            case .masterslice: return .masterslice
            case .overlap:     return .overlap
            case .implant:     return .implant
            }
        }()

        return LEFLayerDef(
            name: ir.name,
            type: layerType,
            direction: direction,
            pitch: ir.pitch,
            width: ir.width,
            spacing: ir.spacing ?? rule?.minSpacing,
            resistance: ir.resistance,
            capacitance: ir.capacitance,
            thickness: ir.thickness,
            minwidth: rule?.minWidth,
            area: ir.minArea ?? rule?.minArea
        )
    }

    // MARK: - Via Conversion

    private static func convertVia(_ lef: LEFViaDef) -> IRTechViaDef {
        var cutLayerName = ""
        var topLayerName = ""
        var bottomLayerName = ""

        if lef.layers.count >= 3 {
            bottomLayerName = lef.layers[0].layerName
            cutLayerName = lef.layers[1].layerName
            topLayerName = lef.layers[2].layerName
        } else if lef.layers.count == 2 {
            bottomLayerName = lef.layers[0].layerName
            topLayerName = lef.layers[1].layerName
        } else if lef.layers.count == 1 {
            cutLayerName = lef.layers[0].layerName
        }

        let irLayers = lef.layers.map { vl in
            IRTechViaLayerGeometry(
                layerName: vl.layerName,
                rects: vl.rects.map { IRTechRect(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2) }
            )
        }

        var enclosure: IRTechEnclosureValues?
        if let enc = lef.enclosure {
            enclosure = IRTechEnclosureValues(overhang1: enc.0, overhang2: enc.1)
        }

        return IRTechViaDef(
            name: lef.name,
            cutLayerName: cutLayerName,
            topLayerName: topLayerName,
            bottomLayerName: bottomLayerName,
            cutWidth: lef.cutSize?.0,
            cutHeight: lef.cutSize?.1,
            enclosure: enclosure,
            spacing: lef.cutSpacing?.0,
            resistance: lef.resistance,
            layers: irLayers
        )
    }

    private static func convertViaBack(_ ir: IRTechViaDef) -> LEFViaDef {
        let lefLayers = ir.layers.map { vl in
            LEFViaDef.LEFViaLayer(
                layerName: vl.layerName,
                rects: vl.rects.map { LEFRect(x1: $0.x1, y1: $0.y1, x2: $0.x2, y2: $0.y2) }
            )
        }

        var cutSize: (Double, Double)?
        if let w = ir.cutWidth, let h = ir.cutHeight {
            cutSize = (w, h)
        }

        var cutSpacing: (Double, Double)?
        if let s = ir.spacing {
            cutSpacing = (s, s)
        }

        var enclosure: (Double, Double, Double, Double)?
        if let enc = ir.enclosure {
            enclosure = (enc.overhang1, enc.overhang2, enc.overhang1, enc.overhang2)
        }

        return LEFViaDef(
            name: ir.name,
            layers: lefLayers,
            cutSize: cutSize,
            cutSpacing: cutSpacing,
            enclosure: enclosure,
            resistance: ir.resistance
        )
    }

    // MARK: - Site Conversion

    private static func convertSite(_ lef: LEFSiteDef) -> IRTechSiteDef {
        let siteClass: IRTechSiteClass? = lef.siteClass.map { sc in
            switch sc {
            case .core: return .core
            case .pad:  return .pad
            }
        }

        let symmetry = lef.symmetry.map { s -> IRTechSymmetry in
            switch s {
            case .x:   return .x
            case .y:   return .y
            case .r90: return .r90
            }
        }

        return IRTechSiteDef(
            name: lef.name,
            siteClass: siteClass,
            width: lef.width,
            height: lef.height,
            symmetry: symmetry
        )
    }

    private static func convertSiteBack(_ ir: IRTechSiteDef) -> LEFSiteDef {
        let siteClass: LEFSiteDef.SiteClass? = ir.siteClass.map { sc in
            switch sc {
            case .core: return .core
            case .pad:  return .pad
            }
        }

        let symmetry = ir.symmetry.map { s -> LEFMacroDef.Symmetry in
            switch s {
            case .x:   return .x
            case .y:   return .y
            case .r90: return .r90
            }
        }

        return LEFSiteDef(
            name: ir.name,
            siteClass: siteClass,
            symmetry: symmetry,
            width: ir.width,
            height: ir.height
        )
    }
}
