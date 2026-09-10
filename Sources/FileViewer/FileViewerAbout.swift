import AppKit
import SwiftUI

@MainActor
final class FileViewerAboutPresenter {
    static let shared = FileViewerAboutPresenter()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 290),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About FileViewer"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FileViewerAboutView())
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FileViewerAboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 104)
            } else {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 76))
                    .foregroundStyle(.secondary)
                    .frame(width: 104, height: 104)
            }

            Text("FileViewer")
                .font(.title.weight(.bold))
            Text("Version \(version)")
                .font(.body)
            Text("By Patrick Shi")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var appIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.11"
    }
}
