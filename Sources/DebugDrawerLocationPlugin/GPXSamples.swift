#if DEBUG
    // The bundled routes, as GPX text in the source rather than files in a resource bundle: SwiftPM
    // copies a target's resources into every app that links it, release builds included, where
    // this text sits under `#if DEBUG` and ships nowhere. Both are drives, a point every 10 and 18
    // seconds, with times, so they also show a timed track's course and speed.
    enum GPXSamples {
        /// A loop of the ring road around Apple Park, 25 points over 4 minutes.
        static let appleParkLoop = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="DebugDrawer" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Apple Park Loop</name><trkseg>
            <trkpt lat="37.338900" lon="-122.009000"><ele>45.0</ele><time>2026-01-01T09:00:00Z</time></trkpt>
            <trkpt lat="37.338764" lon="-122.007698"><ele>45.8</ele><time>2026-01-01T09:00:10Z</time></trkpt>
            <trkpt lat="37.338364" lon="-122.006485"><ele>46.5</ele><time>2026-01-01T09:00:20Z</time></trkpt>
            <trkpt lat="37.337728" lon="-122.005443"><ele>47.1</ele><time>2026-01-01T09:00:30Z</time></trkpt>
            <trkpt lat="37.336900" lon="-122.004643"><ele>47.6</ele><time>2026-01-01T09:00:40Z</time></trkpt>
            <trkpt lat="37.335935" lon="-122.004141"><ele>47.9</ele><time>2026-01-01T09:00:50Z</time></trkpt>
            <trkpt lat="37.334900" lon="-122.003969"><ele>48.0</ele><time>2026-01-01T09:01:00Z</time></trkpt>
            <trkpt lat="37.333865" lon="-122.004141"><ele>47.9</ele><time>2026-01-01T09:01:10Z</time></trkpt>
            <trkpt lat="37.332900" lon="-122.004643"><ele>47.6</ele><time>2026-01-01T09:01:20Z</time></trkpt>
            <trkpt lat="37.332072" lon="-122.005443"><ele>47.1</ele><time>2026-01-01T09:01:30Z</time></trkpt>
            <trkpt lat="37.331436" lon="-122.006485"><ele>46.5</ele><time>2026-01-01T09:01:40Z</time></trkpt>
            <trkpt lat="37.331036" lon="-122.007698"><ele>45.8</ele><time>2026-01-01T09:01:50Z</time></trkpt>
            <trkpt lat="37.330900" lon="-122.009000"><ele>45.0</ele><time>2026-01-01T09:02:00Z</time></trkpt>
            <trkpt lat="37.331036" lon="-122.010302"><ele>44.2</ele><time>2026-01-01T09:02:10Z</time></trkpt>
            <trkpt lat="37.331436" lon="-122.011515"><ele>43.5</ele><time>2026-01-01T09:02:20Z</time></trkpt>
            <trkpt lat="37.332072" lon="-122.012557"><ele>42.9</ele><time>2026-01-01T09:02:30Z</time></trkpt>
            <trkpt lat="37.332900" lon="-122.013357"><ele>42.4</ele><time>2026-01-01T09:02:40Z</time></trkpt>
            <trkpt lat="37.333865" lon="-122.013859"><ele>42.1</ele><time>2026-01-01T09:02:50Z</time></trkpt>
            <trkpt lat="37.334900" lon="-122.014031"><ele>42.0</ele><time>2026-01-01T09:03:00Z</time></trkpt>
            <trkpt lat="37.335935" lon="-122.013859"><ele>42.1</ele><time>2026-01-01T09:03:10Z</time></trkpt>
            <trkpt lat="37.336900" lon="-122.013357"><ele>42.4</ele><time>2026-01-01T09:03:20Z</time></trkpt>
            <trkpt lat="37.337728" lon="-122.012557"><ele>42.9</ele><time>2026-01-01T09:03:30Z</time></trkpt>
            <trkpt lat="37.338364" lon="-122.011515"><ele>43.5</ele><time>2026-01-01T09:03:40Z</time></trkpt>
            <trkpt lat="37.338764" lon="-122.010302"><ele>44.2</ele><time>2026-01-01T09:03:50Z</time></trkpt>
            <trkpt lat="37.338900" lon="-122.009000"><ele>45.0</ele><time>2026-01-01T09:04:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """

        /// Across the Golden Gate Bridge, south to north, 12 points over 3 minutes 18 seconds.
        static let goldenGateBridge = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="DebugDrawer" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Golden Gate Bridge</name><trkseg>
            <trkpt lat="37.807800" lon="-122.475000"><ele>67.0</ele><time>2026-01-01T09:00:00Z</time></trkpt>
            <trkpt lat="37.810036" lon="-122.475409"><ele>67.0</ele><time>2026-01-01T09:00:18Z</time></trkpt>
            <trkpt lat="37.812273" lon="-122.475818"><ele>67.0</ele><time>2026-01-01T09:00:36Z</time></trkpt>
            <trkpt lat="37.814509" lon="-122.476227"><ele>67.0</ele><time>2026-01-01T09:00:54Z</time></trkpt>
            <trkpt lat="37.816745" lon="-122.476636"><ele>67.0</ele><time>2026-01-01T09:01:12Z</time></trkpt>
            <trkpt lat="37.818982" lon="-122.477045"><ele>67.0</ele><time>2026-01-01T09:01:30Z</time></trkpt>
            <trkpt lat="37.821218" lon="-122.477455"><ele>67.0</ele><time>2026-01-01T09:01:48Z</time></trkpt>
            <trkpt lat="37.823455" lon="-122.477864"><ele>67.0</ele><time>2026-01-01T09:02:06Z</time></trkpt>
            <trkpt lat="37.825691" lon="-122.478273"><ele>67.0</ele><time>2026-01-01T09:02:24Z</time></trkpt>
            <trkpt lat="37.827927" lon="-122.478682"><ele>67.0</ele><time>2026-01-01T09:02:42Z</time></trkpt>
            <trkpt lat="37.830164" lon="-122.479091"><ele>67.0</ele><time>2026-01-01T09:03:00Z</time></trkpt>
            <trkpt lat="37.832400" lon="-122.479500"><ele>67.0</ele><time>2026-01-01T09:03:18Z</time></trkpt>
          </trkseg></trk>
        </gpx>
        """
    }
#endif
