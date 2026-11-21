#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The picker of an app's plugins in the picker layout: segments while every plugin's name
    /// fits at its full width, else a pop-up menu naming the plugin picked, whose items name every
    /// plugin in full. A segmented picker shares its width evenly, so twenty plugins in an iPad's
    /// detail column read "Fl…", "Ex…".
    struct SidecarPluginPicker: View {
        let plugins: [DebugDrawerSidecarPlugin]
        @Binding var selection: DebugDrawerSidecarPlugin.ID?

        var body: some View {
            #if os(watchOS)
                // Never shown: the watch's screen is always the rows layout, and watchOS has
                // neither segments nor menus.
                picker
            #else
                // The first whose ideal width fits: the segments' is every name at full width.
                ViewThatFits(in: .horizontal) {
                    picker
                        .pickerStyle(.segmented)
                    picker
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            #endif
        }

        private var picker: some View {
            Picker("Plugin", selection: $selection) {
                ForEach(plugins) { plugin in
                    Label(plugin.title, systemImage: plugin.icon).tag(Optional(plugin.id))
                }
            }
            .labelsHidden()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Plugin")
        }
    }
#endif
