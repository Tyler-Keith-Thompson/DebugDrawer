// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct StyleVocabularyTests {
        @Test("On the Mac each text role takes its compact text style; only values and code are monospaced")
        func typeScaleOnTheMac() {
            let expected: [DebugDrawerTextStyle: Font] = [
                .title: .callout.bold(),
                .heading: .subheadline.weight(.semibold),
                .body: .body,
                .label: .subheadline,
                .value: .system(.subheadline, design: .monospaced).monospacedDigit(),
                .code: .system(.subheadline, design: .monospaced),
                .secondary: .subheadline
            ]

            let actual = Dictionary(uniqueKeysWithValues: DebugDrawerTextStyle.allCases.map { ($0, $0.font) })

            #expect(actual == expected)
        }

        @Test("A button styled primary, secondary or destructive keeps that style and still runs its action",
              arguments: [DebugDrawerButtonStyle.Kind.primary, .secondary, .destructive, .borderless, .plain])
        func buttonStyles(kind: DebugDrawerButtonStyle.Kind) throws {
            var pressed = 0
            let sut = Button("Send") { pressed += 1 }
                .debugDrawerButtonStyle(DebugDrawerButtonStyle(kind: kind))

            let style = try #require(try sut.inspect().button().buttonStyle() as? DebugDrawerButtonStyle)
            try sut.inspect().button().tap()

            #expect(style.kind == kind)
            #expect(pressed == 1)
        }

        @Test("On the Mac a push button is at least 22 points tall, as Xcode's are")
        func buttonHeightOnTheMac() throws {
            let sut = DebugDrawerButtonStyle.secondary
            let expected: CGFloat = 22

            let actual = try sut.inspect(isPressed: false).find(ViewType.StyleConfiguration.Label.self).flexFrame().minHeight

            #expect(actual == expected)
        }

        @Test("An action row gives its buttons the secondary style, everyday ones before the one kept apart")
        func actionRow() throws {
            let sut = DebugDrawerActionRow {
                Button("Copy") {}
                Button("Refresh") {}
            } trailing: {
                Button("Delete All", role: .destructive) {}
                    .debugDrawerButtonStyle(.destructive)
            }
            let expectedTitles = ["Copy", "Refresh", "Delete All"]

            let titles = try sut.inspect().findAll(ViewType.Button.self).map { try $0.labelView().text().string() }
            let rowStyle = try #require(try sut.inspect().find(ViewType.Group.self).buttonStyle() as? DebugDrawerButtonStyle)

            #expect(titles == expectedTitles)
            #expect(rowStyle.kind == .secondary)
        }

        @Test("An action row of buttons that fit lays them in one line; at accessibility sizes it stacks them")
        func actionRowStacksAtAccessibilitySizes() throws {
            func row(_ size: DynamicTypeSize) -> some View {
                DebugDrawerActionRow {
                    Button("Copy") {}
                }
                .environment(\.dynamicTypeSize, size)
            }

            let stacked = try row(.accessibility3).inspect().findAll(ViewType.VStack.self)
            let inline = try row(.large).inspect().findAll(ViewType.VStack.self)

            #expect(!stacked.isEmpty)
            #expect(inline.isEmpty)
        }

        @Test("A section's title is a heading, above its rows and its note")
        func section() throws {
            let sut = DebugDrawerSection("Build") {
                DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
            } footer: {
                Text("From the Info.plist.")
            }
            let expected = ["Build", "Version", "1.4.2 (88)", "From the Info.plist."]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let heading = try sut.inspect().find(text: "Build").accessibilityTraits()

            #expect(texts == expected)
            #expect(heading.contains(.isHeader))
        }

        @Test("A section with no title has no heading")
        func untitledSection() throws {
            let sut = DebugDrawerSection {
                DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
            }
            let expected = ["Version", "1.4.2 (88)"]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("A toggle row's switch is labelled with the row's title and changes the setting")
        func toggleRow() throws {
            var isOn = false
            let binding = Binding(get: { isOn }, set: { isOn = $0 })
            let sut = DebugDrawerRow("Spoof Location", systemImage: "location", isOn: binding)

            let toggle = try sut.inspect().find(ViewType.Toggle.self)
            let label = try toggle.labelView().text().string()
            try toggle.tap()

            #expect(label == "Spoof Location")
            #expect(isOn)
        }

        @Test("A row shows its title, its details and its accessory, its icon hidden from VoiceOver")
        func row() throws {
            let sut = DebugDrawerRow("Camera", systemImage: "camera") {
                Text("Scans receipts")
            } accessory: {
                Text("Allowed")
            }
            let expected = ["Camera", "Allowed", "Scans receipts"]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let iconHidden = try sut.inspect().find(ViewType.Image.self) { try $0.actualImage().name() == "camera" }.accessibilityHidden()

            #expect(texts == expected)
            #expect(iconHidden)
        }

        @Test("An action row inside a row's details shows the row's own actions")
        func actionRowInsideARow() throws {
            var requested = 0
            let sut = DebugDrawerRow("Camera") {
                DebugDrawerActionRow {
                    Button("Request") { requested += 1 }
                        .debugDrawerButtonStyle(.primary)
                }
            } accessory: {
                EmptyView()
            }

            try sut.inspect().find(button: "Request").tap()

            #expect(requested == 1)
        }

        @Test("Each issue glyph reads as its severity and has a shape of its own, so none relies on color",
              arguments: [
                  (DebugDrawerIssueGlyph.Severity.error, "Error", "exclamationmark.octagon.fill"),
                  (.warning, "Warning", "exclamationmark.triangle.fill"),
                  (.ok, "OK", "checkmark.circle.fill"),
                  (.neutral, "Unknown", "questionmark.circle.fill")
              ])
        func issueGlyph(severity: DebugDrawerIssueGlyph.Severity, expectedLabel: String, expectedSymbol: String) throws {
            let sut = DebugDrawerIssueGlyph(severity)

            let image = try sut.inspect().find(ViewType.Image.self)
            let label = try image.accessibilityLabel().string()
            let symbol = try image.actualImage().name()

            #expect(label == expectedLabel)
            #expect(symbol == expectedSymbol)
        }

        @Test("An issue row reads its title and status as one line, its glyph hidden beside the word, then its subline and details")
        func issueRow() throws {
            let sut = DebugDrawerIssueRow("Camera", status: "Denied", severity: .error, subline: "NSCameraUsageDescription") {
                Text("Scans receipts")
            }
            let expected = ["Camera — Denied", "NSCameraUsageDescription", "Scans receipts"]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let glyphHidden = try sut.inspect().find(DebugDrawerIssueGlyph.self).accessibilityHidden()

            #expect(texts == expected)
            #expect(glyphHidden)
        }

        @Test("An issue row with no status lets VoiceOver read its glyph")
        func issueRowWithoutStatus() throws {
            let sut = DebugDrawerIssueRow("Local Network", severity: .neutral)
            let expected = ["Local Network"]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let glyphHidden = try sut.inspect().find(DebugDrawerIssueGlyph.self).accessibilityHidden()

            #expect(texts == expected)
            #expect(!glyphHidden)
        }

        @Test("A gauge row reads its label, its value and how full it is", arguments: [
            (0.38, "38%"), (-0.5, "0%"), (1.7, "100%")
        ])
        func gaugeRow(fraction: Double, expectedPercent: String) throws {
            let sut = DebugDrawerGaugeRow("CPU", value: "12 ms", fraction: fraction)
            let expectedLabel = "CPU"
            let expectedValue = "12 ms, \(expectedPercent)"

            let label = try sut.inspect().find(text: expectedLabel).string()
            let value = sut.spokenValue

            #expect(label == expectedLabel)
            #expect(value == expectedValue)
        }

        @Test("A stack frame names its index, symbol and binary, and says when it is the app's code")
        func stackFrame() throws {
            let sut = DebugDrawerStackFrameRow(index: 3, symbol: "OrdersViewModel.load()", image: "Example", isOwnCode: true)
            let expected = "Frame 3, OrdersViewModel.load(), in Example, the app's code"

            let actual = sut.spokenLabel

            #expect(actual == expected)
        }

        @Test("A stack frame's symbol keeps to two lines; the selected frame shows it whole", arguments: [
            (false, 2 as Int?),
            (true, nil as Int?)
        ])
        func stackFrameSymbolLines(isSelected: Bool, expected: Int?) throws {
            let symbol = "$s14ExampleApp_iOS24DebugDrawerExampleiOSAppV7SwiftUI0B0AadEPxycfCTW"
            let sut = DebugDrawerStackFrameRow(index: 3, symbol: symbol, image: "Example", isOwnCode: true, isSelected: isSelected)

            let actual = try sut.inspect().find(text: symbol).lineLimit()

            #expect(actual == expected)
        }

        @Test("While Show only my code is on, a system frame draws nothing and the app's frames still show")
        func ownCodeOnly() throws {
            let system = DebugDrawerStackFrameRow(index: 0, symbol: "swift_retain", image: "libswiftCore.dylib", isOwnCode: false)
                .environment(\.debugDrawerShowsOnlyOwnCode, true)
            let own = DebugDrawerStackFrameRow(index: 1, symbol: "main", image: "Example", isOwnCode: true)
                .environment(\.debugDrawerShowsOnlyOwnCode, true)

            let systemTexts = try system.inspect().findAll(ViewType.Text.self)
            let ownTexts = try own.inspect().findAll(ViewType.Text.self)

            #expect(systemTexts.isEmpty)
            #expect(!ownTexts.isEmpty)
        }

        @Test("A type badge row badges an app A, a framework F and a dylib D, read to VoiceOver by name", arguments: [
            (DebugDrawerTypeBadgeRow.Kind.app, "A", "App"),
            (.framework, "F", "Framework"),
            (.dylib, "D", "Dynamic library")
        ])
        func typeBadge(kind: DebugDrawerTypeBadgeRow.Kind, expectedLetter: String, expectedName: String) throws {
            let sut = DebugDrawerTypeBadgeRow("Charts", kind: kind, path: "/Frameworks/Charts.framework/Charts", version: "5.1.0")
            let expectedTexts = [expectedLetter, "Charts", "5.1.0", "/Frameworks/Charts.framework/Charts"]

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

            let name = try sut.inspect().find(text: expectedLetter).accessibilityLabel().string()

            #expect(texts == expectedTexts)
            #expect(name == expectedName)
        }

        @Test("A code block shows its lines")
        func codeBlock() throws {
            let sut = DebugDrawerCodeBlock {
                Text("0 main")
                Text("1 start")
            }
            let expected = ["0 main", "1 start"]

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(actual == expected)
        }

        @Test("A text field in the drawer's style keeps its placeholder and its text")
        func textFieldStyle() throws {
            var text = ""
            let binding = Binding(get: { text }, set: { text = $0 })
            let sut = TextField("Filter", text: binding).debugDrawerTextFieldStyle()

            try sut.inspect().find(ViewType.TextField.self).setInput("libSystem")
            let placeholder = try sut.inspect().find(ViewType.TextField.self).labelView().text().string()

            #expect(text == "libSystem")
            #expect(placeholder == "Filter")
        }
    }
#endif
