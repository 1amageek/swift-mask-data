import CircuiteFoundation
import Foundation
import LayoutIR
import Testing

@testable import OASIS

/// Regression tests for OASIS reader/writer bug fixes.
@Suite("OASIS Bug Fix Regressions")
struct OASISBugFixTests {

  // MARK: - Bug 1: Rectangle W/H bit order

  @Test func testRectangleWHBitOrder() throws {
    // Non-square rectangle: w=100, h=200. If W/H bits are swapped,
    // the reader would produce w=200, h=100.
    let boundary = IRBoundary(
      layer: 1,
      datatype: 0,
      points: [
        IRPoint(x: 0, y: 0),
        IRPoint(x: 100, y: 0),
        IRPoint(x: 100, y: 200),
        IRPoint(x: 0, y: 200),
        IRPoint(x: 0, y: 0),
      ],
      properties: []
    )
    let lib = IRLibrary(
      name: "RECTWHTEST",
      databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
      cells: [IRCell(name: "R", elements: [.boundary(boundary)])]
    )
    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)

    #expect(result.cells.count == 1)
    #expect(result.cells[0].elements.count == 1)
    if case .boundary(let b) = result.cells[0].elements[0] {
      // Verify the rectangle corners match a 100-wide, 200-tall box
      #expect(b.points.count == 5)
      #expect(b.points[0] == IRPoint(x: 0, y: 0))
      #expect(b.points[1] == IRPoint(x: 100, y: 0))
      #expect(b.points[2] == IRPoint(x: 100, y: 200))
      #expect(b.points[3] == IRPoint(x: 0, y: 200))
      #expect(b.points[4] == IRPoint(x: 0, y: 0))
    } else {
      Issue.record("Expected boundary element")
    }
  }

  @Test func testNonSquareRectangleRoundTrip() throws {
    // Wide rectangle: w=500, h=100
    let boundary = IRBoundary(
      layer: 3,
      datatype: 1,
      points: [
        IRPoint(x: 10, y: 20),
        IRPoint(x: 510, y: 20),
        IRPoint(x: 510, y: 120),
        IRPoint(x: 10, y: 120),
        IRPoint(x: 10, y: 20),
      ],
      properties: []
    )
    let lib = IRLibrary(
      name: "WIDERECT",
      databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
      cells: [IRCell(name: "WR", elements: [.boundary(boundary)])]
    )
    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)

    if case .boundary(let b) = result.cells[0].elements[0] {
      #expect(b.layer == 3)
      #expect(b.datatype == 1)
      #expect(b.points.count == 5)
      // Check the width (x-extent) and height (y-extent)
      let xs = b.points[0...3].map(\.x)
      let ys = b.points[0...3].map(\.y)
      let width = (xs.max() ?? 0) - (xs.min() ?? 0)
      let height = (ys.max() ?? 0) - (ys.min() ?? 0)
      #expect(width == 500)
      #expect(height == 100)
    } else {
      Issue.record("Expected boundary element")
    }
  }

  // MARK: - Bug 2: Repetition reuse (type-0)

  @Test func testRepetitionReuse() throws {
    // Build OASIS data manually with two rectangles, the second using
    // repetition type-0 (reuse). This exercises the readRepetitionWithReuse
    // code path that previously double-read the type-0 byte.
    var w = OASISWriter()
    w.writeMagic()

    // START
    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)  // 1000 dbu/um
    w.writeUnsignedInteger(0)

    // CELLNAME
    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString("REPTEST")

    // CELL (by ref)
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(0)

    // First RECTANGLE with repetition (uniform row, 3 copies, spacing 100)
    w.writeByte(OASISRecordType.rectangle.rawValue)
    // info-byte: S(7)=0, W(6)=1, H(5)=1, X(4)=1, Y(3)=1, R(2)=1, D(1)=1, L(0)=1
    let firstInfoByte: UInt8 = 0b0111_1111
    w.writeByte(firstInfoByte)
    w.writeUnsignedInteger(1)  // L (layer)
    w.writeUnsignedInteger(0)  // D (datatype)
    w.writeUnsignedInteger(50)  // W
    w.writeUnsignedInteger(30)  // H
    w.writeSignedInteger(0)  // X
    w.writeSignedInteger(0)  // Y
    // Repetition: type 2 = uniform row, count=3, spacing=100
    w.writeUnsignedInteger(2)  // type 2
    w.writeUnsignedInteger(1)  // count - 2 = 1
    w.writeUnsignedInteger(100)  // spacing

    // Second RECTANGLE reusing previous repetition (type-0)
    w.writeByte(OASISRecordType.rectangle.rawValue)
    // info-byte: S(7)=0, W(6)=1, H(5)=1, X(4)=1, Y(3)=1, R(2)=1, D(1)=0, L(0)=0
    // Reuse layer/datatype from modal, set W, H, X, Y, R
    let secondInfoByte: UInt8 = 0b0111_1100
    w.writeByte(secondInfoByte)
    w.writeUnsignedInteger(60)  // W
    w.writeUnsignedInteger(40)  // H
    w.writeSignedInteger(0)  // X
    w.writeSignedInteger(200)  // Y
    // Repetition type-0: reuse previous (single byte 0x00)
    w.writeByte(0x00)

    // END
    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)

    let result = try OASISLibraryReader.read(w.data)
    #expect(result.cells.count == 1)
    #expect(result.cells[0].elements.count == 6)

    // Verify first rectangle repetition expands to three copies.
    if case .boundary(let b1) = result.cells[0].elements[0] {
      #expect(b1.layer == 1)
      let xs = b1.points[0...3].map(\.x)
      let ys = b1.points[0...3].map(\.y)
      #expect((xs.max() ?? 0) - (xs.min() ?? 0) == 50)
      #expect((ys.max() ?? 0) - (ys.min() ?? 0) == 30)
    } else {
      Issue.record("Expected boundary for first rectangle")
    }
    if case .boundary(let b1Copy) = result.cells[0].elements[2] {
      let xs = b1Copy.points[0...3].map(\.x)
      #expect(xs.min() == 200)
      #expect(xs.max() == 250)
    } else {
      Issue.record("Expected boundary for first rectangle copy")
    }

    // Verify second rectangle reuses the repetition and preserves dimensions.
    if case .boundary(let b2) = result.cells[0].elements[3] {
      let xs = b2.points[0...3].map(\.x)
      let ys = b2.points[0...3].map(\.y)
      #expect((xs.max() ?? 0) - (xs.min() ?? 0) == 60)
      #expect((ys.max() ?? 0) - (ys.min() ?? 0) == 40)
      #expect(ys.min() == 200)
    } else {
      Issue.record("Expected boundary for second rectangle")
    }
    if case .boundary(let b2Copy) = result.cells[0].elements[5] {
      let xs = b2Copy.points[0...3].map(\.x)
      let ys = b2Copy.points[0...3].map(\.y)
      #expect(xs.min() == 200)
      #expect(xs.max() == 260)
      #expect(ys.min() == 200)
    } else {
      Issue.record("Expected boundary for second rectangle copy")
    }
  }

  @Test func testReaderRejectsOverflowingUnsignedInteger() {
    var reader = OASISReader(data: Data(Array(repeating: UInt8(0x80), count: 10) + [0x00]))

    expectNumericOverflow(contextContains: "unsigned integer") {
      _ = try reader.readUnsignedInteger()
    }
  }

  @Test func testRectangleCoordinateOverflowThrowsTypedError() throws {
    let data = try makeOASISData(cellName: "RECT_OVERFLOW") { w in
      w.writeByte(OASISRecordType.rectangle.rawValue)
      let infoByte: UInt8 = 0b0111_1011
      w.writeByte(infoByte)
      w.writeUnsignedInteger(1)
      w.writeUnsignedInteger(0)
      w.writeUnsignedInteger(10)
      w.writeUnsignedInteger(10)
      w.writeSignedInteger(Int64(Int32.max) + 1)
      w.writeSignedInteger(0)
    }

    expectNumericOverflow(contextContains: "rectangle x") {
      _ = try OASISLibraryReader.read(data)
    }
  }

  @Test func testInitialRepetitionReuseWithoutPreviousRepetitionFails() throws {
    var w = OASISWriter()
    w.writeMagic()

    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)

    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString("BADREP")
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(0)

    w.writeByte(OASISRecordType.rectangle.rawValue)
    let infoByte: UInt8 = 0b0111_1111
    w.writeByte(infoByte)
    w.writeUnsignedInteger(1)
    w.writeUnsignedInteger(0)
    w.writeUnsignedInteger(50)
    w.writeUnsignedInteger(30)
    w.writeSignedInteger(0)
    w.writeSignedInteger(0)
    w.writeByte(0x00)

    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)

    #expect(throws: OASISError.self) {
      _ = try OASISLibraryReader.read(w.data)
    }
  }

  @Test func testRepetitionOffsetOverflowThrowsTypedError() throws {
    let data = try makeOASISData(cellName: "REP_OVERFLOW") { w in
      w.writeByte(OASISRecordType.rectangle.rawValue)
      let infoByte: UInt8 = 0b0111_1111
      w.writeByte(infoByte)
      w.writeUnsignedInteger(1)
      w.writeUnsignedInteger(0)
      w.writeUnsignedInteger(10)
      w.writeUnsignedInteger(10)
      w.writeSignedInteger(0)
      w.writeSignedInteger(0)
      w.writeUnsignedInteger(2)
      w.writeUnsignedInteger(0)
      w.writeUnsignedInteger(UInt64(Int32.max) + 1)
    }

    expectNumericOverflow(contextContains: "translated point") {
      _ = try OASISLibraryReader.read(data)
    }
  }

  @Test func testPointListDeltaOverflowThrowsTypedError() throws {
    let data = try makeOASISData(cellName: "POINT_OVERFLOW") { w in
      w.writeByte(OASISRecordType.polygon.rawValue)
      let infoByte: UInt8 = 0b0011_1011
      w.writeByte(infoByte)
      w.writeUnsignedInteger(1)
      w.writeUnsignedInteger(0)
      w.writeUnsignedInteger(4)
      w.writeUnsignedInteger(1)
      w.writeSignedInteger(Int64(Int32.max) + 1)
      w.writeSignedInteger(0)
      w.writeSignedInteger(0)
      w.writeSignedInteger(0)
    }

    expectNumericOverflow(contextContains: "general point-list dx") {
      _ = try OASISLibraryReader.read(data)
    }
  }

  @Test func testNameTableReferenceOverflowThrowsTypedError() throws {
    var w = OASISWriter()
    w.writeMagic()
    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)
    w.writeByte(OASISRecordType.cellnameRef.rawValue)
    w.writeUnsignedInteger(1_000_001)
    try w.writeAString("TOO_LARGE")

    expectNumericOverflow(contextContains: "cell-name reference") {
      _ = try OASISLibraryReader.read(w.data)
    }
  }

  @Test func testPropertyValueCountOverflowThrowsTypedError() throws {
    let data = try makeOASISData(cellName: "PROP_COUNT_OVERFLOW") { w in
      w.writeByte(OASISRecordType.rectangle.rawValue)
      let rectInfo: UInt8 = 0b0111_1011
      w.writeByte(rectInfo)
      w.writeUnsignedInteger(1)
      w.writeUnsignedInteger(0)
      w.writeUnsignedInteger(10)
      w.writeUnsignedInteger(10)
      w.writeSignedInteger(0)
      w.writeSignedInteger(0)

      w.writeByte(OASISRecordType.property.rawValue)
      let propInfo: UInt8 = 0xF4
      w.writeByte(propInfo)
      try w.writeAString("too_many_values")
      w.writeUnsignedInteger(1_000_001)
    }

    expectNumericOverflow(contextContains: "property value count") {
      _ = try OASISLibraryReader.read(data)
    }
  }

  @Test func testCTrapezoidPointOverflowThrowsTypedError() {
    expectNumericOverflow(contextContains: "ctrapezoid point") {
      _ = try ctrapezoidPoints(type: 16, x: Int32.max, y: 0, w: 1, h: 1)
    }
  }

  @Test func testCTrapezoidNegativeTypeThrowsTypedError() {
    expectNumericOverflow(contextContains: "ctrapezoid type") {
      _ = try ctrapezoidPoints(type: -1, x: 0, y: 0, w: 1, h: 1)
    }
  }

  // MARK: - Placement non-grid repetition expansion

  @Test func testPlacementNonGridRepetitionExpandsIntoIndividualPlacements() throws {
    // A PLACEMENT with a non-grid repetition (uniform row) must expand
    // into one cell reference per occurrence — only grid repetitions
    // have a compact IRArrayRef form. Dropping the repetition silently
    // lost every occurrence but the first.
    var w = OASISWriter()
    w.writeMagic()

    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)

    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString("UNIT")
    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString("PTOP")

    // UNIT: one rectangle so the cell exists with content.
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(0)
    w.writeByte(OASISRecordType.rectangle.rawValue)
    w.writeByte(0b0111_1111)
    w.writeUnsignedInteger(1)  // layer
    w.writeUnsignedInteger(0)  // datatype
    w.writeUnsignedInteger(10)  // W
    w.writeUnsignedInteger(10)  // H
    w.writeSignedInteger(0)
    w.writeSignedInteger(0)
    w.writeUnsignedInteger(2)  // repetition type 2 (uniform row)
    w.writeUnsignedInteger(0)  // count - 2 = 0 -> 2 copies
    w.writeUnsignedInteger(20)

    // PTOP: placement of UNIT with uniform-row repetition, 3 copies.
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(1)
    w.writeByte(OASISRecordType.placement.rawValue)
    // info: C(0x80) explicit cell, N(0x40) by reference, X(0x20),
    // Y(0x10), R(0x08) repetition.
    w.writeByte(0xF8)
    w.writeUnsignedInteger(0)  // cell-name ref -> UNIT
    w.writeSignedInteger(50)  // X
    w.writeSignedInteger(7)  // Y
    w.writeUnsignedInteger(2)  // repetition type 2 (uniform row)
    w.writeUnsignedInteger(1)  // count - 2 = 1 -> 3 copies
    w.writeUnsignedInteger(100)  // spacing

    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)

    let result = try OASISLibraryReader.read(w.data)
    let top = try #require(result.cell(named: "PTOP"))

    let refs = top.elements.compactMap { element -> IRCellRef? in
      if case .cellRef(let ref) = element { return ref }
      return nil
    }
    #expect(refs.count == 3, "all repeated placements must survive reading")
    #expect(refs.allSatisfy { $0.cellName == "UNIT" })
    #expect(refs.map(\.origin.x).sorted() == [50, 150, 250])
    #expect(refs.allSatisfy { $0.origin.y == 7 })
  }

  // MARK: - Bug 3: Array placement field order

  @Test func testArrayPlacementFieldOrder() throws {
    let child = IRCell(
      name: "UNIT",
      elements: [
        .boundary(
          IRBoundary(
            layer: 1, datatype: 0,
            points: [
              IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0),
              IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 10),
              IRPoint(x: 0, y: 0),
            ],
            properties: []
          ))
      ])
    let arrayRef = IRArrayRef(
      cellName: "UNIT",
      transform: .identity,
      columns: 4,
      rows: 3,
      referencePoints: [
        IRPoint(x: 100, y: 200),  // origin
        IRPoint(x: 100 + 4 * 50, y: 200),  // column vector end
        IRPoint(x: 100, y: 200 + 3 * 80),  // row vector end
      ],
      properties: []
    )
    let parent = IRCell(name: "ARRAY_TOP", elements: [.arrayRef(arrayRef)])
    let lib = IRLibrary(
      name: "AREFTEST",
      databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
      cells: [child, parent]
    )
    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)

    // Find the ARRAY_TOP cell
    let topCell = result.cell(named: "ARRAY_TOP")
    #expect(topCell != nil)
    guard let top = topCell else { return }
    #expect(top.elements.count == 1)

    if case .arrayRef(let aref) = top.elements[0] {
      #expect(aref.cellName == "UNIT")
      #expect(aref.columns == 4)
      #expect(aref.rows == 3)
      #expect(aref.referencePoints.count == 3)
      #expect(aref.referencePoints[0] == IRPoint(x: 100, y: 200))
    } else {
      Issue.record("Expected arrayRef element, got \(top.elements[0])")
    }
  }

  @Test func testOneColumnArrayPlacementDoesNotTrap() throws {
    let child = IRCell(name: "UNIT", elements: [])
    let arrayRef = IRArrayRef(
      cellName: "UNIT",
      transform: .identity,
      columns: 1,
      rows: 2,
      referencePoints: [
        IRPoint(x: 10, y: 20),
        IRPoint(x: 10, y: 20),
        IRPoint(x: 10, y: 120),
      ],
      properties: []
    )
    let parent = IRCell(name: "ARRAY_TOP", elements: [.arrayRef(arrayRef)])
    let lib = IRLibrary(name: "ONECOL", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000), cells: [child, parent])

    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)
    let top = try #require(result.cell(named: "ARRAY_TOP"))
    let refs = top.elements.compactMap { element -> IRCellRef? in
      if case .cellRef(let ref) = element { return ref }
      return nil
    }
    #expect(refs.count == 2)
    #expect(refs.map(\.origin.y).sorted() == [20, 70])
    #expect(refs.allSatisfy { $0.origin.x == 10 })
  }

  @Test func testOneRowArrayPlacementDoesNotTrap() throws {
    let child = IRCell(name: "UNIT", elements: [])
    let arrayRef = IRArrayRef(
      cellName: "UNIT",
      transform: .identity,
      columns: 2,
      rows: 1,
      referencePoints: [
        IRPoint(x: 10, y: 20),
        IRPoint(x: 110, y: 20),
        IRPoint(x: 10, y: 20),
      ],
      properties: []
    )
    let parent = IRCell(name: "ARRAY_TOP", elements: [.arrayRef(arrayRef)])
    let lib = IRLibrary(name: "ONEROW", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000), cells: [child, parent])

    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)
    let top = try #require(result.cell(named: "ARRAY_TOP"))
    let refs = top.elements.compactMap { element -> IRCellRef? in
      if case .cellRef(let ref) = element { return ref }
      return nil
    }
    #expect(refs.count == 2)
    #expect(refs.map(\.origin.x).sorted() == [10, 60])
    #expect(refs.allSatisfy { $0.origin.y == 20 })
  }

  @Test func testOneRowArrayPlacementPreservesTransform() throws {
    let child = IRCell(name: "UNIT", elements: [])
    let arrayRef = IRArrayRef(
      cellName: "UNIT",
      transform: IRTransform(mirrorX: false, magnification: 1.0, angle: 90.0),
      columns: 2,
      rows: 1,
      referencePoints: [
        IRPoint(x: 10, y: 20),
        IRPoint(x: 110, y: 20),
        IRPoint(x: 10, y: 20),
      ],
      properties: []
    )
    let parent = IRCell(name: "ARRAY_TOP", elements: [.arrayRef(arrayRef)])
    let lib = IRLibrary(name: "ONEROW_TRANSFORM", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000), cells: [child, parent])

    let data = try OASISLibraryWriter.write(lib)
    let result = try OASISLibraryReader.read(data)
    let top = try #require(result.cell(named: "ARRAY_TOP"))
    let refs = top.elements.compactMap { element -> IRCellRef? in
      if case .cellRef(let ref) = element { return ref }
      return nil
    }
    #expect(refs.count == 2)
    #expect(refs.map(\.origin.x).sorted() == [10, 60])
    #expect(refs.allSatisfy { $0.origin.y == 20 })
    #expect(refs.allSatisfy { $0.transform.angle == 90.0 })
    #expect(refs.allSatisfy { $0.transform.magnification == 1.0 })
    #expect(refs.allSatisfy { !$0.transform.mirrorX })
  }

  // MARK: - Bug 4: Property value count

  @Test func testPropertyValueCount() throws {
    // Build OASIS data manually with a property record containing 3 values.
    // The property info-byte encodes the value count in the lower bits.
    // This verifies the count is not truncated by the extra & 0x07 mask.
    var w = OASISWriter()
    w.writeMagic()

    // START
    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)

    // CELLNAME
    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString("PROPTEST")

    // CELL (by ref)
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(0)

    // RECTANGLE (simple, as a target for the property)
    w.writeByte(OASISRecordType.rectangle.rawValue)
    // info-byte: W, H, X, Y, D, L set
    let rectInfo: UInt8 = 0b0111_1011
    w.writeByte(rectInfo)
    w.writeUnsignedInteger(1)  // L
    w.writeUnsignedInteger(0)  // D
    w.writeUnsignedInteger(100)  // W
    w.writeUnsignedInteger(100)  // H
    w.writeSignedInteger(0)  // X
    w.writeSignedInteger(0)  // Y

    // PROPERTY record with 3 string values
    // OASIS spec info-byte layout: UUUU(7:4) V(3) C(2) T(1) S(0)
    // UUUU=0011 (3 values), V=0 (values in stream), C=1 (name present), T=0 (inline), S=0
    // Bits: 0011(7:4) 0(3) 1(2) 0(1) 0(0) = 0b0011_0100 = 0x34
    let propInfoByte: UInt8 = 0x34
    w.writeByte(OASISRecordType.property.rawValue)
    w.writeByte(propInfoByte)
    try w.writeAString("test_prop")  // inline property name
    // 3 property values (type 3 = a-string)
    try w.writePropertyValue(.aString("alpha"))
    try w.writePropertyValue(.aString("beta"))
    try w.writePropertyValue(.aString("gamma"))

    // END
    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)

    let result = try OASISLibraryReader.read(w.data)
    #expect(result.cells.count == 1)
    #expect(result.cells[0].elements.count == 1)

    if case .boundary(let b) = result.cells[0].elements[0] {
      // The property should be attached with all 3 values
      #expect(b.properties.count == 1)
      let prop = b.properties[0]
      #expect(prop.value.contains("test_prop"))
      #expect(prop.value.contains("alpha"))
      #expect(prop.value.contains("beta"))
      #expect(prop.value.contains("gamma"))
    } else {
      Issue.record("Expected boundary element with property")
    }
  }

  @Test func cellReferenceToMissingNameFailsClosed() throws {
    var w = OASISWriter()
    w.writeMagic()
    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(9)
    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)

    do {
      _ = try OASISLibraryReader.read(w.data)
      Issue.record("Expected unresolvedReference")
    } catch OASISError.unresolvedReference(let context, let refNum) {
      #expect(context == "cell reference")
      #expect(refNum == 9)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func textStringReferenceToMissingNameFailsClosed() throws {
    let data = try makeOASISData(cellName: "TOP") { w in
      w.writeByte(OASISRecordType.text.rawValue)
      w.writeByte(0b0111_1011)
      w.writeUnsignedInteger(7)
      w.writeUnsignedInteger(1)
      w.writeUnsignedInteger(0)
      w.writeSignedInteger(0)
      w.writeSignedInteger(0)
    }

    do {
      _ = try OASISLibraryReader.read(data)
      Issue.record("Expected unresolvedReference")
    } catch OASISError.unresolvedReference(let context, let refNum) {
      #expect(context == "text-string reference")
      #expect(refNum == 7)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  private func makeOASISData(
    cellName: String,
    body: (inout OASISWriter) throws -> Void
  ) throws -> Data {
    var w = OASISWriter()
    w.writeMagic()
    w.writeByte(OASISRecordType.start.rawValue)
    try w.writeAString("1.0")
    w.writeReal(0.001)
    w.writeUnsignedInteger(0)
    w.writeByte(OASISRecordType.cellname.rawValue)
    try w.writeAString(cellName)
    w.writeByte(OASISRecordType.cellRef.rawValue)
    w.writeUnsignedInteger(0)
    try body(&w)
    w.writeByte(OASISRecordType.end.rawValue)
    try w.writeAString("")
    w.writeUnsignedInteger(0)
    return w.data
  }

  private func expectNumericOverflow(
    contextContains expectedContext: String,
    operation: () throws -> Void
  ) {
    do {
      try operation()
      Issue.record("Expected numeric overflow")
    } catch OASISError.numericOverflow(let context, _) {
      #expect(context.contains(expectedContext))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }
}
