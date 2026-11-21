// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerAnalyticsPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
