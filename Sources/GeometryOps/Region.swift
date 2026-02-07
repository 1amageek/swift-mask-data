import LayoutIR

/// A collection of polygons on a single layer, supporting boolean operations and DRC checks.
public struct Region: Hashable, Sendable {
    public var layer: Int16
    public var polygons: [IRBoundary]

    public init(layer: Int16 = 0, polygons: [IRBoundary] = []) {
        self.layer = layer
        self.polygons = polygons
    }

    // MARK: - Utilities

    public var isEmpty: Bool {
        polygons.isEmpty
    }

    /// Total signed area of all polygons (shoelace formula).
    public var area: Int64 {
        polygons.reduce(0) { $0 + PolygonUtils.area($1.points) }
    }

    /// Total number of edges across all polygons.
    public var edgeCount: Int {
        polygons.reduce(0) { total, poly in
            let n = poly.points.count
            return total + (n > 1 ? n - 1 : 0)
        }
    }

    /// Axis-aligned bounding box.
    public var boundingBox: (minX: Int32, minY: Int32, maxX: Int32, maxY: Int32)? {
        guard !polygons.isEmpty else { return nil }
        var minX = Int32.max, minY = Int32.max
        var maxX = Int32.min, maxY = Int32.min
        for poly in polygons {
            for p in poly.points {
                if p.x < minX { minX = p.x }
                if p.y < minY { minY = p.y }
                if p.x > maxX { maxX = p.x }
                if p.y > maxY { maxY = p.y }
            }
        }
        return (minX, minY, maxX, maxY)
    }

    // MARK: - Boolean Operations

    public func and(_ other: Region) -> Region {
        RegionBoolean.perform(.and, self, other)
    }

    public func or(_ other: Region) -> Region {
        RegionBoolean.perform(.or, self, other)
    }

    public func xor(_ other: Region) -> Region {
        RegionBoolean.perform(.xor, self, other)
    }

    public func not(_ other: Region) -> Region {
        RegionBoolean.perform(.not, self, other)
    }

    // MARK: - Sizing

    public func sized(by amount: Int32) -> Region {
        RegionSizing.size(self, by: amount)
    }

    public func sized(by amount: Int32, cornerMode: CornerMode) -> Region {
        RegionSizing.size(self, by: amount, cornerMode: cornerMode)
    }

    // MARK: - DRC

    public func widthViolations(minWidth: Int32) -> [IREdgePair] {
        DRCCheck.widthCheck(self, minWidth: minWidth)
    }

    public func widthViolations(minWidth: Int32, metric: DRCMetric) -> [IREdgePair] {
        DRCCheck.widthCheck(self, minWidth: minWidth, metric: metric)
    }

    public func spaceViolations(to other: Region, minSpace: Int32) -> [IREdgePair] {
        DRCCheck.spaceCheck(self, other, minSpace: minSpace)
    }

    public func spaceViolations(to other: Region, minSpace: Int32, metric: DRCMetric) -> [IREdgePair] {
        DRCCheck.spaceCheck(self, other, minSpace: minSpace, metric: metric)
    }

    public func enclosureViolations(inner: Region, minEnclosure: Int32) -> [IREdgePair] {
        DRCCheck.enclosureCheck(outer: self, inner: inner, minEnclosure: minEnclosure)
    }

    public func enclosureViolations(inner: Region, minEnclosure: Int32, metric: DRCMetric) -> [IREdgePair] {
        DRCCheck.enclosureCheck(outer: self, inner: inner, minEnclosure: minEnclosure, metric: metric)
    }

    public func notchViolations(minNotch: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        DRCCheck.notchCheck(self, minNotch: minNotch, metric: metric)
    }

    public func separationViolations(to other: Region, minSeparation: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        DRCCheck.separationCheck(self, other, minSeparation: minSeparation, metric: metric)
    }

    public func gridViolations(gridX: Int32, gridY: Int32) -> [IREdgePair] {
        DRCCheck.gridCheck(self, gridX: gridX, gridY: gridY)
    }

    public func angleViolations(allowedAngles: Set<Int>) -> [IREdgePair] {
        DRCCheck.angleCheck(self, allowedAngles: allowedAngles)
    }
}
