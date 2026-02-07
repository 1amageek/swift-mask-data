import Foundation
import LayoutIR

/// Converts between DEFDocument and IRLibrary.
public enum DEFIRConverter {

    /// Convert a DEFDocument to an IRLibrary.
    /// Components become IRCellRef elements in a top-level cell.
    public static func toIRLibrary(_ doc: DEFDocument) -> IRLibrary {
        var elements: [IRElement] = []

        for comp in doc.components {
            let transform = orientationToTransform(comp.orientation)
            elements.append(.cellRef(IRCellRef(
                cellName: comp.macro,
                origin: IRPoint(x: comp.x, y: comp.y),
                transform: transform,
                properties: []
            )))
        }

        // Die area as boundary
        if let area = doc.dieArea {
            let pts: [IRPoint]
            if area.isRectangular, let bb = area.boundingBox {
                pts = [
                    IRPoint(x: bb.x1, y: bb.y1),
                    IRPoint(x: bb.x2, y: bb.y1),
                    IRPoint(x: bb.x2, y: bb.y2),
                    IRPoint(x: bb.x1, y: bb.y2),
                    IRPoint(x: bb.x1, y: bb.y1),
                ]
            } else {
                var polyPts = area.points
                if let first = polyPts.first, polyPts.last != first {
                    polyPts.append(first)
                }
                pts = polyPts
            }
            elements.insert(.boundary(IRBoundary(
                layer: 0, datatype: 0,
                points: pts,
                properties: []
            )), at: 0)
        }

        // Pin labels
        for pin in doc.pins {
            elements.append(.text(IRText(
                layer: 0, texttype: 0,
                transform: .identity,
                position: IRPoint(x: pin.x, y: pin.y),
                string: pin.name,
                properties: []
            )))
        }

        let topCell = IRCell(name: doc.designName.isEmpty ? "TOP" : doc.designName, elements: elements)
        return IRLibrary(
            name: doc.designName,
            units: IRUnits(dbuPerMicron: doc.dbuPerMicron),
            cells: [topCell]
        )
    }

    /// Convert an IRLibrary to a DEFDocument.
    public static func toDEFDocument(_ library: IRLibrary) -> DEFDocument {
        var doc = DEFDocument(designName: library.name, dbuPerMicron: library.units.dbuPerMicron)
        guard let topCell = library.cells.first else { return doc }

        for element in topCell.elements {
            switch element {
            case .cellRef(let ref):
                let orient = transformToOrientation(ref.transform)
                doc.components.append(DEFComponent(
                    name: ref.cellName,
                    macro: ref.cellName,
                    x: ref.origin.x,
                    y: ref.origin.y,
                    orientation: orient
                ))
            default:
                break
            }
        }

        return doc
    }

    // MARK: - Orientation Mapping

    public static func orientationToTransform(_ orient: DEFOrientation) -> IRTransform {
        switch orient {
        case .n:  return IRTransform(mirrorX: false, magnification: 1.0, angle: 0)
        case .s:  return IRTransform(mirrorX: false, magnification: 1.0, angle: 180)
        case .e:  return IRTransform(mirrorX: false, magnification: 1.0, angle: 90)
        case .w:  return IRTransform(mirrorX: false, magnification: 1.0, angle: 270)
        case .fn: return IRTransform(mirrorX: true, magnification: 1.0, angle: 0)
        case .fs: return IRTransform(mirrorX: true, magnification: 1.0, angle: 180)
        case .fe: return IRTransform(mirrorX: true, magnification: 1.0, angle: 90)
        case .fw: return IRTransform(mirrorX: true, magnification: 1.0, angle: 270)
        }
    }

    public static func transformToOrientation(_ t: IRTransform) -> DEFOrientation {
        let angle = ((Int(t.angle) % 360) + 360) % 360
        if t.mirrorX {
            switch angle {
            case 0: return .fn
            case 90: return .fe
            case 180: return .fs
            case 270: return .fw
            default: return .fn
            }
        } else {
            switch angle {
            case 0: return .n
            case 90: return .e
            case 180: return .s
            case 270: return .w
            default: return .n
            }
        }
    }
}
