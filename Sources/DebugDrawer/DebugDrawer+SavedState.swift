#if DEBUG
    import Foundation

    extension DebugDrawer {
        // Moved when the plugin registers, rather than read under both names on every lookup: each
        // store then holds one name per plugin, and the first plugin of a type name to register
        // takes what was saved under it, as it would have shown it.
        /// Moves what the drawer saved under the plugin's unqualified type name
        /// (``AnyDebugDrawerPlugin/unqualifiedTypeID``) to its ``AnyDebugDrawerPlugin/id``: whether
        /// its section is collapsed, its pin and place in the drawer's order, its HUD pin and its
        /// silenced notices. State already saved under the ID wins, and the old name's is removed,
        /// so the move happens once; a plugin that declares its own ID has nothing to move.
        func adoptSavedState(of plugin: AnyDebugDrawerPlugin) {
            guard let name = plugin.unqualifiedTypeID, name != plugin.id else { return }
            let id = plugin.id

            let oldCollapsedKey = AnyDebugDrawerPlugin.collapsedStateKey(forID: name)
            if let collapsed = defaults.object(forKey: oldCollapsedKey) {
                if defaults.object(forKey: plugin.collapsedStateKey) == nil {
                    defaults.set(collapsed, forKey: plugin.collapsedStateKey)
                }
                defaults.removeObject(forKey: oldCollapsedKey)
            }

            var layout = DrawerLayout(from: defaults)
            if layout.renamePlugin(name, to: id) {
                layout.save(to: defaults)
            }

            var hud = hudLayout
            if hud.renamePlugin(name, to: id) {
                hudLayout = hud
                hudLayout.save(to: defaults)
            }

            if noticesMutedPlugins.contains(name) {
                noticesMutedPlugins.remove(name)
                noticesMutedPlugins.insert(id)
                defaults.set(noticesMutedPlugins.sorted(), forKey: Self.noticesMutedDefaultsKey)
            }
        }
    }

    extension DrawerLayout {
        /// Puts `id` wherever the layout names `name`, unless it already names `id`, and drops
        /// `name`.
        ///
        /// - Returns: Whether the layout changed.
        mutating func renamePlugin(_ name: String, to id: String) -> Bool {
            let before = self
            pinned = pinned.renaming(name, to: id)
            order = order.renaming(name, to: id)
            if lastUsed == name {
                lastUsed = id
            }
            return self != before
        }
    }

    extension HUDLayout {
        /// Pins `id` where `name` is pinned, unless `id` is pinned already, and unpins `name`.
        ///
        /// - Returns: Whether the layout changed.
        mutating func renamePlugin(_ name: String, to id: String) -> Bool {
            let before = pinned
            pinned = pinned.renaming(name, to: id)
            return pinned != before
        }
    }

    extension [String] {
        /// The IDs with `id` in `name`'s place, or without `name` when `id` is already among them.
        fileprivate func renaming(_ name: String, to id: String) -> [String] {
            guard let index = firstIndex(of: name) else { return self }
            var renamed = self
            if contains(id) {
                renamed.remove(at: index)
            } else {
                renamed[index] = id
            }
            return renamed
        }
    }
#endif
