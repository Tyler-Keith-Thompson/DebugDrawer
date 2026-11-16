import SwiftUI

/// How ``DebugDrawerKeyValueRow`` sets its value: in the system font, as words read, or
/// monospaced, as code reads.
///
/// The drawer sets numbers, versions, times, paths, keys and code in monospaced type and words in
/// the system font. ``automatic`` tells them apart by the value's characters; a group of rows
/// whose words are code (HTTP headers, query parameters, a keychain label) says so with
/// `debugDrawerValueStyle(.code)`.
///
/// ```swift
/// DebugDrawerKeyValueRow("Alert Style", value: "Banners")        // the system font
/// DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")         // monospaced
/// ForEach(headers) { DebugDrawerKeyValueRow($0.name, value: $0.value) }
///     .debugDrawerValueStyle(.code)                              // "gzip" monospaced too
/// ```
public enum DebugDrawerValueStyle: Sendable {
    /// Monospaced when the value holds a digit or a character words don't ("/", ".", "_", ":",
    /// "@", "=" and the like), the system font otherwise: "Not Supported", "AC Power" and
    /// "Banners" read as words; "63.5 MB", "1.4.2", "com.example.orders" and "arm64" as code.
    case automatic
    /// The system font, whatever the value holds.
    case text
    /// Monospaced, whatever the value holds.
    case code
}

public extension View {
    /// Sets how the ``DebugDrawerKeyValueRow``s in this view set their values.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerValueStyle(_ style: DebugDrawerValueStyle) -> some View {
        #if DEBUG
            environment(\.debugDrawerValueStyle, style)
        #else
            self
        #endif
    }
}

#if DEBUG
    extension EnvironmentValues {
        @Entry var debugDrawerValueStyle = DebugDrawerValueStyle.automatic
    }

    extension DebugDrawerValueStyle {
        /// Whether `value` is set monospaced in this style.
        func isCode(_ value: String) -> Bool {
            switch self {
            case .text: false
            case .code: true
            case .automatic: value.contains { $0.isNumber || Self.codeCharacters.contains($0) }
            }
        }

        // Characters that appear in paths, identifiers, versions, addresses and expressions but
        // not in words. The hyphen, apostrophe, ellipsis and dashes are left out: "Wi-Fi",
        // "Measuring…" and "—" read as words.
        private static let codeCharacters = Set("/\\._:@#$%&=+*<>[]{}|~^`\"")
    }
#endif
