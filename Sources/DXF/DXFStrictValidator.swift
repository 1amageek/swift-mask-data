import Foundation

enum DXFStrictValidator {
    private static let supportedEntities: Set<String> = [
        "LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "ELLIPSE",
        "SPLINE", "HATCH", "TEXT", "MTEXT", "ATTDEF", "INSERT", "SOLID"
    ]
    private static let structuralRecords: Set<String> = [
        "SECTION", "ENDSEC", "EOF", "BLOCK", "ENDBLK", "VERTEX", "SEQEND",
        "TABLE", "ENDTAB", "LAYER", "LTYPE", "STYLE", "DIMSTYLE", "APPID",
        "BLOCK_RECORD", "VPORT", "UCS", "VIEW", "CLASS"
    ]

    static func validate(
        _ groups: [DXFGroup],
        circleSegments: Int,
        databaseUnitsPerMicrometer: Double
    ) throws {
        guard circleSegments >= 4 else {
            throw DXFError.invalidStructure("circleSegments must be at least 4")
        }
        try validateNumbers(groups, databaseUnitsPerMicrometer: databaseUnitsPerMicrometer)
        try validateStructureAndEntities(groups)
    }

    private static func validateNumbers(
        _ groups: [DXFGroup],
        databaseUnitsPerMicrometer: Double
    ) throws {
        var context = "document"
        for group in groups {
            if group.code == 0 {
                context = group.value
                continue
            }
            if isFloatingPointCode(group.code) {
                guard let number = Double(group.value), number.isFinite else {
                    throw DXFError.invalidNumber(entity: context, groupCode: group.code, value: group.value)
                }
                if (10...39).contains(group.code) {
                    let coordinate = number * databaseUnitsPerMicrometer
                    guard coordinate >= Double(Int32.min), coordinate <= Double(Int32.max) else {
                        throw DXFError.numberOutOfRange(
                            entity: context,
                            groupCode: group.code,
                            value: group.value
                        )
                    }
                }
            } else if isIntegerCode(group.code) {
                guard Int64(group.value) != nil else {
                    throw DXFError.invalidNumber(entity: context, groupCode: group.code, value: group.value)
                }
            }
        }
    }

    private static func validateStructureAndEntities(_ groups: [DXFGroup]) throws {
        var index = 0
        var section: String?
        var blockName: String?
        var inPolyline = false
        var polylineVertexCount = 0
        var polylineIsClosed = false
        var sawEOF = false

        while index < groups.count {
            let group = groups[index]
            guard group.code == 0 else {
                index += 1
                continue
            }
            let end = nextRecordIndex(after: index, in: groups)
            let properties = Array(groups[(index + 1)..<end])
            switch group.value {
            case "SECTION":
                guard section == nil, let name = value(2, in: properties), !name.isEmpty else {
                    throw DXFError.invalidStructure("SECTION must be named and cannot be nested")
                }
                section = name
            case "ENDSEC":
                guard section != nil else { throw DXFError.invalidStructure("ENDSEC has no matching SECTION") }
                guard blockName == nil, !inPolyline else {
                    throw DXFError.invalidStructure("SECTION ended while a nested structure was open")
                }
                section = nil
            case "EOF":
                guard section == nil, blockName == nil, !inPolyline else {
                    throw DXFError.invalidStructure("EOF occurred before nested structures were closed")
                }
                guard end == groups.count else { throw DXFError.invalidStructure("records occur after EOF") }
                sawEOF = true
            case "BLOCK":
                guard section == "BLOCKS", blockName == nil, let name = value(2, in: properties), !name.isEmpty else {
                    throw DXFError.invalidStructure("BLOCK is misplaced or unnamed")
                }
                blockName = name
            case "ENDBLK":
                guard blockName != nil else { throw DXFError.invalidStructure("ENDBLK has no matching BLOCK") }
                blockName = nil
            case "POLYLINE":
                guard section == "ENTITIES" || blockName != nil, !inPolyline else {
                    throw DXFError.invalidStructure("POLYLINE is misplaced or nested")
                }
                inPolyline = true
                polylineVertexCount = 0
                polylineIsClosed = value(70, in: properties).flatMap(Int.init).map { $0 & 1 != 0 } ?? false
            case "VERTEX":
                guard inPolyline else { throw DXFError.invalidStructure("VERTEX occurs outside POLYLINE") }
                try require([10, 20], entity: group.value, properties: properties)
                polylineVertexCount += 1
            case "SEQEND":
                guard inPolyline else { throw DXFError.invalidStructure("SEQEND has no matching POLYLINE") }
                let minimumVertexCount = polylineIsClosed ? 3 : 2
                guard polylineVertexCount >= minimumVertexCount else {
                    throw DXFError.invalidGeometry(
                        "POLYLINE requires at least \(minimumVertexCount) complete vertices"
                    )
                }
                inPolyline = false
            default:
                if supportedEntities.contains(group.value) {
                    guard section == "ENTITIES" || blockName != nil else {
                        throw DXFError.invalidStructure("\(group.value) occurs outside an entity container")
                    }
                    try validateEntity(group.value, properties: properties)
                } else if !structuralRecords.contains(group.value) {
                    throw DXFError.unsupportedEntity(group.value)
                }
            }
            index = end
        }
        guard sawEOF else { throw DXFError.invalidStructure("EOF record is missing") }
        guard section == nil, blockName == nil, !inPolyline else {
            throw DXFError.invalidStructure("document contains an unterminated structure")
        }
    }

    private static func validateEntity(_ entity: String, properties: [DXFGroup]) throws {
        switch entity {
        case "LINE": try require([10, 20, 11, 21], entity: entity, properties: properties)
        case "LWPOLYLINE":
            let xs = properties.filter { $0.code == 10 }.count
            let ys = properties.filter { $0.code == 20 }.count
            guard xs == ys, xs >= 2 else { throw DXFError.invalidStructure("LWPOLYLINE requires at least two complete vertices") }
        case "CIRCLE":
            try require([10, 20, 40], entity: entity, properties: properties)
            guard let radius = number(40, in: properties), radius > 0 else {
                throw DXFError.invalidNumber(entity: entity, groupCode: 40, value: value(40, in: properties) ?? "")
            }
        case "ARC":
            try require([10, 20, 40, 50, 51], entity: entity, properties: properties)
            guard let radius = number(40, in: properties), radius > 0 else {
                throw DXFError.invalidNumber(entity: entity, groupCode: 40, value: value(40, in: properties) ?? "")
            }
        case "ELLIPSE":
            try require([10, 20, 11, 21, 40], entity: entity, properties: properties)
            guard let majorX = number(11, in: properties),
                  let majorY = number(21, in: properties),
                  let ratio = number(40, in: properties),
                  majorX != 0 || majorY != 0,
                  ratio > 0 else {
                throw DXFError.invalidGeometry("ELLIPSE has a zero axis or non-positive ratio")
            }
        case "SPLINE":
            let controlX = properties.filter { $0.code == 10 }.count
            let controlY = properties.filter { $0.code == 20 }.count
            let fitX = properties.filter { $0.code == 11 }.count
            let fitY = properties.filter { $0.code == 21 }.count
            guard controlX == controlY, fitX == fitY else {
                throw DXFError.invalidStructure("SPLINE contains incomplete point pairs")
            }
            let controlPoints = controlX
            let fitPoints = fitX
            guard max(controlPoints, fitPoints) >= 2 else { throw DXFError.invalidStructure("SPLINE requires at least two complete points") }
        case "TEXT", "MTEXT":
            try require([10, 20, 1], entity: entity, properties: properties)
            guard let text = value(1, in: properties), !text.isEmpty else {
                throw DXFError.invalidGeometry("\(entity) contains empty text")
            }
        case "ATTDEF":
            try require([10, 20, 2], entity: entity, properties: properties)
            guard let tag = value(2, in: properties), !tag.isEmpty else {
                throw DXFError.invalidGeometry("ATTDEF contains an empty tag")
            }
        case "INSERT":
            try require([2], entity: entity, properties: properties)
            let scaleX = number(41, in: properties) ?? 1
            let scaleY = number(42, in: properties) ?? 1
            guard scaleX != 0, scaleY != 0 else {
                throw DXFError.unsupportedTransform(entity: entity, reason: "zero scale")
            }
            guard scaleY > 0, abs(abs(scaleX) - abs(scaleY)) < 1e-9 else {
                throw DXFError.unsupportedTransform(entity: entity, reason: "non-uniform or Y-axis mirrored scale")
            }
            for code in [70, 71] {
                if let text = value(code, in: properties) {
                    guard let count = Int(text), (1...Int(Int16.max)).contains(count) else {
                        throw DXFError.invalidNumber(entity: entity, groupCode: code, value: text)
                    }
                }
            }
        case "SOLID": try require([10, 20, 11, 21, 12, 22], entity: entity, properties: properties)
        case "HATCH": try validateHatch(properties)
        default: break
        }
    }

    private static func validateHatch(_ properties: [DXFGroup]) throws {
        guard let declaredPathCount = value(91, in: properties).flatMap(Int.init),
              declaredPathCount > 0 else {
            throw DXFError.missingRequiredGroup(entity: "HATCH", groupCode: 91)
        }
        let pathStarts = properties.indices.filter { properties[$0].code == 92 }
        guard pathStarts.count == declaredPathCount else {
            throw DXFError.invalidStructure(
                "HATCH boundary path count does not match group 91"
            )
        }

        for (offset, start) in pathStarts.enumerated() {
            let end = offset + 1 < pathStarts.count ? pathStarts[offset + 1] : properties.endIndex
            let path = Array(properties[start..<end])
            guard let pathType = value(92, in: path).flatMap(Int.init) else {
                throw DXFError.invalidNumber(entity: "HATCH", groupCode: 92, value: value(92, in: path) ?? "")
            }
            if pathType & 2 != 0 {
                try validateHatchPolyline(path)
            } else {
                try validateHatchEdges(path)
            }
        }
    }

    private static func validateHatchPolyline(_ path: [DXFGroup]) throws {
        try require([72, 73, 93], entity: "HATCH", properties: path)
        guard value(73, in: path).flatMap(Int.init) == 1 else {
            throw DXFError.invalidGeometry("HATCH polyline boundary must be closed")
        }
        guard let declaredVertexCount = value(93, in: path).flatMap(Int.init),
              declaredVertexCount >= 3 else {
            throw DXFError.invalidGeometry("HATCH polyline boundary requires at least three vertices")
        }
        let xCount = path.filter { $0.code == 10 }.count
        let yCount = path.filter { $0.code == 20 }.count
        guard xCount == declaredVertexCount, yCount == declaredVertexCount else {
            throw DXFError.invalidStructure(
                "HATCH polyline vertex count does not match group 93 or contains incomplete coordinate pairs"
            )
        }
        for index in path.indices where path[index].code == 10 {
            guard path.indices.contains(index + 1), path[index + 1].code == 20 else {
                throw DXFError.invalidStructure(
                    "HATCH polyline coordinates must be ordered as complete group 10/20 pairs"
                )
            }
        }
        for index in path.indices where path[index].code == 20 {
            guard index > path.startIndex, path[index - 1].code == 10 else {
                throw DXFError.invalidStructure(
                    "HATCH polyline coordinates must be ordered as complete group 10/20 pairs"
                )
            }
        }
    }

    private static func validateHatchEdges(_ path: [DXFGroup]) throws {
        guard let declaredEdgeCount = value(93, in: path).flatMap(Int.init),
              declaredEdgeCount >= 1 else {
            throw DXFError.missingRequiredGroup(entity: "HATCH", groupCode: 93)
        }
        let edgeStarts = path.indices.filter { path[$0].code == 72 }
        guard edgeStarts.count == declaredEdgeCount else {
            throw DXFError.invalidStructure("HATCH edge count does not match group 93")
        }
        for (offset, start) in edgeStarts.enumerated() {
            let end = offset + 1 < edgeStarts.count ? edgeStarts[offset + 1] : path.endIndex
            let edge = Array(path[start..<end])
            guard let edgeType = value(72, in: edge).flatMap(Int.init) else {
                throw DXFError.invalidNumber(entity: "HATCH", groupCode: 72, value: value(72, in: edge) ?? "")
            }
            switch edgeType {
            case 1:
                try require([10, 20, 11, 21], entity: "HATCH line edge", properties: edge)
            case 2:
                try require([10, 20, 40, 50, 51, 73], entity: "HATCH arc edge", properties: edge)
                guard let radius = number(40, in: edge), radius > 0 else {
                    throw DXFError.invalidGeometry("HATCH arc edge radius must be positive")
                }
            case 3:
                try require([10, 20, 11, 21, 40, 50, 51, 73], entity: "HATCH ellipse edge", properties: edge)
                guard let majorX = number(11, in: edge),
                      let majorY = number(21, in: edge),
                      let ratio = number(40, in: edge),
                      majorX != 0 || majorY != 0,
                      ratio > 0 else {
                    throw DXFError.invalidGeometry("HATCH ellipse edge has invalid axes")
                }
            default:
                throw DXFError.unsupportedEntity("HATCH edge type \(edgeType)")
            }
        }
    }

    private static func require(_ codes: [Int], entity: String, properties: [DXFGroup]) throws {
        for code in codes where !properties.contains(where: { $0.code == code }) {
            throw DXFError.missingRequiredGroup(entity: entity, groupCode: code)
        }
    }

    private static func value(_ code: Int, in properties: [DXFGroup]) -> String? {
        properties.first(where: { $0.code == code })?.value
    }

    private static func number(_ code: Int, in properties: [DXFGroup]) -> Double? {
        value(code, in: properties).flatMap(Double.init)
    }

    private static func nextRecordIndex(after index: Int, in groups: [DXFGroup]) -> Int {
        var next = index + 1
        while next < groups.count, groups[next].code != 0 { next += 1 }
        return next
    }

    private static func isFloatingPointCode(_ code: Int) -> Bool {
        (10...59).contains(code) || (110...149).contains(code) || (210...239).contains(code) ||
            (460...469).contains(code) || (1010...1059).contains(code)
    }

    private static func isIntegerCode(_ code: Int) -> Bool {
        (60...99).contains(code) || (160...179).contains(code) || (270...299).contains(code) ||
            (370...459).contains(code) || (1060...1071).contains(code)
    }
}
