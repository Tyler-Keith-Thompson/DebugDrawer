#if DEBUG
    import DebugDrawer

    // Requests go to the store of the drawer that installed the Network plugin last
    // (`NetworkInterception`), so that drawer's rules mask what its store writes to the session: a
    // plugin installed in a `DebugDrawer(defaults:)` of its own is written by that drawer's rules.
    // A store held by two drawers writes by the later one's, and by the earlier one's again once
    // the later removes the plugin. Rejected: the first install's rules (a drawer installed later
    // gets the requests but not its own masking), and the drawer showing the plugin (a request is
    // written as it completes, whether or not a drawer shows the plugin then).

    extension NetworkStore {
        /// Writes `entry`, complete, to the current session, masked by ``recordingRedaction`` as it
        /// is now, with the request it resends when the log still holds it.
        func persist(_ entry: NetworkEntry) {
            guard let recorder else { return }
            let original = entry.replayOf.flatMap { id in entries.first { $0.id == id } }
            recorder.record(entry, original: original, redaction: recordingRedaction)
        }

        /// The rules what is written to the session is masked by: those of ``recordingDrawer``, the
        /// drawer holding the plugin over this store that installed it last, which
        /// `NetworkInterception` sets as drawers install and remove the plugin.
        var recordingRedaction: DebugDrawerRedaction {
            // The shared drawer's while no drawer holds this store: then requests reach a store
            // only through the shared route, which is the app's drawer's, `installNetwork()`'s.
            (recordingDrawer ?? .shared).redaction
        }
    }
#endif
