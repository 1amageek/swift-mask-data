import Foundation
import LayoutIR

/// Converts an IRLibrary to GDSII binary data.
public enum GDSLibraryWriter {

    public static func write(_ library: IRLibrary) throws -> Data {
        var w = GDSRecordWriter()

        // HEADER
        try w.checkedWriteInt16(.header, values: [600])

        // BGNLIB (creation + modification timestamps, 12 int16s)
        let createdAt = library.createdAt ?? currentTimestamp()
        let modifiedAt = library.modifiedAt ?? createdAt
        try w.checkedWriteInt16(.bgnlib, values: createdAt.gdsValues + modifiedAt.gdsValues)

        // LIBNAME
        try w.writeString(.libname, value: library.name)

        // UNITS: userUnitsPerDBU, metersPerDBU
        try w.checkedWriteReal8(.units, values: [
            library.units.userUnitsPerDBU,
            library.units.metersPerDBU,
        ])

        // Structures (cells)
        for cell in library.cells {
            try writeCell(&w, cell)
        }

        // ENDLIB
        try w.checkedWriteNoData(.endlib)

        return w.data
    }

    // MARK: - Cell

    private static func writeCell(_ w: inout GDSRecordWriter, _ cell: IRCell) throws {
        let createdAt = cell.createdAt ?? currentTimestamp()
        let modifiedAt = cell.modifiedAt ?? createdAt
        try w.checkedWriteInt16(.bgnstr, values: createdAt.gdsValues + modifiedAt.gdsValues)
        try w.writeString(.strname, value: cell.name)

        for element in cell.elements {
            try writeElement(&w, element)
        }

        try w.checkedWriteNoData(.endstr)
    }

    // MARK: - Elements

    private static func writeElement(_ w: inout GDSRecordWriter, _ element: IRElement) throws {
        switch element {
        case .boundary(let b):
            try writeBoundary(&w, b)
        case .path(let p):
            try writePath(&w, p)
        case .cellRef(let r):
            try writeCellRef(&w, r)
        case .arrayRef(let a):
            try writeArrayRef(&w, a)
        case .text(let t):
            try writeText(&w, t)
        }
    }

    private static func writeBoundary(_ w: inout GDSRecordWriter, _ b: IRBoundary) throws {
        try w.checkedWriteNoData(.boundary)
        try w.checkedWriteInt16(.layer, values: [b.layer])
        try w.checkedWriteInt16(.datatype, values: [b.datatype])
        try w.checkedWriteXY(b.points)
        try writeProperties(&w, b.properties)
        try w.checkedWriteNoData(.endel)
    }

    private static func writePath(_ w: inout GDSRecordWriter, _ p: IRPath) throws {
        try w.checkedWriteNoData(.path)
        try w.checkedWriteInt16(.layer, values: [p.layer])
        try w.checkedWriteInt16(.datatype, values: [p.datatype])
        if p.pathType != .flush {
            try w.checkedWriteInt16(.pathtype, values: [p.pathType.rawValue])
        }
        if p.width != 0 {
            try w.checkedWriteInt32(.width, values: [p.width])
        }
        if let bext = p.beginExtension {
            try w.checkedWriteInt32(.bgnextn, values: [bext])
        }
        if let eext = p.endExtension {
            try w.checkedWriteInt32(.endextn, values: [eext])
        }
        try w.checkedWriteXY(p.points)
        try writeProperties(&w, p.properties)
        try w.checkedWriteNoData(.endel)
    }

    private static func writeCellRef(_ w: inout GDSRecordWriter, _ r: IRCellRef) throws {
        try w.checkedWriteNoData(.sref)
        try w.writeString(.sname, value: r.cellName)
        try writeTransform(&w, r.transform)
        try w.checkedWriteXY([r.origin])
        try writeProperties(&w, r.properties)
        try w.checkedWriteNoData(.endel)
    }

    private static func writeArrayRef(_ w: inout GDSRecordWriter, _ a: IRArrayRef) throws {
        try w.checkedWriteNoData(.aref)
        try w.writeString(.sname, value: a.cellName)
        try writeTransform(&w, a.transform)
        try w.checkedWriteInt16(.colrow, values: [a.columns, a.rows])
        try w.checkedWriteXY(a.referencePoints)
        try writeProperties(&w, a.properties)
        try w.checkedWriteNoData(.endel)
    }

    private static func writeText(_ w: inout GDSRecordWriter, _ t: IRText) throws {
        try w.checkedWriteNoData(.text)
        try w.checkedWriteInt16(.layer, values: [t.layer])
        try w.checkedWriteInt16(.texttype, values: [t.texttype])
        try writeTransform(&w, t.transform)
        try w.checkedWriteXY([t.position])
        try w.writeString(.string, value: t.string)
        try writeProperties(&w, t.properties)
        try w.checkedWriteNoData(.endel)
    }

    // MARK: - Transform

    private static func writeTransform(_ w: inout GDSRecordWriter, _ t: IRTransform) throws {
        let hasTransform = t.mirrorX || t.magnification != 1.0 || t.angle != 0.0
        guard hasTransform else { return }

        var bits: UInt16 = 0
        if t.mirrorX { bits |= 0x8000 }
        try w.checkedWriteBitArray(.strans, value: bits)

        if t.magnification != 1.0 {
            try w.checkedWriteReal8(.mag, values: [t.magnification])
        }
        if t.angle != 0.0 {
            try w.checkedWriteReal8(.angle, values: [t.angle])
        }
    }

    // MARK: - Properties

    private static func writeProperties(_ w: inout GDSRecordWriter, _ props: [IRProperty]) throws {
        for prop in props {
            try w.checkedWriteInt16(.propattr, values: [prop.attribute])
            try w.writeString(.propvalue, value: prop.value)
        }
    }

    // MARK: - Timestamp

    private static func currentTimestamp() -> IRDateTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return IRDateTime(
            year: Int16(components.year ?? 0),
            month: Int16(components.month ?? 0),
            day: Int16(components.day ?? 0),
            hour: Int16(components.hour ?? 0),
            minute: Int16(components.minute ?? 0),
            second: Int16(components.second ?? 0)
        )
    }
}
