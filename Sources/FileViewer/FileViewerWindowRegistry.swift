import AppKit
import SwiftUI

@MainActor
final class FileViewerWindowRegistry {
    static let shared = FileViewerWindowRegistry()

    private var registeredModels: [WeakAppModel] = []
    private var retainedWindows: [NSWindow] = []
    private var windowDelegates: [ObjectIdentifier: WindowCloseDelegate] = [:]
    private var pendingExternalURLs: [URL] = []
    private var pendingFlushScheduled = false

    private init() {}

    func register(_ model: AppModel) {
        cleanup()
        if !registeredModels.contains(where: { $0.value === model }) {
            registeredModels.append(WeakAppModel(value: model))
        }
        flushPendingExternalURLsIfPossible()
    }

    func register(_ model: AppModel, window: NSWindow) {
        register(model)
        let key = ObjectIdentifier(window)
        if let existingDelegate = windowDelegates[key] {
            existingDelegate.model = model
        } else {
            let delegate = WindowCloseDelegate(model: model) { [weak self, weak window] in
                guard let self, let window else { return }
                self.windowDelegates.removeValue(forKey: ObjectIdentifier(window))
                self.retainedWindows.removeAll { $0 === window }
            }
            window.delegate = delegate
            windowDelegates[key] = delegate
        }
    }

    func openExternal(_ urls: [URL]) {
        cleanup()
        if registeredModels.compactMap(\.value).isEmpty {
            pendingExternalURLs.append(contentsOf: urls)
            schedulePendingFlush()
            return
        }

        for url in urls {
            openExternal(url)
        }
    }

    private func flushPendingExternalURLsIfPossible() {
        guard !pendingExternalURLs.isEmpty else { return }
        guard !registeredModels.compactMap(\.value).isEmpty else { return }
        let urls = pendingExternalURLs
        pendingExternalURLs = []
        openExternal(urls)
    }

    private func schedulePendingFlush() {
        guard !pendingFlushScheduled else { return }
        pendingFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingFlushScheduled = false
            if self.registeredModels.compactMap(\.value).isEmpty {
                let urls = self.pendingExternalURLs
                self.pendingExternalURLs = []
                for url in urls {
                    self.openNewWindow(initialURLs: [url])
                }
            } else {
                self.flushPendingExternalURLsIfPossible()
            }
        }
    }

    private func openExternal(_ url: URL) {
        if let reusableModel = registeredModels
            .compactMap(\.value)
            .first(where: { $0.canAcceptExternalOpenInCurrentWindow }) {
            reusableModel.open(url: url)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openNewWindow(initialURLs: [url])
    }

    private func openNewWindow(initialURLs: [URL]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 520, height: 620)
        window.title = initialURLs.first?.lastPathComponent ?? "FileViewer"
        window.contentView = NSHostingView(rootView: ContentView(initialURLs: initialURLs))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        retainedWindows.append(window)
    }

    private func cleanup() {
        registeredModels.removeAll { $0.value == nil }
        let closedWindows = retainedWindows.filter { !$0.isVisible }
        retainedWindows.removeAll { !$0.isVisible }
        for window in closedWindows {
            windowDelegates.removeValue(forKey: ObjectIdentifier(window))
        }
    }
}

private struct WeakAppModel {
    weak var value: AppModel?
}

@MainActor
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var model: AppModel?
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model?.canCloseAllDocuments() ?? true
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
