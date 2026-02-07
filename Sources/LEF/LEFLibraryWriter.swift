import Foundation

/// Writes a LEFDocument to LEF text format.
public enum LEFLibraryWriter {

    public static func write(_ doc: LEFDocument) throws -> Data {
        var lines: [String] = []

        lines.append("VERSION \(doc.version) ;")
        lines.append("")

        if let bc = doc.busbitChars {
            lines.append("BUSBITCHARS \"\(bc)\" ;")
        }
        if let dc = doc.dividerChar {
            lines.append("DIVIDERCHAR \"\(dc)\" ;")
        }

        lines.append("UNITS")
        lines.append("  DATABASE MICRONS \(formatNum(doc.dbuPerMicron)) ;")
        lines.append("END UNITS")
        lines.append("")

        for site in doc.sites {
            writeSite(site, to: &lines)
            lines.append("")
        }

        for layer in doc.layers {
            writeLayer(layer, to: &lines)
            lines.append("")
        }

        for via in doc.vias {
            writeVia(via, to: &lines)
            lines.append("")
        }

        for macro in doc.macros {
            writeMacro(macro, to: &lines)
            lines.append("")
        }

        if !doc.properties.isEmpty {
            for prop in doc.properties {
                lines.append("PROPERTY \(prop.key) \"\(prop.value)\" ;")
            }
            lines.append("")
        }

        lines.append("END LIBRARY")
        lines.append("")

        let text = lines.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw LEFError.invalidEncoding
        }
        return data
    }

    // MARK: - SITE

    private static func writeSite(_ site: LEFSiteDef, to lines: inout [String]) {
        lines.append("SITE \(site.name)")
        if let cls = site.siteClass {
            lines.append("  CLASS \(cls.rawValue) ;")
        }
        if !site.symmetry.isEmpty {
            let syms = site.symmetry.map(\.rawValue).joined(separator: " ")
            lines.append("  SYMMETRY \(syms) ;")
        }
        if let w = site.width, let h = site.height {
            lines.append("  SIZE \(formatNum(w)) BY \(formatNum(h)) ;")
        }
        lines.append("END \(site.name)")
    }

    // MARK: - LAYER

    private static func writeLayer(_ layer: LEFLayerDef, to lines: inout [String]) {
        lines.append("LAYER \(layer.name)")
        lines.append("  TYPE \(layer.type.rawValue) ;")
        if let dir = layer.direction {
            lines.append("  DIRECTION \(dir.rawValue) ;")
        }
        if let p = layer.pitch {
            lines.append("  PITCH \(formatNum(p)) ;")
        }
        if let w = layer.width {
            lines.append("  WIDTH \(formatNum(w)) ;")
        }
        if let s = layer.spacing {
            lines.append("  SPACING \(formatNum(s)) ;")
        }
        if let o = layer.offset {
            lines.append("  OFFSET \(formatNum(o)) ;")
        }
        if let r = layer.resistance {
            lines.append("  RESISTANCE RPERSQ \(formatNum(r)) ;")
        }
        if let c = layer.capacitance {
            lines.append("  CAPACITANCE CPERSQDIST \(formatNum(c)) ;")
        }
        if let ec = layer.edgeCapacitance {
            lines.append("  EDGECAPACITANCE \(formatNum(ec)) ;")
        }
        if let t = layer.thickness {
            lines.append("  THICKNESS \(formatNum(t)) ;")
        }
        if let mw = layer.minwidth {
            lines.append("  MINWIDTH \(formatNum(mw)) ;")
        }
        if let mw = layer.maxwidth {
            lines.append("  MAXWIDTH \(formatNum(mw)) ;")
        }
        if let a = layer.area {
            lines.append("  AREA \(formatNum(a)) ;")
        }
        if let enc = layer.enclosure {
            lines.append("  ENCLOSURE \(formatNum(enc.overhang1)) \(formatNum(enc.overhang2)) ;")
        }
        if let tbl = layer.spacingTable {
            writeSpacingTable(tbl, to: &lines)
        }
        lines.append("END \(layer.name)")
    }

    private static func writeSpacingTable(_ tbl: LEFSpacingTable, to lines: inout [String]) {
        let prlStr = tbl.parallelRunLengths.map { formatNum($0) }.joined(separator: " ")
        lines.append("  SPACINGTABLE")
        lines.append("    PARALLELRUNLENGTH \(prlStr) ;")
        for entry in tbl.widthEntries {
            let spacingStr = entry.spacings.map { formatNum($0) }.joined(separator: " ")
            lines.append("    WIDTH \(formatNum(entry.width)) \(spacingStr) ;")
        }
    }

    // MARK: - VIA

    private static func writeVia(_ via: LEFViaDef, to lines: inout [String]) {
        var header = "VIA \(via.name)"
        if via.isDefault { header += " DEFAULT" }
        if via.isGenerate { header += " GENERATE" }
        header += " ;"
        lines.append(header)
        if let vr = via.viaRule {
            lines.append("  VIARULE \(vr) ;")
        }
        if let cs = via.cutSize {
            lines.append("  CUTSIZE \(formatNum(cs.0)) \(formatNum(cs.1)) ;")
        }
        if let csp = via.cutSpacing {
            lines.append("  CUTSPACING \(formatNum(csp.0)) \(formatNum(csp.1)) ;")
        }
        if let enc = via.enclosure {
            lines.append("  ENCLOSURE \(formatNum(enc.0)) \(formatNum(enc.1)) \(formatNum(enc.2)) \(formatNum(enc.3)) ;")
        }
        if let rc = via.rowCol {
            lines.append("  ROWCOL \(rc.0) \(rc.1) ;")
        }
        if let r = via.resistance {
            lines.append("  RESISTANCE \(formatNum(r)) ;")
        }
        for vl in via.layers {
            lines.append("  LAYER \(vl.layerName) ;")
            for r in vl.rects {
                var rectStr = "    RECT"
                if let m = r.mask { rectStr += " MASK \(m)" }
                rectStr += " \(formatNum(r.x1)) \(formatNum(r.y1)) \(formatNum(r.x2)) \(formatNum(r.y2)) ;"
                lines.append(rectStr)
            }
            for poly in vl.polygons {
                let ptsStr = poly.map { "\(formatNum($0.x)) \(formatNum($0.y))" }.joined(separator: " ")
                lines.append("    POLYGON \(ptsStr) ;")
            }
        }
        lines.append("END \(via.name)")
    }

    // MARK: - MACRO

    private static func writeMacro(_ macro: LEFMacroDef, to lines: inout [String]) {
        lines.append("MACRO \(macro.name)")
        if let cls = macro.macroClass {
            var classLine = "  CLASS \(cls.rawValue)"
            if let sub = macro.subClass { classLine += " \(sub)" }
            classLine += " ;"
            lines.append(classLine)
        }
        if let origin = macro.origin {
            lines.append("  ORIGIN \(formatNum(origin.x)) \(formatNum(origin.y)) ;")
        }
        if let foreign = macro.foreign {
            var fLine = "  FOREIGN \(foreign.cellName)"
            if let pt = foreign.point { fLine += " \(formatNum(pt.x)) \(formatNum(pt.y))" }
            fLine += " ;"
            lines.append(fLine)
        }
        if let w = macro.width, let h = macro.height {
            lines.append("  SIZE \(formatNum(w)) BY \(formatNum(h)) ;")
        }
        if macro.fixedMask {
            lines.append("  FIXEDMASK ;")
        }
        if !macro.symmetry.isEmpty {
            let syms = macro.symmetry.map(\.rawValue).joined(separator: " ")
            lines.append("  SYMMETRY \(syms) ;")
        }
        if let site = macro.site {
            lines.append("  SITE \(site) ;")
        }
        if let source = macro.source {
            lines.append("  SOURCE \(source) ;")
        }
        if let eeq = macro.eeq {
            lines.append("  EEQ \(eeq) ;")
        }
        for prop in macro.properties {
            lines.append("  PROPERTY \(prop.key) \"\(prop.value)\" ;")
        }
        for pin in macro.pins {
            writePin(pin, to: &lines)
        }
        if !macro.obs.isEmpty {
            lines.append("  OBS")
            for port in macro.obs {
                lines.append("    LAYER \(port.layerName) ;")
                for r in port.rects {
                    var rectStr = "      RECT"
                    if let m = r.mask { rectStr += " MASK \(m)" }
                    rectStr += " \(formatNum(r.x1)) \(formatNum(r.y1)) \(formatNum(r.x2)) \(formatNum(r.y2)) ;"
                    lines.append(rectStr)
                }
                for poly in port.polygons {
                    let ptsStr = poly.map { "\(formatNum($0.x)) \(formatNum($0.y))" }.joined(separator: " ")
                    lines.append("      POLYGON \(ptsStr) ;")
                }
            }
            lines.append("  END")
        }
        lines.append("END \(macro.name)")
    }

    private static func writePin(_ pin: LEFPinDef, to lines: inout [String]) {
        lines.append("  PIN \(pin.name)")
        if let dir = pin.direction {
            lines.append("    DIRECTION \(dir.rawValue) ;")
        }
        if let use = pin.use {
            lines.append("    USE \(use.rawValue) ;")
        }
        if let shape = pin.shape {
            lines.append("    SHAPE \(shape.rawValue) ;")
        }
        if let ada = pin.antennaDiffArea {
            lines.append("    ANTENNADIFFAREA \(formatNum(ada)) ;")
        }
        if let aga = pin.antennaGateArea {
            lines.append("    ANTENNAGATEAREA \(formatNum(aga)) ;")
        }
        if let am = pin.antennaModel {
            lines.append("    ANTENNAMODEL \(am) ;")
        }
        if let tr = pin.taperrule {
            lines.append("    TAPERRULE \(tr) ;")
        }
        for prop in pin.properties {
            lines.append("    PROPERTY \(prop.key) \"\(prop.value)\" ;")
        }
        for port in pin.ports {
            lines.append("    PORT")
            if let pc = port.portClass {
                lines.append("      CLASS \(pc.rawValue) ;")
            }
            lines.append("      LAYER \(port.layerName) ;")
            for r in port.rects {
                var rectStr = "        RECT"
                if let m = r.mask { rectStr += " MASK \(m)" }
                rectStr += " \(formatNum(r.x1)) \(formatNum(r.y1)) \(formatNum(r.x2)) \(formatNum(r.y2)) ;"
                lines.append(rectStr)
            }
            for poly in port.polygons {
                let ptsStr = poly.map { "\(formatNum($0.x)) \(formatNum($0.y))" }.joined(separator: " ")
                lines.append("        POLYGON \(ptsStr) ;")
            }
            for via in port.vias {
                lines.append("        VIA \(formatNum(via.point.x)) \(formatNum(via.point.y)) \(via.viaName) ;")
            }
            lines.append("    END")
        }
        lines.append("  END \(pin.name)")
    }

    // MARK: - Helpers

    private static func formatNum(_ val: Double) -> String {
        if val == val.rounded() && val.magnitude < 1e15 {
            return String(Int(val))
        }
        return String(val)
    }
}
