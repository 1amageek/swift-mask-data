import Testing
import Foundation
import LayoutIR
@testable import DEF

@Suite("DEF KLayout Compatibility")
struct DEFKLayoutCompatTests {

    // MARK: - Polygon DIEAREA

    @Test func polygonDieArea() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        DIEAREA ( 0 0 ) ( 1000 0 ) ( 1000 500 ) ( 500 500 ) ( 500 1000 ) ( 0 1000 ) ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.dieArea != nil)
        #expect(doc.dieArea!.points.count == 6)
        #expect(doc.dieArea!.isRectangular == false)
        let bb = doc.dieArea!.boundingBox!
        #expect(bb.x1 == 0)
        #expect(bb.y1 == 0)
        #expect(bb.x2 == 1000)
        #expect(bb.y2 == 1000)
    }

    @Test func polygonDieAreaRoundTrip() throws {
        let area = DEFDieArea(points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            IRPoint(x: 1000, y: 500), IRPoint(x: 500, y: 500),
            IRPoint(x: 500, y: 1000), IRPoint(x: 0, y: 1000),
        ])
        let doc = DEFDocument(designName: "test", dieArea: area)
        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.dieArea!.points.count == 6)
    }

    @Test func polygonDieAreaToIR() {
        let area = DEFDieArea(points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            IRPoint(x: 1000, y: 500), IRPoint(x: 0, y: 500),
        ])
        let doc = DEFDocument(designName: "test", dieArea: area)
        let lib = DEFIRConverter.toIRLibrary(doc)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 5) // Closed polygon
        } else {
            Issue.record("Expected boundary")
        }
    }

    // MARK: - Component Placement Status

    @Test func componentPlacementStatus() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 4 ;
          - u1 INV + PLACED ( 0 0 ) N ;
          - u2 BUF + FIXED ( 100 200 ) S ;
          - u3 NAND + COVER ( 300 400 ) FN ;
          - u4 NOR + UNPLACED ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.components[0].placementStatus == DEFComponent.PlacementStatus.placed)
        #expect(doc.components[1].placementStatus == DEFComponent.PlacementStatus.fixed)
        #expect(doc.components[2].placementStatus == DEFComponent.PlacementStatus.cover)
        #expect(doc.components[3].placementStatus == DEFComponent.PlacementStatus.unplaced)
    }

    @Test func componentPlacementStatusRoundTrip() throws {
        let doc = DEFDocument(
            designName: "test",
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 0, y: 0, orientation: .n,
                            placementStatus: .fixed),
                DEFComponent(name: "u2", macro: "BUF", placementStatus: .unplaced),
            ]
        )
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("FIXED"))
        #expect(text.contains("UNPLACED"))
        let result = try DEFLibraryReader.read(data)
        #expect(result.components[0].placementStatus == DEFComponent.PlacementStatus.fixed)
        #expect(result.components[1].placementStatus == DEFComponent.PlacementStatus.unplaced)
    }

    // MARK: - TRACKS

    @Test func tracksReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        TRACKS X 100 DO 50 STEP 200 LAYER metal1 ;
        TRACKS Y 0 DO 100 STEP 200 LAYER metal2 ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.tracks.count == 2)
        #expect(doc.tracks[0].direction == DEFTrack.TrackDirection.x)
        #expect(doc.tracks[0].start == 100)
        #expect(doc.tracks[0].numTracks == 50)
        #expect(doc.tracks[0].step == 200)
        #expect(doc.tracks[0].layerNames == ["metal1"])
        #expect(doc.tracks[1].direction == DEFTrack.TrackDirection.y)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.tracks.count == 2)
        #expect(result.tracks[0].start == 100)
    }

    // MARK: - GCELLGRID

    @Test func gcellGridReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        GCELLGRID X 0 DO 10 STEP 1000 ;
        GCELLGRID Y 0 DO 20 STEP 500 ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.gcellGrids.count == 2)
        #expect(doc.gcellGrids[0].direction == DEFTrack.TrackDirection.x)
        #expect(doc.gcellGrids[0].numColumns == 10)
        #expect(doc.gcellGrids[1].step == 500)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.gcellGrids.count == 2)
    }

    // MARK: - ROWS

    @Test func rowReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        ROW ROW_0 core 0 0 N DO 100 BY 1 STEP 200 0 ;
        ROW ROW_1 core 0 2000 FS DO 100 BY 1 STEP 200 0 ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.rows.count == 2)
        #expect(doc.rows[0].rowName == "ROW_0")
        #expect(doc.rows[0].siteName == "core")
        #expect(doc.rows[0].originX == 0)
        #expect(doc.rows[0].originY == 0)
        #expect(doc.rows[0].numX == 100)
        #expect(doc.rows[0].numY == 1)
        #expect(doc.rows[0].stepX == 200)
        #expect(doc.rows[1].orientation == .fs)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.rows.count == 2)
        #expect(result.rows[0].numX == 100)
    }

    // MARK: - BLOCKAGES

    @Test func blockageReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        BLOCKAGES 2 ;
          - PLACEMENT + COMPONENT u1 RECT ( 0 0 ) ( 100 200 ) ;
          - ROUTING + LAYER metal1 + PUSHDOWN RECT ( 100 100 ) ( 500 500 ) ;
        END BLOCKAGES
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.blockages.count == 2)
        #expect(doc.blockages[0].blockageType == DEFBlockage.BlockageType.placement)
        #expect(doc.blockages[0].component == "u1")
        #expect(doc.blockages[0].rects.count == 1)
        #expect(doc.blockages[1].blockageType == DEFBlockage.BlockageType.routing)
        #expect(doc.blockages[1].layerName == "metal1")
        #expect(doc.blockages[1].pushdown == true)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.blockages.count == 2)
    }

    // MARK: - REGIONS

    @Test func regionReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        REGIONS 2 ;
          - region1 ( 0 0 ) ( 5000 5000 ) + TYPE FENCE ;
          - region2 ( 1000 1000 ) ( 4000 4000 ) + TYPE GUIDE ;
        END REGIONS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.regions.count == 2)
        #expect(doc.regions[0].name == "region1")
        #expect(doc.regions[0].rects.count == 1)
        #expect(doc.regions[0].regionType == DEFRegion.RegionType.fence)
        #expect(doc.regions[1].regionType == DEFRegion.RegionType.guide)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.regions.count == 2)
        #expect(result.regions[0].regionType == DEFRegion.RegionType.fence)
    }

    // MARK: - FILLS

    @Test func fillReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        FILLS 1 ;
          - LAYER metal1 + OPC RECT ( 100 200 ) ( 300 400 ) RECT ( 500 600 ) ( 700 800 ) ;
        END FILLS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.fills.count == 1)
        #expect(doc.fills[0].layerName == "metal1")
        #expect(doc.fills[0].opc == true)
        #expect(doc.fills[0].rects.count == 2)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.fills.count == 1)
        #expect(result.fills[0].opc == true)
        #expect(result.fills[0].rects.count == 2)
    }

    // MARK: - GROUPS

    @Test func groupReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        GROUPS 1 ;
          - grp1 u1 u2 u3 + REGION region1 ;
        END GROUPS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.groups.count == 1)
        #expect(doc.groups[0].name == "grp1")
        #expect(doc.groups[0].components == ["u1", "u2", "u3"])
        #expect(doc.groups[0].region == "region1")

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.groups.count == 1)
        #expect(result.groups[0].components == ["u1", "u2", "u3"])
    }

    // MARK: - VIAS

    @Test func viaDefReadWrite() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        VIAS 1 ;
          - via12 + VIARULE M1_M2 + CUTSIZE 100 100 + CUTSPACING 200 200 + ENCLOSURE 50 50 50 50 + ROWCOL 1 2 + LAYERS metal1 via1 metal2 ;
        END VIAS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.viaDefs.count == 1)
        #expect(doc.viaDefs[0].name == "via12")
        #expect(doc.viaDefs[0].viaRule == "M1_M2")
        #expect(doc.viaDefs[0].cutSize?.width == 100)
        #expect(doc.viaDefs[0].cutSize?.height == 100)
        #expect(doc.viaDefs[0].cutSpacing?.x == 200)
        #expect(doc.viaDefs[0].rowCol?.rows == 1)
        #expect(doc.viaDefs[0].rowCol?.cols == 2)
        #expect(doc.viaDefs[0].layers.count == 3)

        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.viaDefs.count == 1)
        #expect(result.viaDefs[0].viaRule == "M1_M2")
    }

    @Test func viaDefWithRects() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        VIAS 1 ;
          - VIA12 + RECT metal1 ( -50 -50 ) ( 50 50 ) + RECT via1 ( -25 -25 ) ( 25 25 ) + RECT metal2 ( -50 -50 ) ( 50 50 ) ;
        END VIAS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.viaDefs[0].layers.count == 3)
        #expect(doc.viaDefs[0].layers[0].layerName == "metal1")
        #expect(doc.viaDefs[0].layers[0].rects.count == 1)
        #expect(doc.viaDefs[0].layers[0].rects[0].x1 == -50)
    }

    // MARK: - PROPERTYDEFINITIONS

    @Test func propertyDefinitions() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        PROPERTYDEFINITIONS
          COMPONENT weight REAL ;
          NET priority INTEGER "1" ;
        END PROPERTYDEFINITIONS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.propertyDefinitions.count == 2)
        #expect(doc.propertyDefinitions[0].objectType == "COMPONENT")
        #expect(doc.propertyDefinitions[0].propName == "weight")
        #expect(doc.propertyDefinitions[0].propType == "REAL")
        #expect(doc.propertyDefinitions[1].defaultValue == "1")

        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("PROPERTYDEFINITIONS"))
        #expect(text.contains("COMPONENT weight REAL"))
    }

    // MARK: - BUSBITCHARS / DIVIDERCHAR

    @Test func busbitCharsAndDividerChar() throws {
        let def = """
        VERSION 5.8 ;
        BUSBITCHARS "[]" ;
        DIVIDERCHAR "/" ;
        DESIGN test ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.busbitChars == "[]")
        #expect(doc.dividerChar == "/")

        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("BUSBITCHARS"))
        #expect(text.contains("DIVIDERCHAR"))
    }

    // MARK: - Special Net with Connections

    @Test func specialNetConnections() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD ( * VDD ) + USE POWER + ROUTED metal1 200 ( 0 0 ) ( 1000 0 ) ;
        END SPECIALNETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.specialNets[0].connections.count == 1)
        #expect(doc.specialNets[0].connections[0].componentName == "*")
        #expect(doc.specialNets[0].connections[0].pinName == "VDD")
    }

    // MARK: - Special Net Route Shape

    @Test func specialNetRouteShape() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD + USE POWER + ROUTED metal1 200 + SHAPE STRIPE ( 0 0 ) ( 1000 0 ) ;
        END SPECIALNETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.specialNets[0].routing[0].shape == DEFRouteSegment.RouteShape.stripe)
    }

    // MARK: - Net Routing

    @Test func netRouting() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - net1 ( u1 A ) ( u2 Y ) + ROUTED metal1 ( 100 200 ) ( 300 200 ) via12 ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets[0].routing.count == 1)
        #expect(doc.nets[0].routing[0].layerName == "metal1")
        #expect(doc.nets[0].routing[0].points.count == 2)
        #expect(doc.nets[0].routing[0].viaName == "via12")
    }

    // MARK: - Component Properties

    @Test func componentProperties() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 1 ;
          - u1 INV + PLACED ( 0 0 ) N + WEIGHT 10 + SOURCE NETLIST + PROPERTY key1 "val1" ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.components[0].weight == 10)
        #expect(doc.components[0].source == "NETLIST")
        #expect(doc.components[0].properties.count == 1)
        #expect(doc.components[0].properties[0].key == "key1")
        #expect(doc.components[0].properties[0].value == "val1")
    }

    // MARK: - KLayout Typical Output

    @Test func klayoutTypicalOutput() throws {
        let def = """
        VERSION 5.8 ;
        BUSBITCHARS "[]" ;
        DIVIDERCHAR "/" ;
        DESIGN top ;
        UNITS DISTANCE MICRONS 1000 ;
        DIEAREA ( 0 0 ) ( 100000 100000 ) ;
        ROW ROW_0 unit 0 0 N DO 500 BY 1 STEP 200 0 ;
        ROW ROW_1 unit 0 2000 FS DO 500 BY 1 STEP 200 0 ;
        TRACKS X 100 DO 500 STEP 200 LAYER metal1 ;
        TRACKS Y 100 DO 500 STEP 200 LAYER metal2 ;
        GCELLGRID X 0 DO 50 STEP 2000 ;
        GCELLGRID Y 0 DO 50 STEP 2000 ;
        VIAS 1 ;
          - via12 + RECT metal1 ( -50 -50 ) ( 50 50 ) + RECT via1 ( -25 -25 ) ( 25 25 ) + RECT metal2 ( -50 -50 ) ( 50 50 ) ;
        END VIAS
        COMPONENTS 2 ;
          - u1 INV + PLACED ( 1000 0 ) N ;
          - u2 BUF + FIXED ( 5000 0 ) FS ;
        END COMPONENTS
        PINS 2 ;
          - clk + NET clk + DIRECTION INPUT + LAYER metal1 + PLACED ( 0 1000 ) N ;
          - out + NET out + DIRECTION OUTPUT + PLACED ( 100000 1000 ) N ;
        END PINS
        BLOCKAGES 1 ;
          - ROUTING + LAYER metal1 RECT ( 2000 2000 ) ( 3000 3000 ) ;
        END BLOCKAGES
        REGIONS 1 ;
          - region1 ( 0 0 ) ( 50000 50000 ) + TYPE FENCE ;
        END REGIONS
        NETS 1 ;
          - net1 ( u1 Y ) ( u2 A ) ;
        END NETS
        SPECIALNETS 1 ;
          - VDD ( * VDD ) + USE POWER + ROUTED metal1 200 ( 0 0 ) ( 100000 0 ) ;
        END SPECIALNETS
        FILLS 1 ;
          - LAYER metal2 RECT ( 1000 1000 ) ( 2000 2000 ) ;
        END FILLS
        GROUPS 1 ;
          - grp1 u1 u2 + REGION region1 ;
        END GROUPS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.designName == "top")
        #expect(doc.busbitChars == "[]")
        #expect(doc.dividerChar == "/")
        #expect(doc.dbuPerMicron == 1000)
        #expect(doc.rows.count == 2)
        #expect(doc.tracks.count == 2)
        #expect(doc.gcellGrids.count == 2)
        #expect(doc.viaDefs.count == 1)
        #expect(doc.components.count == 2)
        #expect(doc.pins.count == 2)
        #expect(doc.blockages.count == 1)
        #expect(doc.regions.count == 1)
        #expect(doc.nets.count == 1)
        #expect(doc.specialNets.count == 1)
        #expect(doc.fills.count == 1)
        #expect(doc.groups.count == 1)

        // Round-trip
        let data = try DEFLibraryWriter.write(doc)
        let result = try DEFLibraryReader.read(data)
        #expect(result.designName == "top")
        #expect(result.rows.count == 2)
        #expect(result.tracks.count == 2)
        #expect(result.gcellGrids.count == 2)
        #expect(result.viaDefs.count == 1)
        #expect(result.components.count == 2)
        #expect(result.pins.count == 2)
        #expect(result.blockages.count == 1)
        #expect(result.regions.count == 1)
        #expect(result.nets.count == 1)
        #expect(result.specialNets.count == 1)
        #expect(result.fills.count == 1)
        #expect(result.groups.count == 1)
    }

    // MARK: - DEFViaDef Codable

    @Test func viaDefCodable() throws {
        let original = DEFViaDef(
            name: "via12",
            layers: [DEFViaLayer(layerName: "metal1", rects: [DEFRect(x1: -50, y1: -50, x2: 50, y2: 50)])],
            viaRule: "M1_M2",
            cutSize: (100, 100),
            cutSpacing: (200, 200),
            botEnclosure: (50, 50),
            topEnclosure: (50, 50),
            rowCol: (1, 2)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFViaDef.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Wildcard Coordinates

    @Test func specialNetWildcard() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD + USE POWER + ROUTED metal1 200 ( 0 0 ) ( * 1000 ) ;
        END SPECIALNETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        let pts = doc.specialNets[0].routing[0].points
        #expect(pts.count == 2)
        #expect(pts[0].x == 0)
        #expect(pts[0].y == 0)
        #expect(pts[1].x == nil) // wildcard
        #expect(pts[1].y == 1000)
    }

    // MARK: - Pin USE keyword

    @Test func pinUseKeyword() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        PINS 1 ;
          - VDD + NET VDD + DIRECTION INOUT + USE POWER + PLACED ( 0 0 ) N ;
        END PINS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.pins[0].use == DEFSpecialNet.NetUse.power)
        #expect(doc.pins[0].direction == DEFPin.Direction.inout_)
    }
}
