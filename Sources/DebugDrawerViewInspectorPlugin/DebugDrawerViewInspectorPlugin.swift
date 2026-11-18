import Combine
import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// View borders by depth, the alignment grid, click indicators, slowed animations, the key
/// window's view hierarchy and the render counts of the views tracked with `.trackRenders(_:)`.
public struct ViewInspectorPlugin: DebugDrawerPlugin {
    public var title = "View Inspector"
    public var category = "Interface"
    public var icon = "rectangle.dashed"

    public init() {}

    public var body: some View {
        #if DEBUG
            ViewInspectorPluginView()
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the View Inspector plugin. Its switches act on the app's key window; the grid
    /// shows only under `.debugGrid()`.
    func installViewInspector() {
        #if DEBUG
            registerGlobal(ViewInspectorPlugin())
        #endif
    }
}

#if DEBUG
    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    struct ViewInspectorPluginView: View {
        @ObservedObject private var controller = ViewBorderController.shared
        @ObservedObject private var renderTracker = RenderTracker.shared
        @ObservedObject private var flashSetting = RenderFlashSetting.shared
        @State private var hierarchy: ViewNode?
        @State private var isHierarchyExpanded = false
        @State private var searchText = ""

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

            // Counts only views the app tracks with .trackRenders(_:); the drawer tracks none of its own.
            DebugDrawerSection("SwiftUI Renders") {
                DebugDrawerRow("Flash Renders", isOn: $flashSetting.isOn)
                RenderCountList(entries: renderTracker.entries) { renderTracker.reset() }
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
        }

        private func snapshotHierarchy() {
            #if os(macOS)
            guard let contentView = debugDrawerAppKeyWindow?.contentView else { return }
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

#else
    import SwiftUI

    public extension View {
        /// Returns the view unchanged: release builds draw no grid.
        ///
        /// - Returns: This view.
        func debugGrid() -> some View { self }
    }
#endif
