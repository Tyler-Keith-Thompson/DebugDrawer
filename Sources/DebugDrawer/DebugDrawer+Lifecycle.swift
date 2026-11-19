#if DEBUG
    import Foundation

    // MARK: - Plugin lifecycle

    // Visibility is counted per plugin ID, from its views' appearances, rather than read off the
    // drawers' open state: a window's drawer, the plugin's section, its detail and its HUD readout
    // each come and go on their own, and a count lets the plugin hear one change however many of
    // them show it.
    extension DebugDrawer {
        /// Calls the lifecycle hooks of plugins that just left the drawer and of those that just
        /// joined it: each one removed gets ``DebugDrawerPlugin/didBecomeHidden(in:)`` if it was
        /// on screen and then ``DebugDrawerPlugin/uninstall(from:)``, and each one added gets
        /// ``DebugDrawerPlugin/install(in:)``. A removed plugin's ID still registered (a local
        /// plugin a newer view registered again) is still on screen, so its new registration gets
        /// ``DebugDrawerPlugin/didBecomeVisible(in:)``.
        func pluginsDidChange(removed: [AnyDebugDrawerPlugin], added: [AnyDebugDrawerPlugin]) {
            for plugin in removed {
                if visibleContentCounts[plugin.id] != nil { plugin.lifecycle.didBecomeHidden(self) }
                plugin.lifecycle.uninstall(self)
            }
            for plugin in added {
                plugin.lifecycle.install(self)
            }
            for id in Set(removed.map(\.id)).sorted() where visibleContentCounts[id] != nil {
                if let remaining = registeredPlugin(id: id) {
                    remaining.lifecycle.didBecomeVisible(self)
                } else {
                    visibleContentCounts[id] = nil
                }
            }
        }

        /// One of the plugin's views came on screen; the first one makes it visible. A view of a
        /// plugin the drawer doesn't hold (one being removed) counts for nothing.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        func pluginContentDidAppear(id: String) {
            guard let plugin = registeredPlugin(id: id) else { return }
            let count = visibleContentCounts[id, default: 0]
            visibleContentCounts[id] = count + 1
            if count == 0 { plugin.lifecycle.didBecomeVisible(self) }
        }

        /// One of the plugin's views left the screen; the last one hides it. A view the drawer
        /// didn't count (one of a plugin already removed) changes nothing.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        func pluginContentDidDisappear(id: String) {
            guard let count = visibleContentCounts[id] else { return }
            guard count == 1 else {
                visibleContentCounts[id] = count - 1
                return
            }
            visibleContentCounts[id] = nil
            registeredPlugin(id: id)?.lifecycle.didBecomeHidden(self)
        }

        /// The plugin the drawer holds under `id`: the global one, or else the first local one.
        private func registeredPlugin(id: String) -> AnyDebugDrawerPlugin? {
            globalPlugins.first { $0.id == id } ?? localRegistrations.first { $0.plugin.id == id }?.plugin
        }
    }
#endif
