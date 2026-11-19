#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the overlay switches, the animation speed, the render counts and the
    /// view hierarchy snapshot.
    ///
    /// It draws ``ViewInspectorModel``'s snapshots from its transport and sends it commands; it
    /// keeps only what is its own: the hierarchy's filter text.
    struct ViewInspectorPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<ViewInspectorSnapshot, ViewInspectorCommand>
        @State private var searchText = ""

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<ViewInspectorSnapshot, ViewInspectorCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            let overlays = snapshot.overlays
            DebugDrawerSection("Overlays") {
                DebugDrawerRow("View Borders", isOn: binding(\.overlays.isBordersEnabled) { .overlays(.setBordersEnabled($0)) })
                DebugDrawerRow("Alignment Grid", isOn: binding(\.overlays.isGridEnabled) { .overlays(.setGridEnabled($0)) })

                if overlays.isGridEnabled {
                    DebugDrawerRow("Grid Spacing") {
                        Slider(value: binding(\.overlays.gridSpacing) { .overlays(.setGridSpacing($0)) }, in: 4 ... 32, step: 4)
                            .accessibilityLabel("Grid spacing")
                            .accessibilityValue("\(Int(overlays.gridSpacing)) points")
                    } accessory: {
                        Text("\(Int(overlays.gridSpacing)) pt")
                            .debugDrawerFont(.value)
                            .accessibilityHidden(true)
                    }

                    DebugDrawerRow("Grid Color") {
                        Picker("Grid color", selection: binding(\.overlays.gridColor) { .overlays(.setGridColor($0)) }) {
                            ForEach(ViewBorderController.GridColor.allCases, id: \.self) { gridColor in
                                // Each segment shows the grid's own color, the choice it makes.
                                Circle()
                                    .fill(gridColor.color)
                                    .frame(width: 8, height: 8)
                                    .accessibilityLabel(gridColor.rawValue)
                                    .tag(gridColor)
                            }
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                        .accessibilityLabel("Grid color")
                        .accessibilityElement(children: .contain)
                    }

                    DebugDrawerRow("Grid Opacity") {
                        Slider(value: binding(\.overlays.gridOpacity) { .overlays(.setGridOpacity($0)) }, in: 0.05 ... 0.5)
                            .accessibilityLabel("Grid opacity")
                    } accessory: {
                        Text(overlays.gridOpacity, format: .percent.precision(.fractionLength(0)))
                            .debugDrawerFont(.value)
                            .accessibilityHidden(true)
                    }
                }

                DebugDrawerRow(
                    "Click Indicators",
                    isOn: binding(\.overlays.isClickIndicatorEnabled) { .overlays(.setClickIndicatorEnabled($0)) }
                )
            }

            DebugDrawerSection("Animation") {
                AnimationSpeedRow(slowdown: binding(\.overlays.animationSpeed) { .overlays(.setAnimationSpeed($0)) })
            }

            // Counts only views the app tracks with .trackRenders(_:); the drawer tracks none of its own.
            DebugDrawerSection("SwiftUI Renders") {
                DebugDrawerRow("Flash Renders", isOn: binding(\.isFlashingRenders) { .renders(.setFlashing($0)) })
                RenderCountList(entries: snapshot.renderCounts) { send(.renders(.reset)) }
            }

            DebugDrawerSection("View Hierarchy") {
                let isExpanded = snapshot.hierarchy != nil
                DebugDrawerActionRow {
                    Button(isExpanded ? "Collapse" : "Snapshot") {
                        send(.hierarchy(isExpanded ? .collapse : .snapshot))
                    }
                    .accessibilityLabel(isExpanded ? "Collapse the view hierarchy" : "Snapshot the view hierarchy")
                }

                if let root = snapshot.hierarchy {
                    DebugDrawerSearchableList("Filter...", text: $searchText, accessibilityLabel: "Filter views by class, label or role") {
                        ViewNodeRow(node: root, depth: 0, filter: searchText)
                    }
                }
            }
        }

        private func send(_ action: ViewInspectorCommand.Action) {
            transport.send(ViewInspectorCommand(action))
        }

        /// A binding that reads the latest snapshot at `keyPath` and sends `command` for each
        /// change: read back at once through a direct transport, so a slider never shows its old
        /// value after a drag.
        private func binding<Value>(
            _ keyPath: KeyPath<ViewInspectorSnapshot, Value>,
            _ command: @escaping (Value) -> ViewInspectorCommand.Action
        ) -> Binding<Value> {
            Binding(get: { transport.snapshot[keyPath: keyPath] }, set: { send(command($0)) })
        }
    }
#endif
