import Testing
@testable import GDSII

@Suite("GDSII Placeholder")
struct GDSIIPlaceholderTests {
    @Test func moduleImports() {
        #expect(GDSRecordType.header.rawValue == 0x00)
    }
}
