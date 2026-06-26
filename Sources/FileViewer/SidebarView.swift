import PDFKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $model.sidebarMode) {
                ForEach(SidebarMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            switch model.sidebarMode {
            case .recent:
                recentList
            case .contents:
                contentsList
            case .pages:
                pdfPages
            }
        }
    }

    private var recentList: some View {
        List(model.recents) { recent in
            Button {
                model.reopenRecent(recent)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recent.name)
                            .lineLimit(1)
                        Text(recent.kind.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: recent.kind == .pdf ? "doc.richtext" : "doc.plaintext")
                }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if model.recents.isEmpty {
                ContentUnavailableView("No Recent Files", systemImage: "clock")
            }
        }
    }

    private var contentsList: some View {
        List(model.markdownHeadings) { heading in
            Text(heading.title)
                .lineLimit(1)
                .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 12)
        }
        .overlay {
            if model.markdownHeadings.isEmpty {
                ContentUnavailableView("No Headings", systemImage: "list.bullet")
            }
        }
    }

    @ViewBuilder
    private var pdfPages: some View {
        if case .pdf(let viewerDocument) = model.document {
            PDFThumbnailSidebar(document: viewerDocument.document) { page in
                NotificationCenter.default.post(name: .pdfGoToPage, object: page)
            }
        } else {
            ContentUnavailableView("No PDF Open", systemImage: "doc.richtext")
        }
    }
}
