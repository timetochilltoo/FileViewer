import SwiftUI

@main
struct FileViewerApp: App {
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

struct FileViewerCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) { }
    }
}
