import SwiftUI

@main
struct FileViewerApp: App {
    @NSApplicationDelegateAdaptor(FileViewerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            FileViewerCommands()
        }
    }
}

final class FileViewerAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(name: .openFileURLs, object: urls)
    }
}
