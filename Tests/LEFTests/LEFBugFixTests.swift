import Testing
import Foundation
@testable import LEF

@Suite("LEF Bug Fixes")
struct LEFBugFixTests {

    @Test func testDocumentLevelPropertyRoundTrip() throws {
        let original = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            properties: [
                LEFProperty(key: "MANUFACTURER", value: "ACME"),
                LEFProperty(key: "PROCESS", value: "7nm"),
            ]
        )
        let data = try LEFLibraryWriter.write(original)
        let result = try LEFLibraryReader.read(data)

        #expect(result.properties.count == 2)
        #expect(result.properties[0].key == "MANUFACTURER")
        #expect(result.properties[0].value == "ACME")
        #expect(result.properties[1].key == "PROCESS")
        #expect(result.properties[1].value == "7nm")
    }

    @Test func testQuotedPropertyValueRoundTrip() throws {
        let original = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            properties: [
                LEFProperty(key: "DESCRIPTION", value: "hello world"),
                LEFProperty(key: "NOTE", value: "multi word value here"),
            ]
        )
        let data = try LEFLibraryWriter.write(original)
        let text = String(data: data, encoding: .utf8)!
        // Verify the writer quotes multi-word values
        #expect(text.contains("PROPERTY DESCRIPTION \"hello world\" ;"))
        #expect(text.contains("PROPERTY NOTE \"multi word value here\" ;"))

        let result = try LEFLibraryReader.read(data)
        #expect(result.properties.count == 2)
        #expect(result.properties[0].key == "DESCRIPTION")
        #expect(result.properties[0].value == "hello world")
        #expect(result.properties[1].key == "NOTE")
        #expect(result.properties[1].value == "multi word value here")
    }
}
