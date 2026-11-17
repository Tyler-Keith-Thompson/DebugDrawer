#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Protanopia, deuteranopia, tritanopia and grayscale simulated over the app. The header and
    /// the HUD name the simulation on; the HUD cycles through them.
    public struct ColorVisionPlugin: DebugDrawerPlugin {
        public var id: String {
            "ColorVisionPlugin"
        }

        public var title = "Color Vision"
        public var category = "Interface"
        public var icon = "eye"

        let model: ColorVisionModel

        init(model: ColorVisionModel) {
            self.model = model
        }

        public var body: some View {
            ColorVisionPluginView(model: model)
        }

        /// The simulation on, which a tap moves to the next, so they can be compared with the
        /// drawer closed.
        public var hud: ColorVisionHUD? {
            ColorVisionHUD(model: model)
        }

        /// The simulation on ("Protanopia"); nothing while the app shows its own colors.
        public var headerAccessory: some View {
            ColorVisionHeaderAccessory(model: model)
        }

        /// Each simulation on or off, found by "color blind" and its kind too, and all of them off.
        public var actions: [DebugDrawerAction] {
            ColorVision.Simulation.allCases.map { simulation in
                DebugDrawerAction(
                    "Simulate \(simulation.rawValue)",
                    keywords: ["color", "vision", "blind", "simulate", simulation.rawValue]
                ) { [model] in
                    model.toggle(simulation)
                }
            } + [
                DebugDrawerAction("Turn off color vision simulation", keywords: ["color", "vision", "blind", "off", "normal"]) { [model] in
                    model.simulation = nil
                }
            ]
        }
    }

    /// Reads the model and hands its simulation to `ColorVisionView`.
    struct ColorVisionPluginView: View {
        @ObservedObject var model: ColorVisionModel

        var body: some View {
            ColorVisionView(simulation: $model.simulation)
        }
    }

    /// The HUD readout: reads the model and hands its simulation to `ColorVisionHUDButton`.
    public struct ColorVisionHUD: View {
        @ObservedObject var model: ColorVisionModel

        public var body: some View {
            ColorVisionHUDButton(simulation: model.simulation, cycle: { model.cycle() })
        }
    }

    /// The simulation on, or "Simulation Off"; a tap moves to the next.
    struct ColorVisionHUDButton: View {
        let simulation: ColorVision.Simulation?
        let cycle: () -> Void

        var body: some View {
            Button(action: cycle) {
                Label(simulation?.title ?? "Simulation Off", systemImage: simulation == nil ? "eye" : "eye.trianglebadge.exclamationmark")
                    .debugDrawerFont(.value)
                    .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityLabel("Color vision simulation: \(simulation?.title ?? "Off")")
            .accessibilityHint("Switches to \(ColorVision.Simulation.after(simulation)?.title ?? "Off")")
        }
    }

    /// The header's readout: reads the model.
    struct ColorVisionHeaderAccessory: View {
        @ObservedObject var model: ColorVisionModel

        var body: some View {
            ColorVisionHeaderReadout(simulation: model.simulation)
        }
    }

    /// The simulation on ("Protanopia"); nothing while the app shows its own colors.
    struct ColorVisionHeaderReadout: View {
        let simulation: ColorVision.Simulation?

        var body: some View {
            if let simulation {
                Text(simulation.title)
            }
        }
    }
#endif
