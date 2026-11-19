#if DEBUG
    import Combine
    import SwiftUI

    // The one place SwiftUI's values meet the model's: the shared overrides keep SwiftUI's types,
    // which `.debugAccessibilityOverrides()` applies, and read and write as the model's Codable
    // values here.

    extension AccessibilityOverrides: AccessibilityOverrideStore {
        var values: AccessibilityOverrideValues {
            get {
                AccessibilityOverrideValues(
                    colorScheme: colorScheme.flatMap(AccessibilityOverrideValues.ColorScheme.init),
                    dynamicTypeSize: dynamicTypeSize.flatMap(AccessibilityOverrideValues.DynamicTypeSize.init),
                    layoutDirection: layoutDirection.flatMap(AccessibilityOverrideValues.LayoutDirection.init),
                    locale: locale?.identifier,
                    reduceMotion: reduceMotion,
                    increaseContrast: increaseContrast,
                    boldText: boldText,
                    reduceTransparency: reduceTransparency,
                    differentiateWithoutColor: differentiateWithoutColor,
                    invertColors: invertColors
                )
            }
            set {
                // Only what differs is assigned: each assignment republishes, which re-renders the
                // app's views under the overrides.
                let current = values
                if newValue.colorScheme != current.colorScheme { colorScheme = newValue.colorScheme.map(SwiftUI.ColorScheme.init) }
                if newValue.dynamicTypeSize != current.dynamicTypeSize {
                    dynamicTypeSize = newValue.dynamicTypeSize.map(SwiftUI.DynamicTypeSize.init)
                }
                if newValue.layoutDirection != current.layoutDirection {
                    layoutDirection = newValue.layoutDirection.map(SwiftUI.LayoutDirection.init)
                }
                if newValue.locale != current.locale { locale = newValue.locale.map(Locale.init(identifier:)) }
                for setting in AccessibilitySetting.allCases where newValue[setting] != current[setting] {
                    self[setting] = newValue[setting]
                }
            }
        }

        var localeIdentifiers: [String] {
            availableLocales.map(\.identifier)
        }

        var changes: AnyPublisher<Void, Never> {
            objectWillChange.map { _ in }.eraseToAnyPublisher()
        }

        private subscript(setting: AccessibilitySetting) -> Bool? {
            get {
                switch setting {
                case .reduceMotion: reduceMotion
                case .increaseContrast: increaseContrast
                case .boldText: boldText
                case .reduceTransparency: reduceTransparency
                case .differentiateWithoutColor: differentiateWithoutColor
                case .invertColors: invertColors
                }
            }
            set {
                switch setting {
                case .reduceMotion: reduceMotion = newValue
                case .increaseContrast: increaseContrast = newValue
                case .boldText: boldText = newValue
                case .reduceTransparency: reduceTransparency = newValue
                case .differentiateWithoutColor: differentiateWithoutColor = newValue
                case .invertColors: invertColors = newValue
                }
            }
        }
    }

    extension AccessibilityOverrideValues.ColorScheme {
        /// SwiftUI's `scheme`, or `nil` for one this doesn't mirror.
        init?(_ scheme: SwiftUI.ColorScheme) {
            switch scheme {
            case .light: self = .light
            case .dark: self = .dark
            @unknown default: return nil
            }
        }
    }

    extension SwiftUI.ColorScheme {
        init(_ scheme: AccessibilityOverrideValues.ColorScheme) {
            switch scheme {
            case .light: self = .light
            case .dark: self = .dark
            }
        }
    }

    // Both list their sizes smallest first, the same twelve, so a size maps by its place in the list.

    extension AccessibilityOverrideValues.DynamicTypeSize {
        /// SwiftUI's `size`, or `nil` for one this doesn't mirror.
        init?(_ size: SwiftUI.DynamicTypeSize) {
            guard let index = SwiftUI.DynamicTypeSize.allCases.firstIndex(of: size),
                  Self.allCases.indices.contains(index)
            else { return nil }
            self = Self.allCases[index]
        }
    }

    extension SwiftUI.DynamicTypeSize {
        init(_ size: AccessibilityOverrideValues.DynamicTypeSize) {
            // The force unwrap can't fire: every mirrored size has a place in SwiftUI's list, which
            // the tests check size by size.
            let index = AccessibilityOverrideValues.DynamicTypeSize.allCases.firstIndex(of: size)!
            self = Self.allCases[index]
        }
    }

    extension AccessibilityOverrideValues.LayoutDirection {
        /// SwiftUI's `direction`, or `nil` for one this doesn't mirror.
        init?(_ direction: SwiftUI.LayoutDirection) {
            switch direction {
            case .leftToRight: self = .leftToRight
            case .rightToLeft: self = .rightToLeft
            @unknown default: return nil
            }
        }
    }

    extension SwiftUI.LayoutDirection {
        init(_ direction: AccessibilityOverrideValues.LayoutDirection) {
            switch direction {
            case .leftToRight: self = .leftToRight
            case .rightToLeft: self = .rightToLeft
            }
        }
    }
#endif
