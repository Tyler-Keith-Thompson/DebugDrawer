// ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawerKeychainPlugin
    import ViewInspector

    extension Inspection: InspectionEmissary {}
#endif
