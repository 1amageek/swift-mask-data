import TechIR

/// Invocation-local grammar and projection descriptors; key paths never enter shared storage.
struct LEFUnitStatement {
    let command: String
    let unit: String
    let keyPath: WritableKeyPath<IRTechUnitDeclarations, Double?>

    static var all: [Self] {
        [
            .init(command: "TIME", unit: "NANOSECONDS", keyPath: \.timeNanoseconds),
            .init(command: "CAPACITANCE", unit: "PICOFARADS", keyPath: \.capacitancePicofarads),
            .init(command: "RESISTANCE", unit: "OHMS", keyPath: \.resistanceOhms),
            .init(command: "POWER", unit: "MILLIWATTS", keyPath: \.powerMilliwatts),
            .init(command: "CURRENT", unit: "MILLIAMPS", keyPath: \.currentMilliamps),
            .init(command: "VOLTAGE", unit: "VOLTS", keyPath: \.voltageVolts),
            .init(command: "FREQUENCY", unit: "MEGAHERTZ", keyPath: \.frequencyMegahertz)
        ]
    }

    static func validateDatabase(_ value: Double) throws {
        guard [100.0, 200, 400, 800, 1000, 2000, 4000, 8000, 10000, 20000].contains(value) else {
            throw LEFError.invalidNumber(command: "DATABASE MICRONS", value: String(value))
        }
    }
}
