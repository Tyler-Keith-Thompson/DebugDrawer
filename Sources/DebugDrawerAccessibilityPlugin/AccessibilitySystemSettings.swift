#if DEBUG
    import Combine
    import Foundation
    #if canImport(UIKit)
        import UIKit
    #elseif canImport(AppKit)
        import AppKit
    #endif

    /// The system's accessibility settings, as the device has them set.
    @MainActor
    protocol AccessibilitySystemSettings {
        /// The settings now.
        var values: AccessibilitySystemValues { get }
        /// Fires when one of the settings changes.
        var changes: AnyPublisher<Void, Never> { get }
    }

    /// The settings UIKit (iOS, Mac Catalyst) or AppKit (macOS) reports, the ones SwiftUI's
    /// environment reads outside `.debugAccessibilityOverrides()`.
    struct _AccessibilitySystemSettings: AccessibilitySystemSettings {
        #if canImport(UIKit)
            var values: AccessibilitySystemValues {
                AccessibilitySystemValues(
                    reduceMotion: UIAccessibility.isReduceMotionEnabled,
                    increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
                    boldText: UIAccessibility.isBoldTextEnabled,
                    reduceTransparency: UIAccessibility.isReduceTransparencyEnabled,
                    differentiateWithoutColor: UIAccessibility.shouldDifferentiateWithoutColor,
                    invertColors: UIAccessibility.isInvertColorsEnabled
                )
            }

            var changes: AnyPublisher<Void, Never> {
                let names: [Notification.Name] = [
                    UIAccessibility.reduceMotionStatusDidChangeNotification,
                    UIAccessibility.darkerSystemColorsStatusDidChangeNotification,
                    UIAccessibility.boldTextStatusDidChangeNotification,
                    UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                    UIAccessibility.differentiateWithoutColorDidChangeNotification,
                    UIAccessibility.invertColorsStatusDidChangeNotification
                ]
                return Publishers.MergeMany(names.map { NotificationCenter.default.publisher(for: $0) })
                    .map { _ in }
                    .eraseToAnyPublisher()
            }
        #elseif canImport(AppKit)
            // macOS has no Bold Text setting: SwiftUI's legibilityWeight stays regular there.
            var values: AccessibilitySystemValues {
                let workspace = NSWorkspace.shared
                return AccessibilitySystemValues(
                    reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                    increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
                    boldText: false,
                    reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                    differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
                    invertColors: workspace.accessibilityDisplayShouldInvertColors
                )
            }

            var changes: AnyPublisher<Void, Never> {
                NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
                    .map { _ in }
                    .eraseToAnyPublisher()
            }
        #else
            var values: AccessibilitySystemValues {
                AccessibilitySystemValues()
            }

            var changes: AnyPublisher<Void, Never> {
                Empty().eraseToAnyPublisher()
            }
        #endif
    }
#endif
