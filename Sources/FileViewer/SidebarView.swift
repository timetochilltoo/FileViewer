import PDFKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    let onToggleSidebar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sidebar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onToggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Sidebar")
                }
                modeSelector
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            switch model.sidebarMode {
            case .recent:
                recentList
            case .contents:
                contentsList
            case .pages:
                pdfPages
            case .annotations:
                pdfAnnotations
            }
        }
        .frame(minWidth: 320, idealWidth: 320, maxWidth: 320)
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(SidebarMode.allCases, id: \.self) { mode in
                Button {
                    model.sidebarMode = mode
                } label: {
                    Text(mode.title)
                        .font(.callout.weight(model.sidebarMode == mode ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.sidebarMode == mode ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(model.sidebarMode == mode ? Color.accentColor : Color.clear)
                )
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder
    private var pdfAnnotations: some View {
        if let url = model.selectedPDFURL {
            let entries = model.pdfAnnotationEntries
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            NotificationCenter.default.post(
                                name: .pdfGoToAnnotation,
                                object: PDFAnnotationNavigationTarget(
                                    url: url,
                                    page: entry.page,
                                    bounds: entry.bounds
                                )
                            )
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: entry.iconName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(entry.kind)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("p.\(entry.page)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text(entry.summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 40)
                    }
                }
                .padding(.top, 4)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No Annotations", systemImage: "note.text")
                }
            }
        } else {
            ContentUnavailableView("No PDF Open", systemImage: "doc.richtext")
        }
    }
}
