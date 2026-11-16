#if DEBUG
    import Combine
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - Plugin

    public struct ViewInspectorPlugin: DebugDrawerPlugin {
        public var title = "View Inspector"
        public var category = "Interface"
        public var icon = "rectangle.dashed"

        public init() {}

        public var body: some View {
            ViewInspectorPluginView()
        }
    }

    struct ViewInspectorPluginView: View {
        @ObservedObject private var controller = ViewBorderController.shared
        @ObservedObject private var renderTracker = RenderTracker.shared
        @State private var hierarchy: ViewNode?
        @State private var isHierarchyExpanded = false
        @State private var searchText = ""
        @State private var debugger3DRequest: ViewDebugger3DRequest?

        var body: some View {
            DebugDrawerSection("Overlays") {
                DebugDrawerRow("View Borders", isOn: $controller.isBordersEnabled)
                DebugDrawerRow("Alignment Grid", isOn: $controller.isGridEnabled)

                if controller.isGridEnabled {
                    DebugDrawerRow("Grid Spacing") {
                        Slider(value: $controller.gridSpacing, in: 4 ... 32, step: 4)
                            .accessibilityLabel("Grid spacing")
                            .accessibilityValue("\(Int(controller.gridSpacing)) points")
                    } accessory: {
                        Text("\(Int(controller.gridSpacing)) pt")
                            .debugDrawerFont(.value)
                            .accessibilityHidden(true)
                    }

                    DebugDrawerRow("Grid Color") {
                        Picker("Grid color", selection: $controller.gridColor) {
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
                        Slider(value: $controller.gridOpacity, in: 0.05 ... 0.5)
                            .accessibilityLabel("Grid opacity")
                    } accessory: {
                        Text(controller.gridOpacity, format: .percent.precision(.fractionLength(0)))
                            .debugDrawerFont(.value)
                            .accessibilityHidden(true)
                    }
                }

                DebugDrawerRow("Click Indicators", isOn: $controller.isClickIndicatorEnabled)
            }

            DebugDrawerSection("Animation") {
                DebugDrawerRow("Animation Speed") {
                    Slider(value: $controller.animationSpeed, in: 1 ... 10, step: 0.5)
                        .accessibilityLabel("Animation speed")
                } accessory: {
                    Text(controller.animationSpeed == 1.0 ? "Normal" : "\(controller.animationSpeed, specifier: "%.1f")×")
                        .debugDrawerFont(.value)
                        .accessibilityHidden(true)
                }
            }

            DebugDrawerSection("SwiftUI Renders") {
                DebugDrawerRow("Render Tracking", isOn: $renderTracker.isEnabled)

                if renderTracker.isEnabled {
                    DebugDrawerRow("Show Overlays", isOn: $renderTracker.showOverlays)

                    if !renderTracker.renderCounts.isEmpty {
                        DebugDrawerRow("\(renderTracker.renderCounts.count) views, \(renderTracker.totalRenders) renders") {
                            Button("Reset") { renderTracker.reset() }
                                .debugDrawerButtonStyle(.borderless)
                                .accessibilityLabel("Reset render counts")
                        }

                        RenderCountList(entries: Array(renderTracker.sortedEntries.prefix(8)))
                    }
                }
            }

            DebugDrawerSection("View Hierarchy") {
                DebugDrawerActionRow {
                    Button(isHierarchyExpanded ? "Collapse" : "Snapshot") {
                        if isHierarchyExpanded {
                            isHierarchyExpanded = false
                            hierarchy = nil
                        } else {
                            snapshotHierarchy()
                        }
                    }
                    .accessibilityLabel(isHierarchyExpanded ? "Collapse the view hierarchy" : "Snapshot the view hierarchy")
                }

                if isHierarchyExpanded, let root = hierarchy {
                    DebugDrawerSearchableList("Filter...", text: $searchText, accessibilityLabel: "Filter views by class, label or role") {
                        ViewNodeRow(node: root, depth: 0, filter: searchText)
                    }
                }
            }
            .sheet(item: $debugger3DRequest) { request in
                ViewDebugger3DCombinedSheet(targetView: request.targetView)
            }
        }

        #if os(macOS)
        private func open3DDebugger() {
            guard let view = NSApp?.keyWindow?.contentView else { return }
            debugger3DRequest = ViewDebugger3DRequest(targetView: view)
        }
        #elseif os(iOS)
        private func open3DDebugger() {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                let rootView = window.rootViewController?.view
            else { return }
            debugger3DRequest = ViewDebugger3DRequest(targetView: rootView)
        }
        #endif

        private func snapshotHierarchy() {
            #if os(macOS)
            guard let contentView = NSApp?.keyWindow?.contentView else { return }
            hierarchy = ViewNode.build(from: contentView)
            isHierarchyExpanded = true
            #elseif os(iOS)
            guard let window = ViewBorderController.keyWindow,
                  let rootView = window.rootViewController?.view
            else { return }
            hierarchy = ViewNode.build(from: rootView)
            isHierarchyExpanded = true
            #endif
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installViewInspector() {
            registerGlobal(ViewInspectorPlugin())
        }
    }

#else
    import SwiftUI

    public extension View {
        func debugGrid() -> some View { self }
    }
#endif
