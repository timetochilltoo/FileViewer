import PDFKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sidebar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Sidebar", selection: $model.sidebarMode) {
                    ForEach(SidebarMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
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
        Group {
            switch model.document {
            case .markdown:
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
            case .pdf:
                List(model.pdfOutlineEntries) { entry in
                    Button {
                        if let page = entry.page {
                            NotificationCenter.default.post(name: .pdfGoToPage, object: page)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.page == nil ? "text.book.closed" : "text.book.closed.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .lineLimit(2)
                                if let page = entry.page {
                                    Text("Page \(page)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.leading, CGFloat(max(entry.level - 1, 0)) * 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.page == nil)
                }
                .overlay {
                    if model.pdfOutlineEntries.isEmpty {
                        ContentUnavailableView("No PDF Outline", systemImage: "list.bullet.rectangle")
                    }
                }
            case nil:
                ContentUnavailableView("No Document Open", systemImage: "doc")
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
