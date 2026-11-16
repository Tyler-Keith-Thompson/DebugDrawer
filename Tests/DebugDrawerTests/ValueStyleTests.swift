@testable import DebugDrawer
import Testing

@Suite
struct ValueStyleTests {
    @Test("The automatic style sets words in the system font",
          arguments: ["Not Supported", "None", "Always", "Low", "AC Power", "Battery", "Not attached", "Wi-Fi", "Measuring…", "—", ""])
    func automaticWords(value: String) {
        let sut = DebugDrawerValueStyle.automatic

        let actual = sut.isCode(value)

        #expect(actual == false)
    }

    @Test("The automatic style sets figures, versions, paths and identifiers monospaced",
          arguments: [
              "63.5 MB", "1.4.2 (88)", "com.example.orders", "arm64", "/v1/users",
              "user@example.com", "a=b", "[REDACTED]", "snake_case", "12:04"
          ])
    func automaticCode(value: String) {
        let sut = DebugDrawerValueStyle.automatic

        let actual = sut.isCode(value)

        #expect(actual == true)
    }

    @Test("The text style sets any value in the system font, and the code style any value monospaced",
          arguments: ["gzip", "1.4.2", ""])
    func explicitStyles(value: String) {
        let text = DebugDrawerValueStyle.text
        let code = DebugDrawerValueStyle.code

        let actualText = text.isCode(value)
        let actualCode = code.isCode(value)

        #expect(actualText == false)
        #expect(actualCode == true)
    }
}
