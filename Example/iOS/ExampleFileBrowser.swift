import CoreGraphics
import DebugDrawerFileBrowserPlugin
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's File Browser: the plugin installed with the app group the example's
/// entitlements name, and sample files to preview, written on request.
enum ExampleFileBrowser {
    /// Launched with this argument, the app writes a JSON file, a binary and an XML property
    /// list, a text file and a PNG into Documents/Samples, a JSON file five folders below it, and
    /// a JSON file into its app group's container, before it starts.
    static let launchArgument = "-SeedSampleFiles"
    /// The app group the example's entitlements name.
    static let appGroup = "group.com.debugdrawer.example"

    /// Writes the samples when launched with ``launchArgument``, then installs the plugin. It
    /// compiles in release too, where the plugin does nothing.
    @MainActor
    static func install() {
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            seed()
        }
        FileBrowser.install(appGroups: [appGroup])
    }

    /// Writes the sample files, replacing any written before.
    static func seed() {
        let samples = URL.documentsDirectory.appending(path: "Samples", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let settings: [String: Any] = ["theme": "dark", "launchCount": 12, "onboarded": true, "lastSync": Date(timeIntervalSince1970: 1_800_000_000)]
        let files: [String: Data?] = [
            "config.json": Data(#"{"api":{"baseURL":"https://api.example.com/v1","timeout":30},"features":["search","offline"],"version":3}"#.utf8),
            "settings.plist": try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0),
            "defaults.plist": try? PropertyListSerialization.data(fromPropertyList: ["region": "US", "units": "metric"], format: .xml, options: 0),
            "notes.txt": Data("Sample notes for the File Browser.\nA second line.\n".utf8),
            "swatch.png": swatch()
        ]
        for (name, data) in files {
            try? data?.write(to: samples.appending(path: name))
        }
        // Five folders down, to open one level at a time.
        let deep = samples.appending(path: "Archive/2026/11/17/Backups", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try? Data(#"{"backup":1,"items":42}"#.utf8).write(to: deep.appending(path: "backup.json"))
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            try? Data(#"{"sharedWith":"widget","items":3}"#.utf8).write(to: group.appending(path: "shared.json"))
        }
    }

    /// A 96 × 64 PNG: two colored halves.
    private static func swatch() -> Data? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 64))
        context.setFillColor(CGColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 48, y: 0, width: 48, height: 64))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
