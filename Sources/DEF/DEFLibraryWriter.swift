import Foundation
import LayoutIR

/// Writes a DEFDocument to DEF text format.
public enum DEFLibraryWriter {

    public static func write(_ doc: DEFDocument) throws -> Data {
        var lines: [String] = []

        lines.append("VERSION \(doc.version) ;")
        lines.append("DESIGN \(doc.designName) ;")

        if let bc = doc.busbitChars {
            lines.append("BUSBITCHARS \"\(bc)\" ;")
        }
        if let dc = doc.dividerChar {
            lines.append("DIVIDERCHAR \"\(dc)\" ;")
        }

        lines.append("UNITS DISTANCE MICRONS \(formatNum(doc.dbuPerMicron)) ;")

        if !doc.propertyDefinitions.isEmpty {
            lines.append("")
            lines.append("PROPERTYDEFINITIONS")
            for pd in doc.propertyDefinitions {
                var line = "  \(pd.objectType) \(pd.propName) \(pd.propType)"
                if let dv = pd.defaultValue { line += " \"\(dv)\"" }
                line += " ;"
                lines.append(line)
            }
            lines.append("END PROPERTYDEFINITIONS")
        }

        if let area = doc.dieArea {
            let pointsStr = area.points.map { "( \($0.x) \($0.y) )" }.joined(separator: " ")
            lines.append("DIEAREA \(pointsStr) ;")
        }

        for row in doc.rows {
            writeRow(row, to: &lines)
        }

        for track in doc.tracks {
            writeTrack(track, to: &lines)
        }

        for grid in doc.gcellGrids {
            writeGCellGrid(grid, to: &lines)
        }

        if !doc.viaDefs.isEmpty {
            lines.append("")
            lines.append("VIAS \(doc.viaDefs.count) ;")
            for via in doc.viaDefs {
                writeViaDef(via, to: &lines)
            }
            lines.append("END VIAS")
        }

        if !doc.components.isEmpty {
            lines.append("")
            lines.append("COMPONENTS \(doc.components.count) ;")
            for comp in doc.components {
                writeComponent(comp, to: &lines)
            }
            lines.append("END COMPONENTS")
        }

        if !doc.pins.isEmpty {
            lines.append("")
            lines.append("PINS \(doc.pins.count) ;")
            for pin in doc.pins {
                writePin(pin, to: &lines)
            }
            lines.append("END PINS")
        }

        if !doc.blockages.isEmpty {
            lines.append("")
            lines.append("BLOCKAGES \(doc.blockages.count) ;")
            for blk in doc.blockages {
                writeBlockage(blk, to: &lines)
            }
            lines.append("END BLOCKAGES")
        }

        if !doc.regions.isEmpty {
            lines.append("")
            lines.append("REGIONS \(doc.regions.count) ;")
            for reg in doc.regions {
                writeRegion(reg, to: &lines)
            }
            lines.append("END REGIONS")
        }

        if !doc.nets.isEmpty {
            lines.append("")
            lines.append("NETS \(doc.nets.count) ;")
            for net in doc.nets {
                writeNet(net, to: &lines)
            }
            lines.append("END NETS")
        }

        if !doc.specialNets.isEmpty {
            lines.append("")
            lines.append("SPECIALNETS \(doc.specialNets.count) ;")
            for snet in doc.specialNets {
                writeSpecialNet(snet, to: &lines)
            }
            lines.append("END SPECIALNETS")
        }

        if !doc.fills.isEmpty {
            lines.append("")
            lines.append("FILLS \(doc.fills.count) ;")
            for fill in doc.fills {
                writeFill(fill, to: &lines)
            }
            lines.append("END FILLS")
        }

        if !doc.groups.isEmpty {
            lines.append("")
            lines.append("GROUPS \(doc.groups.count) ;")
            for grp in doc.groups {
                writeGroup(grp, to: &lines)
            }
            lines.append("END GROUPS")
        }

        if !doc.properties.isEmpty {
            for prop in doc.properties {
                lines.append("PROPERTY \(prop.key) \(prop.value) ;")
            }
        }

        lines.append("")
        lines.append("END DESIGN")
        lines.append("")

        let text = lines.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw DEFError.invalidEncoding
        }
        return data
    }

    // MARK: - ROW

    private static func writeRow(_ row: DEFRow, to lines: inout [String]) {
        var line = "ROW \(row.rowName) \(row.siteName) \(row.originX) \(row.originY) \(row.orientation.rawValue)"
        if row.numX != 1 || row.numY != 1 {
            line += " DO \(row.numX) BY \(row.numY)"
        }
        if row.stepX != 0 || row.stepY != 0 {
            line += " STEP \(row.stepX) \(row.stepY)"
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - TRACKS

    private static func writeTrack(_ track: DEFTrack, to lines: inout [String]) {
        var line = "TRACKS \(track.direction.rawValue) \(track.start) DO \(track.numTracks) STEP \(track.step)"
        for layer in track.layerNames {
            line += " LAYER \(layer)"
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - GCELLGRID

    private static func writeGCellGrid(_ grid: DEFGCellGrid, to lines: inout [String]) {
        lines.append("GCELLGRID \(grid.direction.rawValue) \(grid.start) DO \(grid.numColumns) STEP \(grid.step) ;")
    }

    // MARK: - VIAS

    private static func writeViaDef(_ via: DEFViaDef, to lines: inout [String]) {
        var line = "  - \(via.name)"
        if let vr = via.viaRule { line += " + VIARULE \(vr)" }
        if let cs = via.cutSize { line += " + CUTSIZE \(cs.width) \(cs.height)" }
        if let csp = via.cutSpacing { line += " + CUTSPACING \(csp.x) \(csp.y)" }
        if let be = via.botEnclosure, let te = via.topEnclosure {
            line += " + ENCLOSURE \(be.x) \(be.y) \(te.x) \(te.y)"
        }
        if let rc = via.rowCol { line += " + ROWCOL \(rc.rows) \(rc.cols)" }
        if !via.layers.isEmpty && via.viaRule != nil {
            let layerNames = via.layers.map(\.layerName).joined(separator: " ")
            line += " + LAYERS \(layerNames)"
        }
        for vl in via.layers {
            for r in vl.rects {
                line += " + RECT \(vl.layerName) ( \(r.x1) \(r.y1) ) ( \(r.x2) \(r.y2) )"
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - COMPONENTS

    private static func writeComponent(_ comp: DEFComponent, to lines: inout [String]) {
        var line = "  - \(comp.name) \(comp.macro)"
        if let status = comp.placementStatus {
            if status == .unplaced {
                line += " + UNPLACED"
            } else {
                line += " + \(status.rawValue) ( \(comp.x) \(comp.y) ) \(comp.orientation.rawValue)"
            }
        }
        if let w = comp.weight { line += " + WEIGHT \(w)" }
        if let r = comp.region { line += " + REGION \(r)" }
        if let s = comp.source { line += " + SOURCE \(s)" }
        if !comp.properties.isEmpty {
            line += " + PROPERTY"
            for p in comp.properties {
                line += " \(p.key) \"\(p.value)\""
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - PINS

    private static func writePin(_ pin: DEFPin, to lines: inout [String]) {
        var line = "  - \(pin.name)"
        if let net = pin.netName { line += " + NET \(net)" }
        if let dir = pin.direction { line += " + DIRECTION \(dir.rawValue)" }
        if let use = pin.use { line += " + USE \(use.rawValue)" }
        if pin.special { line += " + SPECIAL" }
        if pin.layerRects.isEmpty {
            if let layer = pin.layerName { line += " + LAYER \(layer)" }
        } else {
            for lr in pin.layerRects {
                line += " + LAYER \(lr.layerName)"
                for r in lr.rects {
                    line += " ( \(r.x1) \(r.y1) ) ( \(r.x2) \(r.y2) )"
                }
            }
        }
        if let status = pin.placementStatus {
            if status == .unplaced {
                line += " + UNPLACED"
            } else {
                line += " + \(status.rawValue) ( \(pin.x) \(pin.y) ) \(pin.orientation.rawValue)"
            }
        }
        if !pin.properties.isEmpty {
            line += " + PROPERTY"
            for p in pin.properties {
                line += " \(p.key) \"\(p.value)\""
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - BLOCKAGES

    private static func writeBlockage(_ blk: DEFBlockage, to lines: inout [String]) {
        var line = "  - \(blk.blockageType.rawValue)"
        if let layer = blk.layerName { line += " + LAYER \(layer)" }
        if let comp = blk.component { line += " + COMPONENT \(comp)" }
        if blk.pushdown { line += " + PUSHDOWN" }
        for r in blk.rects {
            line += " RECT ( \(r.x1) \(r.y1) ) ( \(r.x2) \(r.y2) )"
        }
        for poly in blk.polygons {
            let ptsStr = poly.map { "( \($0.x) \($0.y) )" }.joined(separator: " ")
            line += " POLYGON \(ptsStr)"
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - REGIONS

    private static func writeRegion(_ reg: DEFRegion, to lines: inout [String]) {
        var line = "  - \(reg.name)"
        for r in reg.rects {
            line += " ( \(r.x1) \(r.y1) ) ( \(r.x2) \(r.y2) )"
        }
        if let rt = reg.regionType { line += " + TYPE \(rt.rawValue)" }
        line += " ;"
        lines.append(line)
    }

    // MARK: - NETS

    private static func writeNet(_ net: DEFNet, to lines: inout [String]) {
        var line = "  - \(net.name)"
        for conn in net.connections {
            line += " ( \(conn.componentName) \(conn.pinName) )"
        }
        if let use = net.use { line += " + USE \(use.rawValue)" }
        for wire in net.routing {
            line += " + \(wire.status.rawValue) \(wire.layerName)"
            for p in wire.points {
                line += " ( \(p.x) \(p.y) )"
            }
            if let via = wire.viaName { line += " \(via)" }
        }
        if !net.properties.isEmpty {
            line += " + PROPERTY"
            for p in net.properties {
                line += " \(p.key) \"\(p.value)\""
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - SPECIALNETS

    private static func writeSpecialNet(_ snet: DEFSpecialNet, to lines: inout [String]) {
        var line = "  - \(snet.name)"
        for conn in snet.connections {
            line += " ( \(conn.componentName) \(conn.pinName) )"
        }
        if let use = snet.use { line += " + USE \(use.rawValue)" }
        if let src = snet.source { line += " + SOURCE \(src)" }
        if let w = snet.weight { line += " + WEIGHT \(w)" }
        for seg in snet.routing {
            line += " + \(seg.status.rawValue) \(seg.layerName) \(seg.width)"
            if let shape = seg.shape { line += " + SHAPE \(shape.rawValue)" }
            for p in seg.points {
                if let viaName = p.viaName {
                    line += " \(viaName)"
                } else {
                    let xStr = p.x.map { String($0) } ?? "*"
                    let yStr = p.y.map { String($0) } ?? "*"
                    if let ext = p.ext {
                        line += " ( \(xStr) \(yStr) \(ext) )"
                    } else {
                        line += " ( \(xStr) \(yStr) )"
                    }
                }
            }
        }
        if !snet.properties.isEmpty {
            line += " + PROPERTY"
            for p in snet.properties {
                line += " \(p.key) \"\(p.value)\""
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - FILLS

    private static func writeFill(_ fill: DEFFill, to lines: inout [String]) {
        var line = "  - LAYER \(fill.layerName)"
        if fill.opc { line += " + OPC" }
        for r in fill.rects {
            line += " RECT ( \(r.x1) \(r.y1) ) ( \(r.x2) \(r.y2) )"
        }
        for poly in fill.polygons {
            let ptsStr = poly.map { "( \($0.x) \($0.y) )" }.joined(separator: " ")
            line += " POLYGON \(ptsStr)"
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - GROUPS

    private static func writeGroup(_ grp: DEFGroup, to lines: inout [String]) {
        var line = "  - \(grp.name)"
        for comp in grp.components {
            line += " \(comp)"
        }
        if let reg = grp.region { line += " + REGION \(reg)" }
        if !grp.properties.isEmpty {
            line += " + PROPERTY"
            for p in grp.properties {
                line += " \(p.key) \"\(p.value)\""
            }
        }
        line += " ;"
        lines.append(line)
    }

    // MARK: - Helpers

    private static func formatNum(_ val: Double) -> String {
        if val == val.rounded() && val.magnitude < 1e15 { return String(Int(val)) }
        return String(val)
    }
}
