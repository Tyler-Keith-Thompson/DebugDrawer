import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// A design mockup over the app: picking it, its opacity, offset, scale and blend, Show and
/// Move. The header and the HUD say whether it shows and at what opacity, or that Move is on.
public struct DesignOverlayPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer and the HUD.
    nonisolated static let pluginID = "DesignOverlayPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Design Overlay"
    public var category = "Interface"
    public var icon = "square.on.square.dashed"

    #if DEBUG
        let model: DesignOverlayModel

        init(model: DesignOverlayModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            DesignOverlayPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, ends Move, so the window gets its
    /// touches back, and takes the mockup off the app. The mockup and settings saved in Caches
    /// stay for the next install.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// Show or Hide with the opacity, and Done while Move is on, so the mockup can be checked
    /// against the app with the drawer closed.
    public var hud: DesignOverlayHUD? {
        #if DEBUG
            DesignOverlayHUD(model: model)
        #else
            nil
        #endif
    }

    /// The opacity and blend while the mockup shows, "Hidden" or "Moving"; nothing before a
    /// mockup is picked.
    public var headerAccessory: some View {
        #if DEBUG
            DesignOverlayHeaderAccessory(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Show or hide the mockup, and switch the difference blend, found by "mockup", "design"
    /// and "comp" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Show or hide the design overlay", keywords: ["design", "overlay", "mockup", "comp"]) { [model] in
                    model.toggleVisibility()
                },
                DebugDrawerAction("Difference blend for the design overlay", keywords: ["design", "mockup", "difference", "blend"]) { [model] in
                    model.settings.blend = model.settings.blend == .difference ? .normal : .difference
                }
            ]
        #else
            []
        #endif
    }
}

/// The HUD readout: reads the model and hands its state to `DesignOverlayHUDButtons`.
public struct DesignOverlayHUD: View {
    #if DEBUG
        @ObservedObject var model: DesignOverlayModel
    #endif

    public var body: some View {
        #if DEBUG
            DesignOverlayHUDButtons(
                state: DesignOverlayStatus(hasMockup: model.mockup != nil, settings: model.settings, isMoving: model.isMoving),
                toggleVisibility: { model.toggleVisibility() },
                endMoving: { model.isMoving = false }
            )
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its values to `DesignOverlayView`.
    struct DesignOverlayPluginView: View {
        @ObservedObject var model: DesignOverlayModel

        var body: some View {
            DesignOverlayView(
                mockup: model.mockup,
                failure: model.failure,
                windowWidth: model.windowWidth,
                settings: $model.settings,
                isMoving: $model.isMoving,
                sources: MockupSources(model: model),
                clear: { model.clear() }
            )
        }
    }

    extension MockupSources {
        /// Each source opening its image in `model`.
        @MainActor
        init(model: DesignOverlayModel) {
            self.init(
                open: { model.open($0) },
                openFile: { model.open(fileAt: $0) },
                paste: { model.paste() },
                fail: { model.fail($0) }
            )
        }
    }

    /// Show or Hide with the opacity; while Move is on, Done.
    struct DesignOverlayHUDButtons: View {
        let state: DesignOverlayStatus
        let toggleVisibility: () -> Void
        let endMoving: () -> Void

        var body: some View {
            switch state {
            case .noMockup:
                Label("No mockup", systemImage: "square.on.square.dashed")
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
            case .moving:
                Button(action: endMoving) {
                    Label("Moving · Done", systemImage: "hand.draw")
                        .debugDrawerFont(.value)
                        .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityLabel("Done moving the mockup")
            case let .showing(opacity, _):
                Button(action: toggleVisibility) {
                    Label("Mockup \(opacity)", systemImage: "eye")
                        .debugDrawerFont(.value)
                        .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityLabel("Hide the mockup")
            case .hidden:
                Button(action: toggleVisibility) {
                    Label("Mockup hidden", systemImage: "eye.slash")
                        .debugDrawerFont(.value)
                        .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityLabel("Show the mockup")
            }
        }
    }

    /// The header's readout: reads the model.
    struct DesignOverlayHeaderAccessory: View {
        @ObservedObject var model: DesignOverlayModel

        var body: some View {
            DesignOverlayHeaderReadout(
                state: DesignOverlayStatus(hasMockup: model.mockup != nil, settings: model.settings, isMoving: model.isMoving)
            )
        }
    }

    /// "50%", "50% · Difference", "Hidden" or "Moving"; nothing before a mockup is picked.
    struct DesignOverlayHeaderReadout: View {
        let state: DesignOverlayStatus

        var body: some View {
            if let text = state.summary {
                Text(text)
            }
        }
    }
#endif
