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

struct FileViewerSettingsView: View {
    @AppStorage(SidebarPreferences.launchModeKey) private var sidebarMode = SidebarLaunchMode.show.rawValue

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 210)
    }
}
