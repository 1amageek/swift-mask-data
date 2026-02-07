public struct IRArrayRef: Hashable, Sendable, Codable {
    public var cellName: String
    public var transform: IRTransform
    public var columns: Int16
    public var rows: Int16
    /// Three reference points: [origin, column-vector-end, row-vector-end].
    public var referencePoints: [IRPoint]
    public var properties: [IRProperty]

    public init(
        cellName: String,
        transform: IRTransform = .identity,
        columns: Int16,
        rows: Int16,
        referencePoints: [IRPoint],
        properties: [IRProperty] = []
    ) {
        self.cellName = cellName
        self.transform = transform
        self.columns = columns
        self.rows = rows
        self.referencePoints = referencePoints
        self.properties = properties
    }
}
