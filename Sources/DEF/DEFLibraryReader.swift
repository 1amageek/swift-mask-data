import Foundation
import LayoutIR

/// Parses DEF text data into a DEFDocument.
public enum DEFLibraryReader {

    public static func read(_ data: Data) throws -> DEFDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DEFError.invalidEncoding
        }

        let tokens = DEFTokenizer.tokenize(text)
        var doc = DEFDocument()
        var i = 0

        while i < tokens.count {
            switch tokens[i].uppercased() {
            case "VERSION":
                i += 1
                if i < tokens.count && tokens[i] != ";" { doc.version = tokens[i]; i += 1 }
                i = skip(";", tokens, i)

            case "DESIGN":
                i += 1
                if i < tokens.count && tokens[i] != ";" { doc.designName = tokens[i]; i += 1 }
                i = skip(";", tokens, i)

            case "BUSBITCHARS":
                i += 1
                if i < tokens.count { doc.busbitChars = unquote(tokens[i]); i += 1 }
                i = skip(";", tokens, i)

            case "DIVIDERCHAR":
                i += 1
                if i < tokens.count { doc.dividerChar = unquote(tokens[i]); i += 1 }
                i = skip(";", tokens, i)

            case "UNITS":
                i += 1
                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i].uppercased() == "MICRONS" {
                        i += 1
                        doc.dbuPerMicron = try parseDouble(tokens, at: i, context: "UNITS DISTANCE MICRONS")
                    }
                    i += 1
                }
                i = skip(";", tokens, i)

            case "DIEAREA":
                i += 1
                let (area, next) = try parseDieArea(tokens, from: i)
                doc.dieArea = area
                i = next

            case "ROW":
                let (row, next) = try parseRow(tokens, from: i)
                if let row = row { doc.rows.append(row) }
                i = next

            case "TRACKS":
                let (track, next) = try parseTrackLine(tokens, from: i)
                if let track = track { doc.tracks.append(track) }
                i = next

            case "GCELLGRID":
                let (grid, next) = try parseGCellGrid(tokens, from: i)
                if let grid = grid { doc.gcellGrids.append(grid) }
                i = next

            case "COMPONENTS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (comps, next) = try parseComponents(tokens, from: i)
                doc.components = comps
                i = next

            case "PINS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (pins, next) = try parsePins(tokens, from: i)
                doc.pins = pins
                i = next

            case "NETS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (nets, next) = try parseNets(tokens, from: i)
                doc.nets = nets
                i = next

            case "SPECIALNETS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (snets, next) = try parseSpecialNets(tokens, from: i)
                doc.specialNets = snets
                i = next

            case "VIAS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (vias, next) = try parseVias(tokens, from: i)
                doc.viaDefs = vias
                i = next

            case "BLOCKAGES":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (blk, next) = try parseBlockages(tokens, from: i)
                doc.blockages = blk
                i = next

            case "REGIONS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (reg, next) = try parseRegions(tokens, from: i)
                doc.regions = reg
                i = next

            case "FILLS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (fills, next) = try parseFills(tokens, from: i)
                doc.fills = fills
                i = next

            case "GROUPS":
                i += 1
                if i < tokens.count, let _ = Int(tokens[i]) { i += 1 }
                i = skip(";", tokens, i)
                let (grp, next) = parseGroups(tokens, from: i)
                doc.groups = grp
                i = next

            case "PROPERTYDEFINITIONS":
                i += 1
                let (defs, next) = parsePropertyDefinitions(tokens, from: i)
                doc.propertyDefinitions = defs
                i = next

            case "PROPERTY":
                i += 1
                var key = ""
                var value = ""
                if i < tokens.count && tokens[i] != ";" { key = tokens[i]; i += 1 }
                if i < tokens.count && tokens[i] != ";" { value = unquote(tokens[i]); i += 1 }
                if !key.isEmpty {
                    doc.properties.append(DEFProperty(key: key, value: value))
                }
                i = skip(";", tokens, i)

            default:
                i += 1
            }
        }

        return doc
    }

    // MARK: - DIEAREA

    private static func parseDieArea(_ tokens: [String], from start: Int) throws -> (DEFDieArea?, Int) {
        var i = start
        var points: [IRPoint] = []
        while i < tokens.count && tokens[i] != ";" {
            if tokens[i] == "(" {
                i += 1
                if i + 1 < tokens.count {
                    let x = try parseInt32(tokens, at: i, context: "DIEAREA x")
                    let y = try parseInt32(tokens, at: i + 1, context: "DIEAREA y")
                    points.append(IRPoint(x: x, y: y))
                    i += 2
                }
                i = skip(")", tokens, i)
            } else {
                i += 1
            }
        }
        i = skip(";", tokens, i)
        if points.count >= 2 {
            return (DEFDieArea(points: points), i)
        }
        return (nil, i)
    }

    // MARK: - ROW

    private static func parseRow(_ tokens: [String], from start: Int) throws -> (DEFRow?, Int) {
        var i = start
        guard tokens[i].uppercased() == "ROW" else { return (nil, i + 1) }
        i += 1
        guard i + 4 < tokens.count else { return (nil, skipToSemicolon(tokens, i)) }
        let rowName = tokens[i]; i += 1
        let siteName = tokens[i]; i += 1
        let originX = try parseInt32(tokens, at: i, context: "ROW \(rowName) origin x"); i += 1
        let originY = try parseInt32(tokens, at: i, context: "ROW \(rowName) origin y"); i += 1
        let orient = DEFOrientation(rawValue: tokens[i].uppercased()) ?? .n; i += 1

        var numX: Int32 = 1, numY: Int32 = 1, stepX: Int32 = 0, stepY: Int32 = 0

        while i < tokens.count && tokens[i] != ";" {
            if tokens[i].uppercased() == "DO" {
                i += 1
                if i < tokens.count { numX = try parseInt32(tokens, at: i, context: "ROW \(rowName) DO count x"); i += 1 }
                if i < tokens.count && tokens[i].uppercased() == "BY" { i += 1 }
                if i < tokens.count { numY = try parseInt32(tokens, at: i, context: "ROW \(rowName) DO count y"); i += 1 }
            } else if tokens[i].uppercased() == "STEP" {
                i += 1
                if i < tokens.count { stepX = try parseInt32(tokens, at: i, context: "ROW \(rowName) STEP x"); i += 1 }
                if i < tokens.count { stepY = try parseInt32(tokens, at: i, context: "ROW \(rowName) STEP y"); i += 1 }
            } else {
                i += 1
            }
        }
        i = skip(";", tokens, i)

        return (DEFRow(rowName: rowName, siteName: siteName,
                       originX: originX, originY: originY, orientation: orient,
                       numX: numX, numY: numY, stepX: stepX, stepY: stepY), i)
    }

    // MARK: - TRACKS

    private static func parseTrackLine(_ tokens: [String], from start: Int) throws -> (DEFTrack?, Int) {
        var i = start
        guard tokens[i].uppercased() == "TRACKS" else { return (nil, i + 1) }
        i += 1
        guard i + 3 < tokens.count else { return (nil, skipToSemicolon(tokens, i)) }
        guard let dir = DEFTrack.TrackDirection(rawValue: tokens[i].uppercased()) else {
            return (nil, skipToSemicolon(tokens, i))
        }
        i += 1
        let startVal = try parseInt32(tokens, at: i, context: "TRACKS start"); i += 1
        if i < tokens.count && tokens[i].uppercased() == "DO" { i += 1 }
        let numTracks = try parseInt32(tokens, at: i, context: "TRACKS DO count"); i += 1
        if i < tokens.count && tokens[i].uppercased() == "STEP" { i += 1 }
        let step = try parseInt32(tokens, at: i, context: "TRACKS STEP"); i += 1

        var layers: [String] = []
        while i < tokens.count && tokens[i] != ";" {
            if tokens[i].uppercased() == "LAYER" {
                i += 1
                if i < tokens.count && tokens[i] != ";" { layers.append(tokens[i]); i += 1 }
            } else {
                layers.append(tokens[i]); i += 1
            }
        }
        i = skip(";", tokens, i)

        return (DEFTrack(direction: dir, start: startVal, numTracks: numTracks,
                         step: step, layerNames: layers), i)
    }

    // MARK: - GCELLGRID

    private static func parseGCellGrid(_ tokens: [String], from start: Int) throws -> (DEFGCellGrid?, Int) {
        var i = start
        guard tokens[i].uppercased() == "GCELLGRID" else { return (nil, i + 1) }
        i += 1
        guard i + 3 < tokens.count else { return (nil, skipToSemicolon(tokens, i)) }
        guard let dir = DEFTrack.TrackDirection(rawValue: tokens[i].uppercased()) else {
            return (nil, skipToSemicolon(tokens, i))
        }
        i += 1
        let startVal = try parseInt32(tokens, at: i, context: "GCELLGRID start"); i += 1
        if i < tokens.count && tokens[i].uppercased() == "DO" { i += 1 }
        let numCols = try parseInt32(tokens, at: i, context: "GCELLGRID DO count"); i += 1
        if i < tokens.count && tokens[i].uppercased() == "STEP" { i += 1 }
        let step = try parseInt32(tokens, at: i, context: "GCELLGRID STEP"); i += 1
        i = skip(";", tokens, i)

        return (DEFGCellGrid(direction: dir, start: startVal, numColumns: numCols, step: step), i)
    }

    // MARK: - COMPONENTS

    private static func parseComponents(_ tokens: [String], from start: Int) throws -> ([DEFComponent], Int) {
        var i = start
        var comps: [DEFComponent] = []

        while i < tokens.count {
            let upper = tokens[i].uppercased()
            if upper == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "COMPONENTS" { i += 1 }
                return (comps, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i + 1 < tokens.count else { break }
                let name = tokens[i]; i += 1
                let macro = tokens[i]; i += 1
                var x: Int32 = 0, y: Int32 = 0
                var orient: DEFOrientation = .n
                var status: DEFComponent.PlacementStatus?
                var weight: Int?
                var region: String?
                var source: String?
                var props: [DEFProperty] = []

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "PLACED" || kw == "FIXED" || kw == "COVER" || kw == "UNPLACED" {
                            status = DEFComponent.PlacementStatus(rawValue: kw)
                            i += 1
                            if kw != "UNPLACED" {
                                i = skip("(", tokens, i)
                                if i < tokens.count { x = try parseInt32(tokens, at: i, context: "COMPONENT \(name) placement x"); i += 1 }
                                if i < tokens.count { y = try parseInt32(tokens, at: i, context: "COMPONENT \(name) placement y"); i += 1 }
                                i = skip(")", tokens, i)
                                if i < tokens.count, let o = DEFOrientation(rawValue: tokens[i].uppercased()) {
                                    orient = o; i += 1
                                }
                            }
                        } else if kw == "WEIGHT" {
                            i += 1
                            if i < tokens.count, let w = Int(tokens[i]) { weight = w; i += 1 }
                        } else if kw == "REGION" {
                            i += 1
                            if i < tokens.count { region = tokens[i]; i += 1 }
                        } else if kw == "SOURCE" {
                            i += 1
                            if i < tokens.count { source = tokens[i]; i += 1 }
                        } else if kw == "PROPERTY" {
                            i += 1
                            let (p, next) = parseProperties(tokens, from: i)
                            props = p; i = next
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                comps.append(DEFComponent(name: name, macro: macro, x: x, y: y,
                                          orientation: orient, placementStatus: status,
                                          weight: weight, region: region, source: source,
                                          properties: props))
            } else {
                i += 1
            }
        }

        return (comps, i)
    }

    // MARK: - PINS

    private static func parsePins(_ tokens: [String], from start: Int) throws -> ([DEFPin], Int) {
        var i = start
        var pins: [DEFPin] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "PINS" { i += 1 }
                return (pins, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var pin = DEFPin(name: name)

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "NET" {
                            i += 1
                            if i < tokens.count { pin.netName = tokens[i]; i += 1 }
                        } else if kw == "DIRECTION" {
                            i += 1
                            if i < tokens.count {
                                pin.direction = DEFPin.Direction(rawValue: tokens[i].uppercased())
                                i += 1
                            }
                        } else if kw == "USE" {
                            i += 1
                            if i < tokens.count {
                                pin.use = DEFSpecialNet.NetUse(rawValue: tokens[i].uppercased())
                                i += 1
                            }
                        } else if kw == "LAYER" {
                            i += 1
                            if i < tokens.count { pin.layerName = tokens[i]; i += 1 }
                            // Parse optional rect after LAYER
                            if i < tokens.count && tokens[i] == "(" {
                                var rects: [DEFRect] = []
                                while i < tokens.count && tokens[i] == "(" {
                                    i += 1
                                    if i + 3 < tokens.count {
                                        let x1 = try parseInt32(tokens, at: i, context: "PIN \(name) layer rect x1")
                                        let y1 = try parseInt32(tokens, at: i + 1, context: "PIN \(name) layer rect y1")
                                        i += 2
                                        i = skip(")", tokens, i)
                                        i = skip("(", tokens, i)
                                        if i + 1 < tokens.count {
                                            let x2 = try parseInt32(tokens, at: i, context: "PIN \(name) layer rect x2")
                                            let y2 = try parseInt32(tokens, at: i + 1, context: "PIN \(name) layer rect y2")
                                            rects.append(DEFRect(x1: x1, y1: y1, x2: x2, y2: y2))
                                            i += 2
                                        }
                                        i = skip(")", tokens, i)
                                    } else {
                                        i = skip(")", tokens, i)
                                    }
                                }
                                if !rects.isEmpty, let layerName = pin.layerName {
                                    pin.layerRects.append(DEFPinLayerRect(layerName: layerName, rects: rects))
                                }
                            }
                        } else if kw == "PLACED" || kw == "FIXED" || kw == "COVER" || kw == "UNPLACED" {
                            pin.placementStatus = DEFComponent.PlacementStatus(rawValue: kw)
                            i += 1
                            if kw != "UNPLACED" {
                                i = skip("(", tokens, i)
                                if i < tokens.count { pin.x = try parseInt32(tokens, at: i, context: "PIN \(name) placement x"); i += 1 }
                                if i < tokens.count { pin.y = try parseInt32(tokens, at: i, context: "PIN \(name) placement y"); i += 1 }
                                i = skip(")", tokens, i)
                                if i < tokens.count, let o = DEFOrientation(rawValue: tokens[i].uppercased()) {
                                    pin.orientation = o; i += 1
                                }
                            }
                        } else if kw == "SPECIAL" {
                            pin.special = true
                            i += 1
                        } else if kw == "PROPERTY" {
                            i += 1
                            let (p, next) = parseProperties(tokens, from: i)
                            pin.properties = p; i = next
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                pins.append(pin)
            } else {
                i += 1
            }
        }

        return (pins, i)
    }

    // MARK: - NETS

    private static func parseNets(_ tokens: [String], from start: Int) throws -> ([DEFNet], Int) {
        var i = start
        var nets: [DEFNet] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "NETS" { i += 1 }
                return (nets, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var conns: [DEFConnection] = []
                var use: DEFSpecialNet.NetUse?
                var routing: [DEFRouteWire] = []
                var props: [DEFProperty] = []

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "(" {
                        i += 1
                        if i + 1 < tokens.count {
                            let comp = tokens[i]; i += 1
                            let pin = tokens[i]; i += 1
                            conns.append(DEFConnection(componentName: comp, pinName: pin))
                        }
                        i = skip(")", tokens, i)
                    } else if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "USE" {
                            i += 1
                            if i < tokens.count {
                                use = DEFSpecialNet.NetUse(rawValue: tokens[i].uppercased())
                                i += 1
                            }
                        } else if kw == "ROUTED" || kw == "FIXED" || kw == "COVER" || kw == "NOSHIELD" || kw == "NEW" {
                            let status = DEFRouteWire.RouteStatus(rawValue: kw) ?? .routed
                            i += 1
                            if i < tokens.count {
                                let layerName = tokens[i]; i += 1
                                var points: [IRPoint] = []
                                var viaName: String?
                                while i < tokens.count && tokens[i] == "(" {
                                    i += 1
                                    if i + 1 < tokens.count, tokens[i] != "*" {
                                        let px = try parseInt32(tokens, at: i, context: "NET \(name) route x")
                                        let py: Int32
                                        if tokens[i + 1] == "*" {
                                            py = try previousRoutePoint(points, axis: "y", context: "NET \(name) route wildcard")
                                        } else {
                                            py = try parseInt32(tokens, at: i + 1, context: "NET \(name) route y")
                                        }
                                        points.append(IRPoint(x: px, y: py))
                                        i += 2
                                    } else if i < tokens.count && tokens[i] == "*" {
                                        // wildcard
                                        i += 1
                                        if i < tokens.count {
                                            let py = try parseInt32(tokens, at: i, context: "NET \(name) route y")
                                            let prevX = try previousRoutePoint(points, axis: "x", context: "NET \(name) route wildcard")
                                            points.append(IRPoint(x: prevX, y: py))
                                            i += 1
                                        }
                                    }
                                    i = skip(")", tokens, i)
                                }
                                // Check for via name after points
                                if i < tokens.count && tokens[i] != "+" && tokens[i] != ";" && tokens[i] != "(" {
                                    if Int32(tokens[i]) == nil {
                                        viaName = tokens[i]; i += 1
                                    }
                                }
                                routing.append(DEFRouteWire(status: status, layerName: layerName,
                                                           points: points, viaName: viaName))
                            }
                        } else if kw == "PROPERTY" {
                            i += 1
                            let (p, next) = parseProperties(tokens, from: i)
                            props = p; i = next
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                nets.append(DEFNet(name: name, connections: conns, use: use,
                                   routing: routing, properties: props))
            } else {
                i += 1
            }
        }

        return (nets, i)
    }

    // MARK: - SPECIALNETS

    private static func parseSpecialNets(_ tokens: [String], from start: Int) throws -> ([DEFSpecialNet], Int) {
        var i = start
        var snets: [DEFSpecialNet] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "SPECIALNETS" { i += 1 }
                return (snets, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var snet = DEFSpecialNet(name: name)

                // Parse connections before + keywords
                while i < tokens.count && tokens[i] == "(" {
                    i += 1
                    if i + 1 < tokens.count {
                        let comp = tokens[i]; i += 1
                        let pin = tokens[i]; i += 1
                        snet.connections.append(DEFConnection(componentName: comp, pinName: pin))
                    }
                    i = skip(")", tokens, i)
                }

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "USE" {
                            i += 1
                            if i < tokens.count {
                                snet.use = DEFSpecialNet.NetUse(rawValue: tokens[i].uppercased())
                                i += 1
                            }
                        } else if kw == "ROUTED" || kw == "FIXED" || kw == "COVER" || kw == "SHIELD" || kw == "NEW" {
                            let status = DEFRouteSegment.RouteStatus(rawValue: kw) ?? .routed
                            i += 1
                            if i < tokens.count {
                                let layerName = tokens[i]; i += 1
                                var width: Int32 = 0
                                if i < tokens.count {
                                    width = try parseInt32(tokens, at: i, context: "SPECIALNET \(name) route width")
                                    i += 1
                                }

                                var shape: DEFRouteSegment.RouteShape?
                                // Parse optional + SHAPE before points
                                if i < tokens.count && tokens[i] == "+" {
                                    let saved = i
                                    i += 1
                                    if i < tokens.count && tokens[i].uppercased() == "SHAPE" {
                                        i += 1
                                        if i < tokens.count {
                                            shape = DEFRouteSegment.RouteShape(rawValue: tokens[i].uppercased())
                                            i += 1
                                        }
                                    } else {
                                        i = saved  // Not SHAPE, restore
                                    }
                                }

                                var points: [DEFRoutePoint] = []
                                while i < tokens.count && tokens[i] == "(" {
                                    i += 1
                                    var pt = DEFRoutePoint()
                                    if i < tokens.count {
                                        if tokens[i] == "*" {
                                            pt.x = nil; i += 1
                                        } else {
                                            let v = try parseInt32(tokens, at: i, context: "SPECIALNET \(name) route x")
                                            pt.x = v; i += 1
                                        }
                                    }
                                    if i < tokens.count {
                                        if tokens[i] == "*" {
                                            pt.y = nil; i += 1
                                        } else {
                                            let v = try parseInt32(tokens, at: i, context: "SPECIALNET \(name) route y")
                                            pt.y = v; i += 1
                                        }
                                    }
                                    // Optional extension
                                    if i < tokens.count && tokens[i] != ")" {
                                        pt.ext = try parseInt32(tokens, at: i, context: "SPECIALNET \(name) route extension")
                                        i += 1
                                    }
                                    i = skip(")", tokens, i)
                                    points.append(pt)
                                }
                                // Check for via name after points
                                if i < tokens.count && tokens[i] != "+" && tokens[i] != ";" && tokens[i] != "(" {
                                    if Int32(tokens[i]) == nil && tokens[i] != "NEW" {
                                        let via = tokens[i]; i += 1
                                        points.append(DEFRoutePoint(viaName: via))
                                    }
                                }
                                snet.routing.append(DEFRouteSegment(status: status, layerName: layerName,
                                                                    width: width, points: points, shape: shape))
                            }
                        } else if kw == "SOURCE" {
                            i += 1
                            if i < tokens.count { snet.source = tokens[i]; i += 1 }
                        } else if kw == "WEIGHT" {
                            i += 1
                            if i < tokens.count, let w = Int(tokens[i]) { snet.weight = w; i += 1 }
                        } else if kw == "PROPERTY" {
                            i += 1
                            let (p, next) = parseProperties(tokens, from: i)
                            snet.properties = p; i = next
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                snets.append(snet)
            } else {
                i += 1
            }
        }

        return (snets, i)
    }

    // MARK: - VIAS

    private static func parseVias(_ tokens: [String], from start: Int) throws -> ([DEFViaDef], Int) {
        var i = start
        var vias: [DEFViaDef] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "VIAS" { i += 1 }
                return (vias, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var via = DEFViaDef(name: name)

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "VIARULE" {
                            i += 1
                            if i < tokens.count { via.viaRule = tokens[i]; i += 1 }
                        } else if kw == "CUTSIZE" {
                            i += 1
                            if i + 1 < tokens.count {
                                let w = try parseInt32(tokens, at: i, context: "VIA \(name) CUTSIZE width")
                                let h = try parseInt32(tokens, at: i + 1, context: "VIA \(name) CUTSIZE height")
                                via.cutSize = (w, h); i += 2
                            }
                        } else if kw == "CUTSPACING" {
                            i += 1
                            if i + 1 < tokens.count {
                                let x = try parseInt32(tokens, at: i, context: "VIA \(name) CUTSPACING x")
                                let y = try parseInt32(tokens, at: i + 1, context: "VIA \(name) CUTSPACING y")
                                via.cutSpacing = (x, y); i += 2
                            }
                        } else if kw == "ENCLOSURE" {
                            i += 1
                            if i + 3 < tokens.count {
                                let bx = try parseInt32(tokens, at: i, context: "VIA \(name) ENCLOSURE bottom x")
                                let by = try parseInt32(tokens, at: i + 1, context: "VIA \(name) ENCLOSURE bottom y")
                                let tx = try parseInt32(tokens, at: i + 2, context: "VIA \(name) ENCLOSURE top x")
                                let ty = try parseInt32(tokens, at: i + 3, context: "VIA \(name) ENCLOSURE top y")
                                via.botEnclosure = (bx, by)
                                via.topEnclosure = (tx, ty)
                                i += 4
                            }
                        } else if kw == "ROWCOL" {
                            i += 1
                            if i + 1 < tokens.count {
                                let r = try parseInt32(tokens, at: i, context: "VIA \(name) ROWCOL rows")
                                let c = try parseInt32(tokens, at: i + 1, context: "VIA \(name) ROWCOL columns")
                                via.rowCol = (r, c); i += 2
                            }
                        } else if kw == "LAYERS" || kw == "RECT" {
                            // VIARULE generated via: + LAYERS botLayer cutLayer topLayer
                            if kw == "LAYERS" {
                                i += 1
                                // 3 layer names
                                for _ in 0..<3 {
                                    if i < tokens.count && tokens[i] != "+" && tokens[i] != ";" {
                                        via.layers.append(DEFViaLayer(layerName: tokens[i]))
                                        i += 1
                                    }
                                }
                            } else {
                                // + RECT layerName ( x1 y1 ) ( x2 y2 )
                                i += 1
                                if i < tokens.count {
                                    let layerName = tokens[i]; i += 1
                                    i = skip("(", tokens, i)
                                    if i + 3 < tokens.count {
                                        let x1 = try parseInt32(tokens, at: i, context: "VIA \(name) RECT x1")
                                        let y1 = try parseInt32(tokens, at: i + 1, context: "VIA \(name) RECT y1")
                                        i += 2
                                        i = skip(")", tokens, i)
                                        i = skip("(", tokens, i)
                                        if i + 1 < tokens.count {
                                            let x2 = try parseInt32(tokens, at: i, context: "VIA \(name) RECT x2")
                                            let y2 = try parseInt32(tokens, at: i + 1, context: "VIA \(name) RECT y2")
                                            let rect = DEFRect(x1: x1, y1: y1, x2: x2, y2: y2)
                                            if let idx = via.layers.firstIndex(where: { $0.layerName == layerName }) {
                                                via.layers[idx].rects.append(rect)
                                            } else {
                                                via.layers.append(DEFViaLayer(layerName: layerName, rects: [rect]))
                                            }
                                            i += 2
                                        }
                                        i = skip(")", tokens, i)
                                    }
                                }
                            }
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                vias.append(via)
            } else {
                i += 1
            }
        }

        return (vias, i)
    }

    // MARK: - BLOCKAGES

    private static func parseBlockages(_ tokens: [String], from start: Int) throws -> ([DEFBlockage], Int) {
        var i = start
        var blockages: [DEFBlockage] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "BLOCKAGES" { i += 1 }
                return (blockages, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let kw = tokens[i].uppercased()
                var blkType: DEFBlockage.BlockageType = .placement
                var layerName: String?
                var component: String?
                var pushdown = false

                if kw == "PLACEMENT" {
                    blkType = .placement; i += 1
                } else if kw == "ROUTING" {
                    blkType = .routing; i += 1
                }

                var rects: [DEFRect] = []
                var polygons: [[IRPoint]] = []

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let subkw = tokens[i].uppercased()
                        if subkw == "LAYER" {
                            i += 1
                            if i < tokens.count { layerName = tokens[i]; i += 1 }
                        } else if subkw == "COMPONENT" {
                            i += 1
                            if i < tokens.count { component = tokens[i]; i += 1 }
                        } else if subkw == "PUSHDOWN" {
                            pushdown = true; i += 1
                        } else {
                            i += 1
                        }
                    } else if tokens[i].uppercased() == "RECT" {
                        i += 1
                        i = skip("(", tokens, i)
                        if i + 3 < tokens.count {
                            let x1 = try parseInt32(tokens, at: i, context: "BLOCKAGE RECT x1")
                            let y1 = try parseInt32(tokens, at: i + 1, context: "BLOCKAGE RECT y1")
                            i += 2
                            i = skip(")", tokens, i)
                            i = skip("(", tokens, i)
                            if i + 1 < tokens.count {
                                let x2 = try parseInt32(tokens, at: i, context: "BLOCKAGE RECT x2")
                                let y2 = try parseInt32(tokens, at: i + 1, context: "BLOCKAGE RECT y2")
                                rects.append(DEFRect(x1: x1, y1: y1, x2: x2, y2: y2))
                                i += 2
                            }
                            i = skip(")", tokens, i)
                        }
                    } else if tokens[i].uppercased() == "POLYGON" {
                        i += 1
                        var pts: [IRPoint] = []
                        while i < tokens.count && tokens[i] == "(" {
                            i += 1
                            if i + 1 < tokens.count {
                                let x = try parseInt32(tokens, at: i, context: "BLOCKAGE POLYGON x")
                                let y = try parseInt32(tokens, at: i + 1, context: "BLOCKAGE POLYGON y")
                                pts.append(IRPoint(x: x, y: y))
                                i += 2
                            }
                            i = skip(")", tokens, i)
                        }
                        if !pts.isEmpty { polygons.append(pts) }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                blockages.append(DEFBlockage(blockageType: blkType, layerName: layerName,
                                             component: component, pushdown: pushdown,
                                             rects: rects, polygons: polygons))
            } else {
                i += 1
            }
        }

        return (blockages, i)
    }

    // MARK: - REGIONS

    private static func parseRegions(_ tokens: [String], from start: Int) throws -> ([DEFRegion], Int) {
        var i = start
        var regions: [DEFRegion] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "REGIONS" { i += 1 }
                return (regions, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var rects: [DEFRect] = []
                var regionType: DEFRegion.RegionType?

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "(" {
                        i += 1
                        if i + 1 < tokens.count {
                            let x1 = try parseInt32(tokens, at: i, context: "REGION \(name) RECT x1")
                            let y1 = try parseInt32(tokens, at: i + 1, context: "REGION \(name) RECT y1")
                            i += 2
                            i = skip(")", tokens, i)
                            i = skip("(", tokens, i)
                            if i + 1 < tokens.count {
                                let x2 = try parseInt32(tokens, at: i, context: "REGION \(name) RECT x2")
                                let y2 = try parseInt32(tokens, at: i + 1, context: "REGION \(name) RECT y2")
                                rects.append(DEFRect(x1: x1, y1: y1, x2: x2, y2: y2))
                                i += 2
                            }
                            i = skip(")", tokens, i)
                        } else {
                            i = skip(")", tokens, i)
                        }
                    } else if tokens[i] == "+" {
                        i += 1
                        if i < tokens.count && tokens[i].uppercased() == "TYPE" {
                            i += 1
                            if i < tokens.count {
                                regionType = DEFRegion.RegionType(rawValue: tokens[i].uppercased())
                                i += 1
                            }
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                regions.append(DEFRegion(name: name, rects: rects, regionType: regionType))
            } else {
                i += 1
            }
        }

        return (regions, i)
    }

    // MARK: - FILLS

    private static func parseFills(_ tokens: [String], from start: Int) throws -> ([DEFFill], Int) {
        var i = start
        var fills: [DEFFill] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "FILLS" { i += 1 }
                return (fills, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                // Expect LAYER keyword
                var layerName = ""
                var rects: [DEFRect] = []
                var polygons: [[IRPoint]] = []
                var opc = false

                if tokens[i].uppercased() == "LAYER" {
                    i += 1
                    if i < tokens.count { layerName = tokens[i]; i += 1 }
                }

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        if i < tokens.count && tokens[i].uppercased() == "OPC" {
                            opc = true; i += 1
                        } else {
                            i += 1
                        }
                    } else if tokens[i].uppercased() == "RECT" {
                        i += 1
                        i = skip("(", tokens, i)
                        if i + 3 < tokens.count {
                            let x1 = try parseInt32(tokens, at: i, context: "FILL RECT x1")
                            let y1 = try parseInt32(tokens, at: i + 1, context: "FILL RECT y1")
                            i += 2
                            i = skip(")", tokens, i)
                            i = skip("(", tokens, i)
                            if i + 1 < tokens.count {
                                let x2 = try parseInt32(tokens, at: i, context: "FILL RECT x2")
                                let y2 = try parseInt32(tokens, at: i + 1, context: "FILL RECT y2")
                                rects.append(DEFRect(x1: x1, y1: y1, x2: x2, y2: y2))
                                i += 2
                            }
                            i = skip(")", tokens, i)
                        }
                    } else if tokens[i].uppercased() == "POLYGON" {
                        i += 1
                        var pts: [IRPoint] = []
                        while i < tokens.count && tokens[i] == "(" {
                            i += 1
                            if i + 1 < tokens.count {
                                let x = try parseInt32(tokens, at: i, context: "FILL POLYGON x")
                                let y = try parseInt32(tokens, at: i + 1, context: "FILL POLYGON y")
                                pts.append(IRPoint(x: x, y: y))
                                i += 2
                            }
                            i = skip(")", tokens, i)
                        }
                        if !pts.isEmpty { polygons.append(pts) }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                fills.append(DEFFill(layerName: layerName, rects: rects, polygons: polygons, opc: opc))
            } else {
                i += 1
            }
        }

        return (fills, i)
    }

    // MARK: - GROUPS

    private static func parseGroups(_ tokens: [String], from start: Int) -> ([DEFGroup], Int) {
        var i = start
        var groups: [DEFGroup] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "GROUPS" { i += 1 }
                return (groups, i)
            }
            if tokens[i] == "-" {
                i += 1
                guard i < tokens.count else { break }
                let name = tokens[i]; i += 1
                var components: [String] = []
                var region: String?
                var props: [DEFProperty] = []

                // Component names before +
                while i < tokens.count && tokens[i] != "+" && tokens[i] != ";" {
                    components.append(tokens[i]); i += 1
                }

                while i < tokens.count && tokens[i] != ";" {
                    if tokens[i] == "+" {
                        i += 1
                        guard i < tokens.count else { break }
                        let kw = tokens[i].uppercased()
                        if kw == "REGION" {
                            i += 1
                            if i < tokens.count { region = tokens[i]; i += 1 }
                        } else if kw == "PROPERTY" {
                            i += 1
                            let (p, next) = parseProperties(tokens, from: i)
                            props = p; i = next
                        } else {
                            i += 1
                        }
                    } else {
                        i += 1
                    }
                }
                i = skip(";", tokens, i)
                groups.append(DEFGroup(name: name, components: components,
                                       region: region, properties: props))
            } else {
                i += 1
            }
        }

        return (groups, i)
    }

    // MARK: - PROPERTYDEFINITIONS

    private static func parsePropertyDefinitions(_ tokens: [String], from start: Int) -> ([DEFPropertyDefinition], Int) {
        var i = start
        var defs: [DEFPropertyDefinition] = []

        while i < tokens.count {
            if tokens[i].uppercased() == "END" {
                i += 1
                if i < tokens.count && tokens[i].uppercased() == "PROPERTYDEFINITIONS" { i += 1 }
                return (defs, i)
            }
            // Each definition: objectType propName propType [RANGE min max] [defaultValue] ;
            let objectType = tokens[i]; i += 1
            guard i < tokens.count else { break }
            let propName = tokens[i]; i += 1
            guard i < tokens.count else { break }
            let propType = tokens[i]; i += 1

            var defaultValue: String?
            // Consume remaining tokens until semicolon, handling RANGE keyword
            while i < tokens.count && tokens[i] != ";" {
                let tok = tokens[i].uppercased()
                if tok == "RANGE" {
                    i += 1  // skip RANGE
                    // skip min and max values
                    if i < tokens.count && tokens[i] != ";" { i += 1 }
                    if i < tokens.count && tokens[i] != ";" { i += 1 }
                } else {
                    if defaultValue == nil { defaultValue = unquote(tokens[i]) }
                    i += 1
                }
            }
            i = skip(";", tokens, i)

            defs.append(DEFPropertyDefinition(objectType: objectType, propName: propName,
                                              propType: propType, defaultValue: defaultValue))
        }

        return (defs, i)
    }

    // MARK: - Helpers

    private static func parseInt32(_ tokens: [String], at index: Int, context: String) throws -> Int32 {
        guard index < tokens.count else {
            throw DEFError.missingNumber(context: context)
        }
        guard let value = Int32(tokens[index]) else {
            throw DEFError.invalidNumber(context: context, token: tokens[index])
        }
        return value
    }

    private static func parseDouble(_ tokens: [String], at index: Int, context: String) throws -> Double {
        guard index < tokens.count else {
            throw DEFError.missingNumber(context: context)
        }
        guard let value = Double(tokens[index]), value.isFinite else {
            throw DEFError.invalidNumber(context: context, token: tokens[index])
        }
        return value
    }

    private static func previousRoutePoint(_ points: [IRPoint], axis: String, context: String) throws -> Int32 {
        guard let point = points.last else {
            throw DEFError.missingNumber(context: context)
        }
        return axis == "x" ? point.x : point.y
    }

    private static func skip(_ token: String, _ tokens: [String], _ i: Int) -> Int {
        if i < tokens.count && tokens[i] == token { return i + 1 }
        return i
    }

    private static func skipToSemicolon(_ tokens: [String], _ start: Int) -> Int {
        var i = start
        while i < tokens.count && tokens[i] != ";" { i += 1 }
        return skip(";", tokens, i)
    }

    private static func unquote(_ s: String) -> String {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func parseProperties(_ tokens: [String], from start: Int) -> ([DEFProperty], Int) {
        var i = start
        var props: [DEFProperty] = []
        while i + 1 < tokens.count && tokens[i] != ";" && tokens[i] != "+" {
            let key = tokens[i]; i += 1
            let value = unquote(tokens[i]); i += 1
            props.append(DEFProperty(key: key, value: value))
        }
        return (props, i)
    }
}
