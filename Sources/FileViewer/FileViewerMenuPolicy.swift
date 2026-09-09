import AppKit

@MainActor
enum FileViewerMenuPolicy {
    // AppKit can insert text services after SwiftUI builds its commands. Keep
    // the native responder-chain editing actions but omit system text services.
    static let editingActions: Set<String> = [
        "undo:", "redo:", "cut:", "copy:", "paste:", "delete:", "selectAll:"
    ]

    static func install() {
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didAddItemNotification,
                     NSMenu.didChangeItemNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { scheduleCleanup() }
            }
        }
        scheduleCleanup()
    }

    private static var isCleaning = false
    private static var cleanupScheduled = false

    private static func scheduleCleanup() {
        guard !isCleaning, !cleanupScheduled else { return }
        cleanupScheduled = true
        // SwiftUI inserts placeholder items before assigning their actions.
        // Wait until this construction pass finishes before filtering them.
        DispatchQueue.main.async {
            cleanupScheduled = false
            cleanMainMenu()
        }
    }

    static func cleanMainMenu() {
        guard !isCleaning, let mainMenu = NSApp.mainMenu else { return }
        isCleaning = true
        defer { isCleaning = false }
        // Identify the Edit menu by its native actions, not its localized title.
        for menu in mainMenu.items.compactMap(\.submenu) {
            if menu.items.contains(where: { $0.action == #selector(NSText.paste(_:)) }) {
                cleanEditMenu(menu)
            }
            for item in menu.items {
                if let action = item.action, nativeTabActions.contains(NSStringFromSelector(action)) {
                    menu.removeItem(item)
                }
            }
            cleanSeparators(menu)
        }
    }

    private static let nativeTabActions: Set<String> = [
        "toggleTabBar:", "toggleTabOverview:", "selectPreviousTab:",
        "selectNextTab:", "moveTabToNewWindow:", "mergeAllWindows:"
    ]

    static func cleanEditMenu(_ menu: NSMenu) {
        for item in menu.items where !item.isSeparatorItem {
            guard let action = item.action,
                  editingActions.contains(NSStringFromSelector(action)),
                  item.submenu == nil else {
                menu.removeItem(item)
                continue
            }
        }
        cleanSeparators(menu)
    }

    private static func cleanSeparators(_ menu: NSMenu) {
        // Removing service groups can leave adjacent/trailing separators.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator {
                menu.removeItem(item)
            } else {
                previousWasSeparator = item.isSeparatorItem
            }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }
}
