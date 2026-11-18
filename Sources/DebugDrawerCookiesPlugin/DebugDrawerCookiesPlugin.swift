import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// The app's cookies: `HTTPCookieStorage.shared`'s, and where WebKit exists, the ones web views
/// keep in `WKWebsiteDataStore.default()`, each marked with its store. They are searched by name or
/// domain, each expanded to its attributes and deletable, or all the filter shows.
public struct CookiesPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "CookiesPlugin"
    }

    public var title = "HTTP Cookies"
    public var category = "Logs & Network"
    public var icon = "doc.plaintext"

    #if DEBUG
        let model: CookiesModel

        /// The plugin over the app's own cookie stores.
        public init() {
            self.init(model: CookiesModel(jar: _CookieJar()))
        }

        init(model: CookiesModel) {
            self.model = model
        }
    #else
        /// The plugin over the app's own cookie stores.
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            CookiesPluginView(model: model)
        #else
            EmptyView()
        #endif
    }
}

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the HTTP Cookies plugin, which lists `HTTPCookieStorage.shared`'s cookies, and
    /// `WKWebsiteDataStore.default()`'s where WebKit exists.
    func installCookies() {
        #if DEBUG
            registerGlobal(CookiesPlugin())
        #endif
    }
}
