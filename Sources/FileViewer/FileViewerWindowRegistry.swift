import AppKit
import SwiftUI

@MainActor
final class FileViewerWindowRegistry {
    static let shared = FileViewerWindowRegistry()

    private var registeredModels: [WeakAppModel] = []
    private var registeredWindows: [ObjectIdentifier: WeakWindow] = [:]
    private var retainedWindows: [NSWindow] = []
    private var windowDelegates: [ObjectIdentifier: WindowCloseDelegate] = [:]
    private var pendingExternalURLs: [URL] = []
    private var pendingFlushScheduled = false
    private var restoredAdditionalSessionWindows = false
    private var sessionRestoreScheduled = false
    private var suppressSessionRestore = false

    private init() {}

    func register(_ model: AppModel) {
        cleanupModels()
        if !registeredModels.contains(where: { $0.value === model }) {
            registeredModels.append(WeakAppModel(value: model))
        }
        scheduleSessionRestoreIfPossible(using: model)
        flushPendingExternalURLsIfPossible()
    }

    func register(_ model: AppModel, window: NSWindow) {
        register(model)
        registeredWindows[ObjectIdentifier(model)] = WeakWindow(value: window)
        let key = ObjectIdentifier(window)
        if let existingDelegate = windowDelegates[key] {
            existingDelegate.model = model
        } else {
            let delegate = WindowCloseDelegate(model: model) { [weak self, weak window, weak model] in
                guard let self, let window else { return }
                if let model {
                    self.registeredModels.removeAll { $0.value === model }
                    self.registeredWindows.removeValue(forKey: ObjectIdentifier(model))
                }
                self.saveCurrentSession()
                self.releaseClosedWindowLater(window)
            }
            window.delegate = delegate
            windowDelegates[key] = delegate
        }
    }

    func openExternal(_ urls: [URL]) {
        suppressSessionRestore = true
        cleanupModels()
        if registeredModels.compactMap(\.value).isEmpty {
            pendingExternalURLs.append(contentsOf: urls)
            schedulePendingFlush()
            return
        }

        for url in urls {
            openExternal(url)
        }
    }

    func saveCurrentSession() {
        cleanupModels()
        let snapshots = registeredModels
            .compactMap(\.value)
            .compactMap { model -> SavedSessionWindow? in
                let frameString = registeredWindows[ObjectIdentifier(model)]?.value
                    .map { NSStringFromRect($0.frame) }
                return model.sessionSnapshot(frameString: frameString)
            }
        AppModel.saveSessionWindows(snapshots)
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

    private func openNewWindow(session: SavedSessionWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 520, height: 620)
        window.title = session.tabs.first.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "FileViewer"
        window.contentView = NSHostingView(rootView: ContentView(restoring: session))
        if let frameString = session.frameString {
            let savedFrame = NSRectFromString(frameString)
            if savedFrame.width > 0, savedFrame.height > 0 {
                window.setFrame(savedFrame, display: false)
            } else {
                window.center()
            }
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        retainedWindows.append(window)
    }

    private func scheduleSessionRestoreIfPossible(using model: AppModel) {
        guard !sessionRestoreScheduled,
              !suppressSessionRestore,
              model.canAcceptExternalOpenInCurrentWindow else { return }
        sessionRestoreScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak model] in
            guard let self,
                  let model else { return }
            self.sessionRestoreScheduled = false
            guard !self.suppressSessionRestore,
                  model.canAcceptExternalOpenInCurrentWindow else { return }
            let savedWindows = AppModel.loadSavedSessionWindows()
            guard let firstWindow = savedWindows.first else { return }
            if let frameString = firstWindow.frameString,
               let window = self.registeredWindows[ObjectIdentifier(model)]?.value {
                let savedFrame = NSRectFromString(frameString)
                if savedFrame.width > 0, savedFrame.height > 0 {
                    window.setFrame(savedFrame, display: true)
                }
            }
            model.restoreSavedSession(window: firstWindow)
            self.restoreAdditionalSessionWindowsIfNeeded(from: model, savedWindows: savedWindows)
        }
    }

    private func restoreAdditionalSessionWindowsIfNeeded(from model: AppModel, savedWindows: [SavedSessionWindow]) {
        guard model.restoredFromSession,
              !restoredAdditionalSessionWindows else { return }
        restoredAdditionalSessionWindows = true
        let additionalWindows = Array(savedWindows.dropFirst())
        for session in additionalWindows {
            openNewWindow(session: session)
        }
    }

    private func cleanupModels() {
        registeredModels.removeAll { $0.value == nil }
        registeredWindows = registeredWindows.filter { $0.value.value != nil }
    }

    private func releaseClosedWindowLater(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            self.windowDelegates.removeValue(forKey: key)
        }
    }
}

private struct WeakAppModel {
    weak var value: AppModel?
}

private struct WeakWindow {
    weak var value: NSWindow?
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
