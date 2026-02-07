import Testing
import Foundation
import LayoutIR
@testable import LEF

// MARK: - SITE Tests

@Suite("LEF SITE")
struct LEFSiteTests {

    @Test func siteReadWrite() throws {
        let lef = """
        VERSION 5.8 ;
        SITE CoreSite
          CLASS CORE ;
          SYMMETRY Y ;
          SIZE 0.2 BY 1.8 ;
        END CoreSite
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.sites.count == 1)
        let site = doc.sites[0]
        #expect(site.name == "CoreSite")
        #expect(site.siteClass == .core)
        #expect(site.symmetry == [.y])
        #expect(site.width == 0.2)
        #expect(site.height == 1.8)

        let data = try LEFLibraryWriter.write(doc)
        let roundTrip = try LEFLibraryReader.read(data)
        #expect(roundTrip.sites.count == 1)
        #expect(roundTrip.sites[0] == site)
    }

    @Test func sitePad() throws {
        let lef = """
        VERSION 5.8 ;
        SITE PadSite
          CLASS PAD ;
          SIZE 50 BY 200 ;
        END PadSite
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.sites[0].siteClass == .pad)
        #expect(doc.sites[0].width == 50)
    }
}

// MARK: - PROPERTY Tests

@Suite("LEF PROPERTY")
struct LEFPropertyTests {

    @Test func macroProperty() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          CLASS CORE ;
          PROPERTY LEF58_ABUTMENT "NONE" ;
          PROPERTY DriveStrength 4 ;
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let macro = doc.macros[0]
        #expect(macro.properties.count == 2)
        #expect(macro.properties[0].key == "LEF58_ABUTMENT")
        #expect(macro.properties[0].value == "NONE")
        #expect(macro.properties[1].key == "DriveStrength")
        #expect(macro.properties[1].value == "4")
    }

    @Test func propertyRoundTrip() throws {
        let doc = LEFDocument(
            macros: [LEFMacroDef(name: "BUF",
                                 properties: [LEFProperty(key: "cellType", value: "buffer")])]
        )
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        #expect(result.macros[0].properties.count == 1)
        #expect(result.macros[0].properties[0].key == "cellType")
        #expect(result.macros[0].properties[0].value == "buffer")
    }
}

// MARK: - FOREIGN / ORIGIN Tests

@Suite("LEF FOREIGN/ORIGIN")
struct LEFForeignOriginTests {

    @Test func foreignWithPoint() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          FOREIGN INV_phys 0.5 1.0 ;
          ORIGIN 0 0 ;
          SIZE 1.4 BY 2.8 ;
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let macro = doc.macros[0]
        #expect(macro.foreign?.cellName == "INV_phys")
        #expect(macro.foreign?.point?.x == 0.5)
        #expect(macro.foreign?.point?.y == 1.0)
        #expect(macro.origin?.x == 0)
        #expect(macro.origin?.y == 0)
    }

    @Test func foreignRoundTrip() throws {
        let doc = LEFDocument(
            macros: [LEFMacroDef(name: "BUF",
                                 foreign: LEFForeign(cellName: "BUF_ext", point: LEFPoint(x: 1, y: 2)),
                                 site: "CoreSite")]
        )
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        #expect(result.macros[0].foreign?.cellName == "BUF_ext")
        #expect(result.macros[0].foreign?.point?.x == 1.0)
        #expect(result.macros[0].site == "CoreSite")
    }
}

// MARK: - SPACINGTABLE Tests

@Suite("LEF SPACINGTABLE")
struct LEFSpacingTableTests {

    @Test func spacingTableParse() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          SPACINGTABLE
            PARALLELRUNLENGTH 0 0.5 1.0 ;
            WIDTH 0.14 0.14 0.16 0.18 ;
            WIDTH 0.28 0.16 0.18 0.20 ;
        END metal1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let layer = doc.layers[0]
        #expect(layer.spacingTable != nil)
        let tbl = layer.spacingTable!
        #expect(tbl.parallelRunLengths == [0, 0.5, 1.0])
        #expect(tbl.widthEntries.count == 2)
        #expect(tbl.widthEntries[0].width == 0.14)
        #expect(tbl.widthEntries[0].spacings == [0.14, 0.16, 0.18])
        #expect(tbl.widthEntries[1].width == 0.28)
        #expect(tbl.widthEntries[1].spacings == [0.16, 0.18, 0.20])
    }

    @Test func spacingTableRoundTrip() throws {
        let tbl = LEFSpacingTable(
            parallelRunLengths: [0, 0.25, 0.5],
            widthEntries: [
                LEFSpacingTable.WidthEntry(width: 0.1, spacings: [0.1, 0.12, 0.14]),
            ]
        )
        let doc = LEFDocument(layers: [LEFLayerDef(name: "m1", type: .routing, spacingTable: tbl)])
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        let resultTbl = result.layers[0].spacingTable!
        #expect(resultTbl.parallelRunLengths == [0, 0.25, 0.5])
        #expect(resultTbl.widthEntries[0].width == 0.1)
        #expect(resultTbl.widthEntries[0].spacings == [0.1, 0.12, 0.14])
    }
}

// MARK: - POLYGON Geometry Tests

@Suite("LEF POLYGON")
struct LEFPolygonTests {

    @Test func portPolygon() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          PIN A
            PORT
              LAYER metal1 ;
                POLYGON 0 0 1.0 0 1.0 0.5 0.5 1.0 0 1.0 0 0 ;
            END
          END A
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let port = doc.macros[0].pins[0].ports[0]
        #expect(port.layerName == "metal1")
        #expect(port.polygons.count == 1)
        #expect(port.polygons[0].count == 6)
        #expect(port.polygons[0][0] == LEFPoint(x: 0, y: 0))
        #expect(port.polygons[0][2] == LEFPoint(x: 1.0, y: 0.5))
    }

    @Test func obsPolygon() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          OBS
            LAYER metal1 ;
              POLYGON 0 0 1 0 1 1 0 1 ;
              RECT 2.0 2.0 3.0 3.0 ;
          END
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let obs = doc.macros[0].obs[0]
        #expect(obs.polygons.count == 1)
        #expect(obs.rects.count == 1)
    }

    @Test func polygonRoundTrip() throws {
        let poly = [LEFPoint(x: 0, y: 0), LEFPoint(x: 1, y: 0),
                    LEFPoint(x: 1, y: 1), LEFPoint(x: 0, y: 1)]
        let doc = LEFDocument(
            macros: [LEFMacroDef(name: "INV", pins: [
                LEFPinDef(name: "A", ports: [
                    LEFPort(layerName: "metal1", rects: [], polygons: [poly])
                ])
            ])]
        )
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        let resultPoly = result.macros[0].pins[0].ports[0].polygons[0]
        #expect(resultPoly.count == 4)
        #expect(resultPoly[0] == LEFPoint(x: 0, y: 0))
        #expect(resultPoly[3] == LEFPoint(x: 0, y: 1))
    }

    @Test func polygonIRConversion() {
        let poly = [LEFPoint(x: 0, y: 0), LEFPoint(x: 0.5, y: 0),
                    LEFPoint(x: 0.5, y: 0.5), LEFPoint(x: 0, y: 0.5)]
        let doc = LEFDocument(
            dbuPerMicron: 1000,
            layers: [LEFLayerDef(name: "metal1", type: .routing)],
            macros: [LEFMacroDef(name: "INV", pins: [
                LEFPinDef(name: "A", ports: [
                    LEFPort(layerName: "metal1", rects: [], polygons: [poly])
                ])
            ])]
        )
        let lib = LEFIRConverter.toIRLibrary(doc)
        let elements = lib.cells[0].elements
        // 1 boundary (polygon) + 1 text label
        #expect(elements.count == 2)
        if case .boundary(let b) = elements[0] {
            #expect(b.points.count == 5) // closed polygon
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[1] == IRPoint(x: 500, y: 0))
        }
    }
}

// MARK: - Layer Extended Fields Tests

@Suite("LEF Layer Extended Fields")
struct LEFLayerExtendedTests {

    @Test func resistanceCapacitance() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          DIRECTION HORIZONTAL ;
          RESISTANCE RPERSQ 0.08 ;
          CAPACITANCE CPERSQDIST 0.000035 ;
          EDGECAPACITANCE 0.00005 ;
          THICKNESS 0.36 ;
        END metal1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let l = doc.layers[0]
        #expect(l.resistance == 0.08)
        #expect(l.capacitance == 0.000035)
        #expect(l.edgeCapacitance == 0.00005)
        #expect(l.thickness == 0.36)
    }

    @Test func minwidthMaxwidthArea() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          MINWIDTH 0.06 ;
          MAXWIDTH 10.0 ;
          AREA 0.014 ;
        END metal1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let l = doc.layers[0]
        #expect(l.minwidth == 0.06)
        #expect(l.maxwidth == 10.0)
        #expect(l.area == 0.014)
    }

    @Test func enclosure() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER via1
          TYPE CUT ;
          ENCLOSURE 0.05 0.08 ;
        END via1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let l = doc.layers[0]
        #expect(l.enclosure?.overhang1 == 0.05)
        #expect(l.enclosure?.overhang2 == 0.08)
    }

    @Test func layerExtendedRoundTrip() throws {
        let doc = LEFDocument(layers: [
            LEFLayerDef(name: "m1", type: .routing, resistance: 0.1,
                       capacitance: 0.00003, thickness: 0.4, minwidth: 0.05)
        ])
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        let l = result.layers[0]
        #expect(l.resistance == 0.1)
        #expect(l.capacitance == 0.00003)
        #expect(l.thickness == 0.4)
        #expect(l.minwidth == 0.05)
    }
}

// MARK: - VIA Extended Fields Tests

@Suite("LEF VIA Extended Fields")
struct LEFViaExtendedTests {

    @Test func viaDefault() throws {
        let lef = """
        VERSION 5.8 ;
        VIA via1_def DEFAULT ;
          LAYER metal1 ;
            RECT -0.07 -0.07 0.07 0.07 ;
          LAYER via1 ;
            RECT -0.07 -0.07 0.07 0.07 ;
        END via1_def
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.vias[0].isDefault == true)
    }

    @Test func viaGenerate() throws {
        let lef = """
        VERSION 5.8 ;
        VIA via1_gen GENERATE ;
          VIARULE viaRule1 ;
          CUTSIZE 0.15 0.15 ;
          CUTSPACING 0.2 0.2 ;
          ENCLOSURE 0.05 0.08 0.05 0.08 ;
          ROWCOL 2 3 ;
          LAYER metal1 ;
          LAYER via1 ;
          LAYER metal2 ;
        END via1_gen
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let via = doc.vias[0]
        #expect(via.isGenerate == true)
        #expect(via.viaRule == "viaRule1")
        #expect(via.cutSize?.0 == 0.15)
        #expect(via.cutSize?.1 == 0.15)
        #expect(via.cutSpacing?.0 == 0.2)
        #expect(via.cutSpacing?.1 == 0.2)
        #expect(via.enclosure?.0 == 0.05)
        #expect(via.enclosure?.1 == 0.08)
        #expect(via.rowCol?.0 == 2)
        #expect(via.rowCol?.1 == 3)
    }

    @Test func viaExtendedRoundTrip() throws {
        let doc = LEFDocument(vias: [
            LEFViaDef(name: "v1", layers: [], isDefault: true,
                     isGenerate: true, viaRule: "rule1",
                     cutSize: (0.1, 0.1), cutSpacing: (0.2, 0.2),
                     rowCol: (3, 4))
        ])
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        let via = result.vias[0]
        #expect(via.isDefault == true)
        #expect(via.isGenerate == true)
        #expect(via.viaRule == "rule1")
        #expect(via.cutSize?.0 == 0.1)
        #expect(via.rowCol?.0 == 3)
    }
}

// MARK: - PIN Extended Fields Tests

@Suite("LEF PIN Extended Fields")
struct LEFPinExtendedTests {

    @Test func pinShape() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          PIN A
            DIRECTION INPUT ;
            SHAPE ABUTMENT ;
            ANTENNADIFFAREA 0.5 ;
            ANTENNAGATEAREA 0.3 ;
            PORT
              LAYER metal1 ;
                RECT 0 0 0.14 0.28 ;
            END
          END A
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let pin = doc.macros[0].pins[0]
        #expect(pin.shape == .abutment)
        #expect(pin.antennaDiffArea == 0.5)
        #expect(pin.antennaGateArea == 0.3)
    }

    @Test func pinShapeRoundTrip() throws {
        let doc = LEFDocument(
            macros: [LEFMacroDef(name: "INV", pins: [
                LEFPinDef(name: "A", shape: .ring,
                          antennaDiffArea: 1.5, antennaGateArea: 0.8)
            ])]
        )
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        let pin = result.macros[0].pins[0]
        #expect(pin.shape == .ring)
        #expect(pin.antennaDiffArea == 1.5)
        #expect(pin.antennaGateArea == 0.8)
    }
}

// MARK: - MACRO Extended Fields Tests

@Suite("LEF MACRO Extended Fields")
struct LEFMacroExtendedTests {

    @Test func macroSubClass() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO TIEH
          CLASS CORE TIEHIGH ;
          SIZE 0.4 BY 1.8 ;
        END TIEH
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let macro = doc.macros[0]
        #expect(macro.macroClass == .core)
        #expect(macro.subClass == "TIEHIGH")
    }

    @Test func fixedMask() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          FIXEDMASK ;
          SIZE 1.0 BY 2.0 ;
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.macros[0].fixedMask == true)
    }

    @Test func macroSiteRef() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          CLASS CORE ;
          SITE CoreSite ;
          SIZE 1.0 BY 2.0 ;
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.macros[0].site == "CoreSite")
    }

    @Test func busbitAndDivider() throws {
        let lef = """
        VERSION 5.8 ;
        BUSBITCHARS "[]" ;
        DIVIDERCHAR "/" ;
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.busbitChars == "[]")
        #expect(doc.dividerChar == "/")

        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)
        #expect(result.busbitChars == "[]")
        #expect(result.dividerChar == "/")
    }

    @Test func fullMacroRoundTrip() throws {
        let doc = LEFDocument(
            macros: [LEFMacroDef(
                name: "NAND2", macroClass: .core, subClass: "TIEHIGH",
                width: 1.4, height: 2.8,
                symmetry: [.x, .y],
                pins: [
                    LEFPinDef(name: "A", direction: .input, use: .signal, shape: .abutment,
                              ports: [LEFPort(layerName: "metal1",
                                             rects: [LEFRect(x1: 0, y1: 0, x2: 0.14, y2: 0.28)])],
                              antennaDiffArea: 0.5),
                    LEFPinDef(name: "VDD", direction: .inout_, use: .power,
                              ports: [LEFPort(layerName: "metal1",
                                             rects: [LEFRect(x1: 0, y1: 2.4, x2: 1.4, y2: 2.8)])]),
                ],
                obs: [LEFPort(layerName: "metal1",
                              rects: [LEFRect(x1: 0.1, y1: 0.1, x2: 0.9, y2: 1.9)])],
                origin: LEFPoint(x: 0, y: 0),
                foreign: LEFForeign(cellName: "NAND2_phys"),
                site: "core_site", fixedMask: true,
                properties: [LEFProperty(key: "strength", value: "2")]
            )],
            sites: [LEFSiteDef(name: "core_site", siteClass: .core,
                              symmetry: [.y], width: 0.2, height: 1.8)]
        )
        let data = try LEFLibraryWriter.write(doc)
        let result = try LEFLibraryReader.read(data)

        #expect(result.sites.count == 1)
        #expect(result.sites[0].name == "core_site")

        let macro = result.macros[0]
        #expect(macro.name == "NAND2")
        #expect(macro.macroClass == LEFMacroDef.MacroClass.core)
        #expect(macro.subClass == "TIEHIGH")
        #expect(macro.width == 1.4)
        #expect(macro.height == 2.8)
        #expect(macro.symmetry == [LEFMacroDef.Symmetry.x, LEFMacroDef.Symmetry.y])
        #expect(macro.origin?.x == 0)
        #expect(macro.foreign?.cellName == "NAND2_phys")
        #expect(macro.site == "core_site")
        #expect(macro.fixedMask == true)
        #expect(macro.properties.count == 1)
        #expect(macro.pins.count == 2)
        #expect(macro.pins[0].shape == LEFPinDef.PinShape.abutment)
        #expect(macro.pins[0].antennaDiffArea == 0.5)
        #expect(macro.obs.count == 1)
    }
}

// MARK: - KLayout LEF Output Compatibility

@Suite("LEF KLayout Compatibility")
struct LEFKLayoutCompatTests {

    @Test func klayoutTypicalOutput() throws {
        // Simulates a LEF file as KLayout would produce it
        let lef = """
        VERSION 5.8 ;
        BUSBITCHARS "[]" ;
        DIVIDERCHAR "/" ;
        UNITS
          DATABASE MICRONS 1000 ;
        END UNITS
        SITE unit
          CLASS CORE ;
          SYMMETRY Y ;
          SIZE 0.19 BY 1.4 ;
        END unit
        LAYER poly
          TYPE MASTERSLICE ;
        END poly
        LAYER metal1
          TYPE ROUTING ;
          DIRECTION HORIZONTAL ;
          PITCH 0.34 ;
          WIDTH 0.16 ;
          SPACING 0.14 ;
          OFFSET 0.17 ;
          RESISTANCE RPERSQ 0.38 ;
          CAPACITANCE CPERSQDIST 0.000104 ;
          THICKNESS 0.36 ;
          MINWIDTH 0.16 ;
          AREA 0.064 ;
        END metal1
        LAYER via1
          TYPE CUT ;
          SPACING 0.26 ;
          ENCLOSURE 0.05 0.06 ;
        END via1
        VIA M1_M2 DEFAULT ;
          LAYER metal1 ;
            RECT -0.08 -0.08 0.08 0.08 ;
          LAYER via1 ;
            RECT -0.07 -0.07 0.07 0.07 ;
          LAYER metal2 ;
            RECT -0.08 -0.08 0.08 0.08 ;
        END M1_M2
        MACRO INV
          CLASS CORE ;
          FOREIGN INV 0 0 ;
          ORIGIN 0 0 ;
          SIZE 0.76 BY 1.4 ;
          SYMMETRY X Y ;
          SITE unit ;
          PIN A
            DIRECTION INPUT ;
            USE SIGNAL ;
            SHAPE ABUTMENT ;
            ANTENNADIFFAREA 0.0456 ;
            ANTENNAGATEAREA 0.0228 ;
            PORT
              LAYER metal1 ;
                RECT 0.04 0.525 0.3 0.875 ;
            END
          END A
          PIN Y
            DIRECTION OUTPUT ;
            USE SIGNAL ;
            PORT
              LAYER metal1 ;
                RECT 0.46 0.35 0.72 1.05 ;
            END
          END Y
          PIN VDD
            DIRECTION INOUT ;
            USE POWER ;
            PORT
              LAYER metal1 ;
                RECT 0 1.24 0.76 1.4 ;
            END
          END VDD
          PIN VSS
            DIRECTION INOUT ;
            USE GROUND ;
            PORT
              LAYER metal1 ;
                RECT 0 0 0.76 0.16 ;
            END
          END VSS
          OBS
            LAYER metal1 ;
              RECT 0.04 0.16 0.72 0.35 ;
              RECT 0.04 1.05 0.72 1.24 ;
          END
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))

        #expect(doc.busbitChars == "[]")
        #expect(doc.dividerChar == "/")
        #expect(doc.dbuPerMicron == 1000)
        #expect(doc.sites.count == 1)
        #expect(doc.layers.count == 3)
        #expect(doc.vias.count == 1)
        #expect(doc.macros.count == 1)

        let m1 = doc.layers[1]
        #expect(m1.name == "metal1")
        #expect(m1.resistance == 0.38)
        #expect(m1.capacitance == 0.000104)
        #expect(m1.thickness == 0.36)
        #expect(m1.minwidth == 0.16)
        #expect(m1.area == 0.064)
        #expect(m1.offset == 0.17)

        let v1 = doc.layers[2]
        #expect(v1.enclosure?.overhang1 == 0.05)
        #expect(v1.enclosure?.overhang2 == 0.06)

        let via = doc.vias[0]
        #expect(via.isDefault == true)
        #expect(via.layers.count == 3)

        let inv = doc.macros[0]
        #expect(inv.foreign?.cellName == "INV")
        #expect(inv.origin?.x == 0)
        #expect(inv.site == "unit")
        #expect(inv.pins.count == 4)
        #expect(inv.pins[0].shape == .abutment)
        #expect(inv.pins[0].antennaDiffArea == 0.0456)
        #expect(inv.pins[0].antennaGateArea == 0.0228)
        #expect(inv.obs.count == 1)
        #expect(inv.obs[0].rects.count == 2)

        // Round-trip
        let data = try LEFLibraryWriter.write(doc)
        let roundTrip = try LEFLibraryReader.read(data)
        #expect(roundTrip.sites.count == 1)
        #expect(roundTrip.layers.count == 3)
        #expect(roundTrip.macros[0].pins.count == 4)
    }

    @Test func multiLayerPort() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          PIN A
            PORT
              LAYER metal1 ;
                RECT 0 0 0.14 0.28 ;
              LAYER metal2 ;
                RECT 0 0 0.2 0.4 ;
            END
          END A
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let ports = doc.macros[0].pins[0].ports
        #expect(ports.count == 2)
        #expect(ports[0].layerName == "metal1")
        #expect(ports[1].layerName == "metal2")
    }
}
