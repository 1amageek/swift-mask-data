import CircuiteFoundation

func testDatabaseUnitScale(
    databaseUnitsPerMicrometer: Double = 1_000
) throws -> DatabaseUnitScale {
    try DatabaseUnitScale(
        databaseUnitsPerMicrometer: databaseUnitsPerMicrometer
    )
}
