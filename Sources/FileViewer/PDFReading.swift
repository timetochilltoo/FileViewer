import AppKit
import PDFKit
import SwiftUI

enum PDFReadingLayout: String, Codable, CaseIterable, Identifiable {
    case continuous, singlePage, twoPages
    var id: Self { self }
    var title: String {
        switch self {
        case .continuous: "Continuous Pages"
        case .singlePage: "Single Page"
        case .twoPages: "Two-Page Spread"
        }
    }
    var displayMode: PDFDisplayMode {
        switch self {
        case .continuous: .singlePageContinuous
        case .singlePage: .singlePage
        case .twoPages: .twoUp
        }
    }
}

struct PDFReadingActions: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ForEach(PDFReadingLayout.allCases) { layout in
            Button {
                model.pdfReadingLayout = layout
            } label: {
                if model.pdfReadingLayout == layout {
                    Label(layout.title, systemImage: "checkmark")
                } else { Text(layout.title) }
            }
        }
        Divider()
        Button("Start Fullscreen Presentation…") { model.startPDFPresentation() }
    }
}

/// Independent, read-only snapshots never become another writable file owner.
@MainActor
final class PDFPresentationController: NSWindowController, NSWindowDelegate {
    private static var active: [UUID: PDFPresentationController] = [:]
    private let id: UUID
    let pdfView = PresentationPDFView()
    private let pageLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let pointerButton = NSButton(title: "Laser Pointer (P)", target: nil, action: nil)
    private var keyMonitor: Any?
    private var pageObserver: NSObjectProtocol?

    static func present(tabID: UUID, document: PDFDocument, name: String, page: Int, fullscreen: Bool = true) -> PDFPresentationController? {
        if let existing = active[tabID] {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }
        guard document.pageCount > 0, !document.isLocked,
              let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { return nil }
        let controller = PDFPresentationController(id: tabID, document: copy, name: name, page: page)
        active[tabID] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.makeFirstResponder(controller.pdfView)
        if fullscreen { controller.window?.toggleFullScreen(nil) }
        return controller
    }

    private init(id: UUID, document: PDFDocument, name: String, page: Int) {
        self.id = id
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = name + " — Presentation"
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 500)
        super.init(window: window)
        window.delegate = self
        let content = NSView()
        window.contentView = content
        let laserOverlay = PresentationLaserOverlay()
        laserOverlay.translatesAutoresizingMaskIntoConstraints = false
        pdfView.onLaserPosition = { [weak laserOverlay] point in
            guard let laserOverlay else { return }
            laserOverlay.position = point.map { laserOverlay.convert($0, from: nil) }
        }
        pdfView.document = document
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = .black
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pdfView)
        previousButton.target = self; previousButton.action = #selector(previous)
        nextButton.target = self; nextButton.action = #selector(next)
        pointerButton.target = self; pointerButton.action = #selector(togglePointer)
        pointerButton.setButtonType(.toggle)
        let exit = NSButton(title: "Exit (Esc)", target: self, action: #selector(exitPresentation))
        let controls = NSStackView(views: [previousButton, pageLabel, nextButton, pointerButton, exit])
        controls.spacing = 16
        controls.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controls)
        // Keep the overlay outside PDFKit, which repositions its own subviews.
        content.addSubview(laserOverlay, positioned: .above, relativeTo: pdfView)
        NSLayoutConstraint.activate([
            laserOverlay.topAnchor.constraint(equalTo: pdfView.topAnchor),
            laserOverlay.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),
            laserOverlay.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
            laserOverlay.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: content.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -10),
            controls.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
        ])
        content.layoutSubtreeIfNeeded()
        pdfView.go(to: document.page(at: Self.clampedPage(page, count: document.pageCount) - 1)!)
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateControls() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53: self.exitPresentation()
            case 123, 126, 116: self.previous()
            case 124, 125, 121: self.next()
            case 49: event.modifierFlags.contains(.shift) ? self.previous() : self.next()
            case 115: self.go(to: 1)
            case 119: self.go(to: self.pdfView.document?.pageCount ?? 1)
            default:
                if event.charactersIgnoringModifiers?.lowercased() == "p" { self.togglePointer() }
                else { return event }
            }
            return nil
        }
        updateControls()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    static func clampedPage(_ page: Int, count: Int) -> Int { min(max(1, page), max(1, count)) }

    var currentPage: Int {
        guard let document = pdfView.document, let page = pdfView.currentPage else { return 1 }
        let index = document.index(for: page)
        guard (0..<document.pageCount).contains(index) else { return 1 }
        return index + 1
    }

    func go(to page: Int) {
        guard let document = pdfView.document, document.pageCount > 0,
              let target = document.page(at: Self.clampedPage(page, count: document.pageCount) - 1) else { return }
        pdfView.go(to: target)
        pdfView.autoScales = true
        updateControls()
        window?.makeFirstResponder(pdfView)
    }
    @objc private func previous() { go(to: currentPage - 1) }
    @objc private func next() { go(to: currentPage + 1) }
    @objc private func togglePointer() {
        pdfView.laserEnabled.toggle()
        pointerButton.state = pdfView.laserEnabled ? .on : .off
        window?.makeFirstResponder(pdfView)
    }
    @objc private func exitPresentation() { close() }
    private func updateControls() {
        let count = pdfView.document?.pageCount ?? 0
        pageLabel.stringValue = "Page \(currentPage) of \(count)"
        previousButton.isEnabled = currentPage > 1
        nextButton.isEnabled = currentPage < count
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver); self.pageObserver = nil }
        window?.sharingType = .none
        window?.isExcludedFromWindowsMenu = true
        pdfView.document = nil
        window?.contentView = nil
        Self.active[id] = nil
    }
}

/// No PDFKit mouse/keyboard editing or link actions in the presentation snapshot.
@MainActor
final class PresentationPDFView: PDFView {
    var laserEnabled = false { didSet { onLaserPosition?(nil) } }
    var onLaserPosition: ((NSPoint?) -> Void)?
    private var laserTracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let laserTracking { removeTrackingArea(laserTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        laserTracking = area
        window?.acceptsMouseMovedEvents = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {
        guard laserEnabled else { return }
        onLaserPosition?(event.locationInWindow)
    }
    override func mouseExited(with event: NSEvent) { onLaserPosition?(nil) }
}

@MainActor
private final class PresentationLaserOverlay: NSView {
    var position: NSPoint? { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        if let point = position {
            NSColor.systemRed.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)).fill()
        }
    }
}
