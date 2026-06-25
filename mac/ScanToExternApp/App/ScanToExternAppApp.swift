import SwiftUI

@main
struct ScanToExternAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No window scene for menubar-only app (LSUIElement)
        Settings {
            EmptyView()
        }
    }
}
