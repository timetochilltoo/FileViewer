import AppKit
import XCTest
@testable import FileViewer

final class WindowPreferencesTests: XCTestCase {
    func testSidebarPreferenceSurvivesNewSettingsInstanceAndHonorsOverrides() throws {
        let suite = "FileViewerTests.Sidebar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(SidebarPreferences.initialVisibility(defaults: defaults))
        defaults.set("remember", forKey: SidebarPreferences.launchModeKey)
        XCTAssertTrue(SidebarPreferences.initialVisibility(defaults: defaults))
        SidebarPreferences.remember(false, defaults: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertFalse(SidebarPreferences.initialVisibility(defaults: reopened))
        defaults.set("show", forKey: SidebarPreferences.launchModeKey)
        XCTAssertTrue(SidebarPreferences.initialVisibility(defaults: reopened))
        defaults.set("hide", forKey: SidebarPreferences.launchModeKey)
        SidebarPreferences.remember(true, defaults: defaults)
        XCTAssertFalse(SidebarPreferences.initialVisibility(defaults: reopened))
        defaults.set("invalid", forKey: SidebarPreferences.launchModeKey)
        XCTAssertTrue(SidebarPreferences.initialVisibility(defaults: reopened))
    }

    @MainActor
    func testWindowIdentityTracksDocumentChangesIndependently() {
        let first = AppModel()
        let second = AppModel()
        let window = NSWindow()
        let otherWindow = NSWindow()
        first.newMarkdownDocument()
        second.newMarkdownDocument()
        FileViewerWindowRegistry.updateDocumentIdentity(first, window: window)
        FileViewerWindowRegistry.updateDocumentIdentity(second, window: otherWindow)
        XCTAssertEqual(window.title, "Untitled.md — FileViewer")
        XCTAssertNil(window.representedURL)

        let url = URL(fileURLWithPath: "/tmp/renamed.md")
        first.document = .markdown(MarkdownDocument(url: url, untitledName: "", text: "", savedText: ""))
        FileViewerWindowRegistry.updateDocumentIdentity(first, window: window)
        XCTAssertEqual(window.title, "renamed.md — FileViewer")
        XCTAssertEqual(window.representedURL, url)
        XCTAssertEqual(otherWindow.title, "Untitled.md — FileViewer")
        first.document = nil
        FileViewerWindowRegistry.updateDocumentIdentity(first, window: window)
        XCTAssertEqual(window.title, "FileViewer")
        XCTAssertNil(window.representedURL)
    }

    @MainActor
    func testMenuCleanupPreservesNativeEditingAndRemovesInjectedServices() {
        let menu = NSMenu()
        menu.addItem(.separator())
        for action in ["undo:", "redo:", "cut:", "copy:", "paste:", "delete:", "selectAll:"] {
            menu.addItem(NSMenuItem(title: action, action: NSSelectorFromString(action), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        let service = NSMenuItem(title: "Localized system service", action: nil, keyEquivalent: "")
        service.submenu = NSMenu()
        menu.addItem(service)
        menu.addItem(NSMenuItem(title: "Dictation", action: NSSelectorFromString("startDictation:"), keyEquivalent: ""))
        menu.addItem(.separator())
        FileViewerMenuPolicy.cleanEditMenu(menu)
        FileViewerMenuPolicy.cleanEditMenu(menu)
        XCTAssertEqual(menu.items.count, 7)
        XCTAssertEqual(Set(menu.items.compactMap(\.action).map(NSStringFromSelector)), FileViewerMenuPolicy.editingActions)
    }
}
