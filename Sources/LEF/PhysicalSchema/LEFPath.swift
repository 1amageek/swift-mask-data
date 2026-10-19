/// Standard orthogonal LEF PATH with half-width endpoint extensions.
public struct LEFPath: Hashable, Sendable, Codable {
    public var width: Double
    public var points: [LEFPoint]

    public init(width: Double, points: [LEFPoint]) {
        self.width = width
        self.points = points
    }

    func validateGeometry() throws {
        guard width.isFinite, width > 0, !points.isEmpty,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw LEFError.invalidGeometry("PATH requires a finite positive width and at least one finite point")
        }
        for index in points.indices.dropFirst() {
            let first = points[index - 1], second = points[index]
            guard first != second, first.x == second.x || first.y == second.y else {
                throw LEFError.invalidGeometry("PATH segments must be nonzero and orthogonal")
            }
        }
    }
}
