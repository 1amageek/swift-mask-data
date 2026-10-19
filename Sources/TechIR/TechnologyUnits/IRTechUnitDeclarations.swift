/// Optional raw precision declarations, independent of distance database resolution.
public struct IRTechUnitDeclarations: Sendable, Hashable, Codable {
    public var timeNanoseconds: Double?
    public var capacitancePicofarads: Double?
    public var resistanceOhms: Double?
    public var powerMilliwatts: Double?
    public var currentMilliamps: Double?
    public var voltageVolts: Double?
    public var frequencyMegahertz: Double?

    public init(timeNanoseconds: Double? = nil, capacitancePicofarads: Double? = nil,
                resistanceOhms: Double? = nil, powerMilliwatts: Double? = nil,
                currentMilliamps: Double? = nil, voltageVolts: Double? = nil,
                frequencyMegahertz: Double? = nil) {
        self.timeNanoseconds = timeNanoseconds
        self.capacitancePicofarads = capacitancePicofarads
        self.resistanceOhms = resistanceOhms
        self.powerMilliwatts = powerMilliwatts
        self.currentMilliamps = currentMilliamps
        self.voltageVolts = voltageVolts
        self.frequencyMegahertz = frequencyMegahertz
    }
}
