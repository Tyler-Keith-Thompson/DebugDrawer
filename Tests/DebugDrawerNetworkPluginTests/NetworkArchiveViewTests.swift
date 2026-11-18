// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkArchiveViewTests {
        @Test("With nothing filtered out, the toolbar offers Export All and Import HAR…")
        func exportAll() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/", host: "example.com",
                path: "/", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let sut = NetworkToolbar(
                filterStatus: .constant(.all), clear: {}, export: NetworkArchiveFile(entries: [entry], redaction: .standard),
                isFiltered: false, importArchive: {}
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Export All") }
            #expect(throws: Never.self) { try view.find(button: "Import HAR…") }
            #expect((try? view.find(text: "Export Shown")) == nil)
        }

        @Test("While a filter hides some requests, the export says it holds only those shown")
        func exportShown() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://example.com/", host: "example.com",
                path: "/", requestHeaders: [:], requestBody: nil, statusCode: 500, isComplete: true
            )
            let sut = NetworkToolbar(
                filterStatus: .constant(.serverError), clear: {}, export: NetworkArchiveFile(entries: [entry], redaction: .standard),
                isFiltered: true, importArchive: {}
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "Export Shown") }
            #expect((try? view.find(text: "Export All")) == nil)
        }

        @Test("Import HAR… asks for a file, once")
        func importAsks() throws {
            var asked = 0
            let sut = NetworkToolbar(filterStatus: .constant(.all), clear: {}, importArchive: { asked += 1 })

            try sut.inspect().find(button: "Import HAR…").tap()

            #expect(asked == 1)
        }

        @Test("While imported requests show, Clear says it clears them")
        func clearImported() throws {
            let sut = NetworkToolbar(filterStatus: .constant(.all), clear: {}, importArchive: {}, source: .imported)
            let expected = "Clear imported requests"

            let actual = try sut.inspect().find(button: "Clear").accessibilityLabel().string()

            #expect(actual == expected)
        }

        @Test("Showing the imported requests names the file and how many requests it holds, read-only")
        func importedSource() throws {
            let sut = NetworkLogSourcePicker(source: .constant(.imported), fileName: "shop.example.com.har", count: 12)

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "shop.example.com.har") }
            #expect(throws: Never.self) { try view.find(text: "12, read-only") }
        }

        @Test("Showing the captured requests leaves the imported file's name out")
        func capturedSource() throws {
            let sut = NetworkLogSourcePicker(source: .constant(.captured), fileName: "shop.example.com.har", count: 12)

            let actual = try? sut.inspect().find(text: "shop.example.com.har")

            #expect(actual == nil)
        }

        @Test("An imported request offers Copy cURL and Mock This under More, but neither Resend nor Edit and Resend")
        func importedEntryReadOnly() throws {
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 0), method: "GET", url: "https://shop.example.com/api/cart",
                host: "shop.example.com", path: "/api/cart", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var mocked: [UUID] = []
            let sut = NetworkRequestDetail(entry: entry, redaction: .standard, onMock: { mocked.append($0.id) })

            let view = try sut.inspect()
            try view.find(button: "Mock This").tap()

            #expect(throws: Never.self) { try view.find(text: "Copy cURL") }
            #expect((try? view.find(button: "Resend")) == nil)
            #expect((try? view.find(button: "Edit and Resend…")) == nil)
            #expect(mocked == [entry.id])
        }
    }
#endif
