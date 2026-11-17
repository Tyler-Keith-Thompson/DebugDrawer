import DebugDrawer
import DebugDrawerDesignOverlayPlugin
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's design overlay: the plugin installed, and on request a sample comp drawn at launch
/// and the plugin pinned to the HUD.
enum ExampleDesignOverlay {
    /// Launched with this argument, the app hands the plugin a generated sample comp and pins the
    /// plugin to the HUD, so the overlay can be checked without picking an image.
    static let launchArgument = "-DesignOverlaySample"

    /// Installs the plugin, which compiles in release too and does nothing there.
    @MainActor
    static func install() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else {
            DesignOverlay.install()
            return
        }
        DesignOverlay.install(mockup: sampleComp())
        #if DEBUG
            // The plugin's ID is its type's name, as for every plugin that declares none.
            let pluginID = "DesignOverlayPlugin"
            if !DebugDrawer.shared.hudLayout.pinned.contains(pluginID) {
                DebugDrawer.shared.toggleHUD(forPlugin: pluginID)
            }
        #endif
    }

    /// A comp of the example's screen, as a designer might hand it over: the title, the Controls
    /// buttons and a few rows, at @2x for a window 1032 points wide, as PNG data.
    @MainActor
    static func sampleComp() -> Data? {
        let renderer = ImageRenderer(content: ExampleComp())
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// The sample comp's layout, 1032 by 1376 points.
private struct ExampleComp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DebugDrawer Example")
                .font(.largeTitle.bold())
                .padding(.top, 96)
            Text("CONTROLS")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(["Increment", "Print", "Reset"], id: \.self) { title in
                    Text(title)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            ForEach(1 ... 8, id: \.self) { row in
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.9))
                    .frame(height: 44)
                    .overlay(alignment: .leading) { Text("Row \(row)").padding(.leading, 16) }
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(width: 1032, height: 1376, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
