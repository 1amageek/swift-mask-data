import Foundation
import CircuiteFoundation
import LayoutIR
import Testing

@Suite("IRLibrary database-unit scale")
struct IRLibraryDatabaseUnitScaleTests {
    @Test("Library retains the shared validated database-unit scale")
    func retainsDatabaseUnitScale() throws {
        let scale = try DatabaseUnitScale(
            databaseUnitsPerMicrometer: 2_000.5
        )
        let library = IRLibrary(name: "TEST", databaseUnitScale: scale)

        #expect(library.databaseUnitScale == scale)
    }

    @Test("Invalid scales are rejected before library construction")
    func rejectsInvalidScale() {
        #expect(throws: DatabaseUnitScaleError.self) {
            _ = try DatabaseUnitScale(databaseUnitsPerMicrometer: 0)
        }
    }

    @Test("Library scale survives Codable round-trip")
    func codableRoundTripPreservesDatabaseUnitScale() throws {
        let scale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 2_000)
        let library = IRLibrary(name: "TEST", databaseUnitScale: scale)

        let encoded = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(IRLibrary.self, from: encoded)

        #expect(decoded.databaseUnitScale == scale)
    }
}
