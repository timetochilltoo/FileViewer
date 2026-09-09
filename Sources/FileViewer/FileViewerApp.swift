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

        Settings {
            FileViewerSettingsView()
        }
    }
}

final class FileViewerAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        // FileViewer manages document tabs itself, not AppKit window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        FileViewerMenuPolicy.install()
    }

    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        FileViewerWindowRegistry.shared.openExternal(urls)
    }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        FileViewerWindowRegistry.shared.saveCurrentSession()
    }

    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Window delegates are not guaranteed to receive a close request during
        // Command-Q. Ask every document session explicitly before terminating.
        FileViewerWindowRegistry.shared.canCloseAllDocuments() ? .terminateNow : .terminateCancel
    }
}
