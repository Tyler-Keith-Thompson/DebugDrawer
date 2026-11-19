#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerAccessibilityPlugin
    import Foundation
    import Testing

    /// Overrides kept in memory, in place of `AccessibilityOverrides.shared`.
    @MainActor
    private final class FakeOverrideStore: AccessibilityOverrideStore {
        let subject = PassthroughSubject<Void, Never>()
        let localeIdentifiers: [String]
        var values = AccessibilityOverrideValues() {
            willSet { subject.send() }
        }

        init(localeIdentifiers: [String] = []) {
            self.localeIdentifiers = localeIdentifiers
        }

        var changes: AnyPublisher<Void, Never> {
            subject.eraseToAnyPublisher()
        }
    }

    /// System settings a test sets, in place of the device's.
    @MainActor
    private final class FakeSystemSettings: AccessibilitySystemSettings {
        let subject = PassthroughSubject<Void, Never>()
        var values = AccessibilitySystemValues() {
            willSet { subject.send() }
        }

        var changes: AnyPublisher<Void, Never> {
            subject.eraseToAnyPublisher()
        }
    }

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, encoded and decoded, with no view and no shared state.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AccessibilityModelTests {
        @Test("The snapshot holds the store's overrides and locales and the system's settings")
        func snapshotReadsServices() {
            let overrides = FakeOverrideStore(localeIdentifiers: ["de", "fr"])
            overrides.values.colorScheme = .dark
            overrides.values.reduceMotion = false
            let system = FakeSystemSettings()
            system.values.boldText = true
            let sut = AccessibilityModel(overrides: overrides, system: system)

            let actual = sut.snapshot

            #expect(actual.overrides == overrides.values)
            #expect(actual.system == system.values)
            #expect(actual.availableLocales == ["de", "fr"])
        }

        @Test("A snapshot with every override set, system settings and locales encodes to JSON and decodes equal")
        func snapshotRoundTrips() throws {
            let overrides = FakeOverrideStore(localeIdentifiers: ["ar", "en", "fr"])
            overrides.values = AccessibilityOverrideValues(
                colorScheme: .light, dynamicTypeSize: .accessibility3, layoutDirection: .rightToLeft, locale: "ar",
                reduceMotion: true, increaseContrast: false, boldText: true, reduceTransparency: false,
                differentiateWithoutColor: true, invertColors: false
            )
            let system = FakeSystemSettings()
            system.values = AccessibilitySystemValues(reduceMotion: true, increaseContrast: true, invertColors: true)
            let snapshot = AccessibilityModel(overrides: overrides, system: system).snapshot

            let actual = try JSONDecoder().decode(AccessibilitySnapshot.self, from: JSONEncoder().encode(snapshot))

            #expect(actual == snapshot)
            #expect(actual.overrides.dynamicTypeSize == .accessibility3)
            #expect(actual.overrides.locale == "ar")
            #expect(actual.system.invertColors)
        }

        @Test("Commands encoded to JSON and decoded set each override through a direct transport, and nil returns it to the system's")
        func commandsRoundTrip() throws {
            let overrides = FakeOverrideStore()
            let sut = DebugDrawerPluginTransport.direct(to: AccessibilityModel(overrides: overrides, system: FakeSystemSettings()))
            let commands = [
                AccessibilityCommand(.setColorScheme(.dark)),
                AccessibilityCommand(.setDynamicTypeSize(.xxLarge)),
                AccessibilityCommand(.setLayoutDirection(.rightToLeft)),
                AccessibilityCommand(.setLocale("fr")),
                AccessibilityCommand(.setSetting(.boldText, true)),
                AccessibilityCommand(.setSetting(.invertColors, false)),
                AccessibilityCommand(.setSetting(.reduceMotion, true)),
                AccessibilityCommand(.setSetting(.reduceMotion, nil))
            ]
            let expected = AccessibilityOverrideValues(
                colorScheme: .dark, dynamicTypeSize: .xxLarge, layoutDirection: .rightToLeft, locale: "fr",
                boldText: true, invertColors: false
            )

            for command in commands {
                let decoded = try JSONDecoder().decode(AccessibilityCommand.self, from: JSONEncoder().encode(command))
                sut.send(decoded)
            }

            #expect(overrides.values == expected)
            #expect(sut.snapshot.overrides == expected)
        }

        @Test("Reset, encoded and decoded, clears every override")
        func resetRoundTrips() throws {
            let overrides = FakeOverrideStore()
            overrides.values = AccessibilityOverrideValues(colorScheme: .dark, locale: "fr", reduceTransparency: true)
            let sut = AccessibilityModel(overrides: overrides, system: FakeSystemSettings())
            let command = try JSONDecoder().decode(
                AccessibilityCommand.self, from: JSONEncoder().encode(AccessibilityCommand(.reset))
            )

            sut.perform(command)

            #expect(overrides.values == AccessibilityOverrideValues())
            #expect(!sut.snapshot.overrides.hasOverrides)
        }

        @Test("The model announces a change when the overrides or a system setting change")
        func announcesServiceChanges() {
            let overrides = FakeOverrideStore()
            let system = FakeSystemSettings()
            let sut = AccessibilityModel(overrides: overrides, system: system)
            var announcements = 0
            let subscription = sut.objectWillChange.sink { announcements += 1 }
            defer { subscription.cancel() }

            overrides.values.boldText = true
            system.values.reduceMotion = true

            #expect(announcements == 2)
            #expect(sut.snapshot.system.reduceMotion)
        }
    }

    extension SharedAccessibilityOverrides {
        // The shared overrides keep SwiftUI's types; these pin how they read and write as the
        // model's values.
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct AccessibilityOverridesStoreTests {
            @Test("The overrides read as the model's values, case for case")
            func sharedOverridesReadAsValues() {
                let overrides = AccessibilityOverrides(localizations: [])
                overrides.colorScheme = .dark
                overrides.dynamicTypeSize = .accessibility5
                overrides.layoutDirection = .leftToRight
                overrides.locale = Locale(identifier: "fr")
                overrides.differentiateWithoutColor = false
                let expected = AccessibilityOverrideValues(
                    colorScheme: .dark, dynamicTypeSize: .accessibility5, layoutDirection: .leftToRight, locale: "fr",
                    differentiateWithoutColor: false
                )

                let actual = overrides.values

                #expect(actual == expected)
            }

            @Test("A model's command sets the shared overrides that .debugAccessibilityOverrides() applies")
            func commandsWriteSharedOverrides() {
                let overrides = AccessibilityOverrides.shared
                let sut = AccessibilityModel(overrides: overrides, system: _AccessibilitySystemSettings())

                sut.perform(AccessibilityCommand(.setColorScheme(.light)))
                sut.perform(AccessibilityCommand(.setDynamicTypeSize(.xSmall)))
                sut.perform(AccessibilityCommand(.setLayoutDirection(.rightToLeft)))
                sut.perform(AccessibilityCommand(.setLocale("de")))
                sut.perform(AccessibilityCommand(.setSetting(.increaseContrast, true)))

                #expect(overrides.colorScheme == .light)
                #expect(overrides.dynamicTypeSize == .xSmall)
                #expect(overrides.layoutDirection == .rightToLeft)
                #expect(overrides.locale?.identifier == "de")
                #expect(overrides.increaseContrast == true)
                #expect(overrides.reduceMotion == nil)
            }

            @Test("Every Dynamic Type size survives the trip from SwiftUI's value to the model's and back")
            func everyDynamicTypeSizeMaps() {
                let overrides = AccessibilityOverrides(localizations: [])
                for size in AccessibilityOverrideValues.DynamicTypeSize.allCases {
                    overrides.values.dynamicTypeSize = size

                    #expect(overrides.values.dynamicTypeSize == size, "\(size)")
                    #expect(overrides.dynamicTypeSize.map(String.init(describing:)) == size.rawValue, "\(size)")
                }
            }
        }
    }
#endif
