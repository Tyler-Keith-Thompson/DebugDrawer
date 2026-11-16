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
        @ObservedObject private var inspectorTool = InspectorToolController.shared
        @State private var hierarchy: ViewNode?
        @State private var isHierarchyExpanded = false
        @State private var searchText = ""
        @State private var debugger3DRequest: ViewDebugger3DRequest?

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // --- Visual overlays ---
                Toggle("View Borders", isOn: $controller.isBordersEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Toggle("Alignment Grid", isOn: $controller.isGridEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if controller.isGridEnabled {
                    HStack(spacing: 6) {
                        Text("\(Int(controller.gridSpacing))pt")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28)
                        Slider(value: $controller.gridSpacing, in: 4 ... 32, step: 4)
                            .controlSize(.small)
                            .accessibilityLabel("Grid spacing")
                            .accessibilityValue("\(Int(controller.gridSpacing)) points")

                        Picker("Grid color", selection: $controller.gridColor) {
                            ForEach(ViewBorderController.GridColor.allCases, id: \.self) { gridColor in
                                Circle()
                                    .fill(gridColor.color)
                                    .frame(width: 8, height: 8)
                                    .accessibilityLabel(gridColor.rawValue)
                                    .tag(gridColor)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.mini)
                        .accessibilityLabel("Grid color")
                        .accessibilityElement(children: .contain)
                    }

                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $controller.gridOpacity, in: 0.05 ... 0.5)
                            .controlSize(.small)
                            .accessibilityLabel("Grid opacity")
                    }
                }

                Toggle("Click Indicators", isOn: $controller.isClickIndicatorEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Divider()

                Divider()

                // --- Animation speed ---
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Animation Speed")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Text(controller.animationSpeed == 1.0 ? "Normal" : "\(controller.animationSpeed, specifier: "%.1f")x")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $controller.animationSpeed, in: 1 ... 10, step: 0.5)
                        .controlSize(.small)
                        .accessibilityLabel("Animation speed")
                }

                Divider()

                // --- SwiftUI Render Tracking ---
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Render Tracking", isOn: $renderTracker.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    if renderTracker.isEnabled {
                        Toggle("Show Overlays", isOn: $renderTracker.showOverlays)
                            .toggleStyle(.switch)
                            .controlSize(.mini)

                        if !renderTracker.renderCounts.isEmpty {
                            HStack {
                                Text("\(renderTracker.renderCounts.count) views, \(renderTracker.totalRenders) renders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset") { renderTracker.reset() }
                                    .font(.caption)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                            }

                            RenderCountList(entries: Array(renderTracker.sortedEntries.prefix(8)))
                        }
                    }
                }

                Divider()

                // --- View Hierarchy ---
                HStack {
                    Text("View Hierarchy")
                        .font(.caption.weight(.medium))
                    Spacer()

                    Button(isHierarchyExpanded ? "Collapse" : "Snapshot") {
                        if isHierarchyExpanded {
                            isHierarchyExpanded = false
                            hierarchy = nil
                        } else {
                            snapshotHierarchy()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

        private func toolButton(_ label: String, icon: String, mode: InspectorToolController.Mode) -> some View {
            Button {
                inspectorTool.clearPreviousSession()
                inspectorTool.mode = inspectorTool.mode == mode ? .off : mode
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(label)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(inspectorTool.mode == mode ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(inspectorTool.mode == mode ? .isSelected : [])
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
