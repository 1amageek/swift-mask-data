public struct DEFDocument: Hashable, Sendable, Codable {
    public var version: String
    public var designName: String
    public var dbuPerMicron: Double
    public var dieArea: DEFDieArea?
    public var components: [DEFComponent]
    public var pins: [DEFPin]
    public var nets: [DEFNet]
    public var specialNets: [DEFSpecialNet]
    public var blockages: [DEFBlockage]
    public var tracks: [DEFTrack]
    public var gcellGrids: [DEFGCellGrid]
    public var regions: [DEFRegion]
    public var fills: [DEFFill]
    public var groups: [DEFGroup]
    public var viaDefs: [DEFViaDef]
    public var propertyDefinitions: [DEFPropertyDefinition]
    public var rows: [DEFRow]
    public var busbitChars: String?
    public var dividerChar: String?
    public var properties: [DEFProperty]

    public init(version: String = "5.8", designName: String = "",
                dbuPerMicron: Double = 1000,
                dieArea: DEFDieArea? = nil,
                components: [DEFComponent] = [], pins: [DEFPin] = [],
                nets: [DEFNet] = [], specialNets: [DEFSpecialNet] = [],
                blockages: [DEFBlockage] = [], tracks: [DEFTrack] = [],
                gcellGrids: [DEFGCellGrid] = [], regions: [DEFRegion] = [],
                fills: [DEFFill] = [], groups: [DEFGroup] = [],
                viaDefs: [DEFViaDef] = [],
                propertyDefinitions: [DEFPropertyDefinition] = [],
                rows: [DEFRow] = [],
                busbitChars: String? = nil, dividerChar: String? = nil,
                properties: [DEFProperty] = []) {
        self.version = version
        self.designName = designName
        self.dbuPerMicron = dbuPerMicron
        self.dieArea = dieArea
        self.components = components
        self.pins = pins
        self.nets = nets
        self.specialNets = specialNets
        self.blockages = blockages
        self.tracks = tracks
        self.gcellGrids = gcellGrids
        self.regions = regions
        self.fills = fills
        self.groups = groups
        self.viaDefs = viaDefs
        self.propertyDefinitions = propertyDefinitions
        self.rows = rows
        self.busbitChars = busbitChars
        self.dividerChar = dividerChar
        self.properties = properties
    }
}

/// Represents a ROW definition in DEF.
public struct DEFRow: Hashable, Sendable, Codable {
    public var rowName: String
    public var siteName: String
    public var originX: Int32
    public var originY: Int32
    public var orientation: DEFOrientation
    public var numX: Int32
    public var numY: Int32
    public var stepX: Int32
    public var stepY: Int32

    public init(rowName: String, siteName: String,
                originX: Int32, originY: Int32,
                orientation: DEFOrientation = .n,
                numX: Int32 = 1, numY: Int32 = 1,
                stepX: Int32 = 0, stepY: Int32 = 0) {
        self.rowName = rowName
        self.siteName = siteName
        self.originX = originX
        self.originY = originY
        self.orientation = orientation
        self.numX = numX
        self.numY = numY
        self.stepX = stepX
        self.stepY = stepY
    }
}
