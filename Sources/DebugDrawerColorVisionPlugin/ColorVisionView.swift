#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the simulation picker, Off first, with what the one picked shows, and
    /// where the system's own color filters are for the whole screen.
    struct ColorVisionView: View {
        @Binding var simulation: ColorVision.Simulation?

        var body: some View {
            DebugDrawerSection("Simulation") {
                DebugDrawerRow("Simulate", systemImage: "camera.filters") {
                    Text(simulation?.summary ?? "The app's own colors.")
                } accessory: {
                    Picker("Simulate", selection: $simulation) {
                        Text("Off").tag(ColorVision.Simulation?.none)
                        ForEach(ColorVision.Simulation.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Simulate")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Over the views marked debugColorVision(), in linear RGB: Machado et al. (2009) at full severity, and Rec. 709 luminance.")
                    Text(Self.systemColorFilters)
                }
            }
        }
    }

    extension ColorVisionView {
        // The system's own color filters tint the whole screen, every UIKit and AppKit view
        // included, where the shader reaches only what SwiftUI draws. The plugin names them and
        // never turns them on: they are the user's setting. The paths are those of iOS 27.2's and
        // macOS 27.0's settings, in their English strings.
        fileprivate static var systemColorFilters: String {
            #if os(macOS) || targetEnvironment(macCatalyst)
                "For the whole screen, AppKit and UIKit views too: System Settings › Accessibility › Display › Color filters."
            #elseif os(iOS)
                "For the whole screen, UIKit views too: Settings › Accessibility › Display & Text Size › Color Filters."
            #else
                "For the whole screen, UIKit views too: Color Filters, in the system's Accessibility settings."
            #endif
        }
    }
#endif
