import SwiftUI

enum SidebarLaunchMode: String, CaseIterable {
    case show, hide, remember

    var title: String {
        switch self {
        case .show: "Show Sidebar"
        case .hide: "Hide Sidebar"
        case .remember: "Remember Last State"
        }
    }
}

enum SidebarPreferences {
    static let launchModeKey = "FileViewer.sidebar.launchMode"
    static let lastVisibleKey = "FileViewer.sidebar.lastVisible"

    static func initialVisibility(defaults: UserDefaults = .standard) -> Bool {
        switch SidebarLaunchMode(rawValue: defaults.string(forKey: launchModeKey) ?? "") ?? .show {
        case .show: true
        case .hide: false
        case .remember: defaults.object(forKey: lastVisibleKey) as? Bool ?? true
        }
    }

    static func remember(_ visible: Bool, defaults: UserDefaults = .standard) {
        defaults.set(visible, forKey: lastVisibleKey)
    }
}

enum MarkdownPreferences {
    static let defaultModeKey = "FileViewer.markdown.defaultMode"
    static let legacyModeKey = "FileViewer.markdownMode"

    static func defaultMode(defaults: UserDefaults = .standard) -> MarkdownMode {
        if let rawValue = defaults.string(forKey: defaultModeKey),
           let mode = MarkdownMode(rawValue: rawValue) {
            return mode
        }

        // Preserve an existing installation's last global mode until the user
        // chooses an explicit default in Settings.
        if let rawValue = defaults.string(forKey: legacyModeKey),
           let mode = MarkdownMode(rawValue: rawValue) {
            return mode
        }
        return .split
    }
}

struct FileViewerSettingsView: View {
    @AppStorage(SidebarPreferences.launchModeKey) private var sidebarMode = SidebarLaunchMode.show.rawValue
    @AppStorage(MarkdownPreferences.defaultModeKey) private var markdownDefaultMode = MarkdownMode.split.rawValue
    @AppStorage(LibraryCachePreferences.enabledKey) private var libraryCacheEnabled = false
    @State private var cacheStatus = ""

    var body: some View {
        Form {
            Section("Library") {
                Toggle("Keep a local search index between launches", isOn: $libraryCacheEnabled)
                Text("Stores extracted document text on this Mac to speed up Library search after restarting. Off by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Clear Cached Index and Turn Off Caching") {
                    libraryCacheEnabled = false
                    clearLibraryCache()
                }
                if !cacheStatus.isEmpty { Text(cacheStatus).font(.caption) }
            }
            Section("Sidebar") {
                Picker("When opening a window", selection: $sidebarMode) {
                    ForEach(SidebarLaunchMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Text("Applies at launch and to new document windows. Remember Last State uses your most recent sidebar toggle. Existing windows keep their current layout.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Markdown") {
                Picker("Default view for new documents", selection: $markdownDefaultMode) {
                    ForEach(MarkdownMode.allCases, id: \.rawValue) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                Text("Applies when a Markdown document window opens. You can still switch views from the toolbar or Display menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onChange(of: libraryCacheEnabled) { _, enabled in
            if enabled {
                NotificationCenter.default.post(name: LibraryCachePreferences.changed, object: nil)
                cacheStatus = "The index will be saved after Library refresh."
            } else {
                clearLibraryCache()
            }
        }
    }

    private func clearLibraryCache() {
        Task {
            do {
                try await LibraryIndexCache.shared.clear()
                cacheStatus = "Cached index cleared. Library files and tags are kept."
            } catch {
                cacheStatus = "Could not clear the cached index. Please try again."
            }
        }
    }
}
