/// Represents a TRACKS definition in DEF.
public struct DEFTrack: Hashable, Sendable, Codable {
    public var direction: TrackDirection
    public var start: Int32
    public var numTracks: Int32
    public var step: Int32
    public var layerNames: [String]

    public enum TrackDirection: String, Hashable, Sendable, Codable {
        case x = "X"
        case y = "Y"
    }

    public init(direction: TrackDirection, start: Int32, numTracks: Int32,
                step: Int32, layerNames: [String] = []) {
        self.direction = direction
        self.start = start
        self.numTracks = numTracks
        self.step = step
        self.layerNames = layerNames
    }
}

/// Represents a GCELLGRID definition in DEF.
public struct DEFGCellGrid: Hashable, Sendable, Codable {
    public var direction: DEFTrack.TrackDirection
    public var start: Int32
    public var numColumns: Int32
    public var step: Int32

    public init(direction: DEFTrack.TrackDirection, start: Int32,
                numColumns: Int32, step: Int32) {
        self.direction = direction
        self.start = start
        self.numColumns = numColumns
        self.step = step
    }
}
