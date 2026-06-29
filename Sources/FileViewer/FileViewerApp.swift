import SwiftUI

@main
struct FileViewerApp: App {
    @NSApplicationDelegateAdaptor(FileViewerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            FileViewerCommands()
        }
    }
}

final class FileViewerAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        FileViewerWindowRegistry.shared.openExternal(urls)
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        FileViewerWindowRegistry.shared.saveCurrentSession()
    }
}
