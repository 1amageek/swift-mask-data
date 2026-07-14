import CircuiteFoundation
import LayoutIR
import Testing

@Suite("IRUnits Foundation boundary")
struct IRUnitsFoundationTests {
    @Test("IR units can round-trip through the shared database scale")
    func roundTripsThroughDatabaseUnitScale() throws {
        let scale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 2_000.5)
        let units = IRUnits(scale: scale)

        #expect(units.dbuPerMicron == 2_000.5)
        #expect(try units.validatedScale == scale)
    }

    @Test("Invalid IR units are rejected at the shared boundary")
    func rejectsInvalidScale() {
        let units = IRUnits(dbuPerMicron: 0)

        #expect(throws: DatabaseUnitScaleError.self) {
            _ = try units.validatedScale
        }
    }
}
