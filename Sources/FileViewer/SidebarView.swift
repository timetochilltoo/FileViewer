import PDFKit
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sidebar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .center)
                modeSelector
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            switch model.sidebarMode {
            case .library:
                libraryList
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
            .contextMenu {
                LibraryTagActions(model: model, url: recent.url)

                Divider()

                Button("Add to Library", systemImage: "books.vertical") {
                    model.addLibraryFile(recent.url)
                }
                .disabled(model.libraryFiles.contains { $0.path == recent.url.path })

                Button("Copy to Library Folder…", systemImage: "doc.on.doc") {
                    model.copyDocumentToLibraryFolder(recent.url)
                }
            }
        }
        .overlay {
            if model.recents.isEmpty {
                ContentUnavailableView("No Recent Files", systemImage: "clock")
            }
        }
    }

    private var libraryList: some View {
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search library", text: $model.libraryQuery)
                    .textFieldStyle(.roundedBorder)
                    .help("Search indexed filenames, tags, headings, document text, and annotations")

                Menu {
                    Button {
                        model.selectedLibraryTag = nil
                    } label: {
                        if model.selectedLibraryTag == nil {
                            Label("All Tags", systemImage: "checkmark")
                        } else {
                            Text("All Tags")
                        }
                    }
                    if !model.libraryTagOptions.isEmpty {
                        Divider()
                        ForEach(model.libraryTagOptions, id: \.self) { tag in
                            Button {
                                model.selectedLibraryTag = tag
                            } label: {
                                if model.selectedLibraryTag?.localizedCaseInsensitiveCompare(tag) == .orderedSame {
                                    Label(tag, systemImage: "checkmark")
                                } else {
                                    Text(tag)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: model.selectedLibraryTag == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .disabled(model.libraryTagOptions.isEmpty && model.selectedLibraryTag == nil)
                .help(model.selectedLibraryTag.map { "Filtered by \($0)" } ?? "Filter by tag")
                .accessibilityLabel(model.selectedLibraryTag.map { "Filter by \($0)" } ?? "Filter by tag")

                Menu {
                    Button("Add Folder…") {
                        model.addLibraryFolder()
                    }
                    if !model.libraryFolders.isEmpty {
                        Divider()
                        Section("Indexed Folders") {
                            ForEach(model.libraryFolders, id: \.path) { folder in
                                Button {
                                    model.removeLibraryFolder(folder)
                                } label: {
                                    Label("Remove \(folder.lastPathComponent)", systemImage: "minus.circle")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .help("Manage Library Folders")
                .accessibilityLabel("Manage Library Folders")

                Button {
                    model.refreshLibraryIndex()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(model.isLibraryIndexing)
                .help("Refresh Library Index")
                .accessibilityLabel("Refresh Library Index")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            HStack(spacing: 6) {
                if model.isLibraryIndexing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Indexing local files…")
                } else if model.libraryFolders.isEmpty {
                    Text("Recent files only")
                } else {
                    Text("\(model.libraryFolders.count) folder\(model.libraryFolders.count == 1 ? "" : "s")")
                }
                Spacer()
                Text("\(model.libraryIndexedFileCount) files")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            Divider()

            List {
                if !model.libraryResults.isEmpty {
                    Section("Library") {
                        ForEach(consolidatedLibraryResults) { result in
                            libraryResultRow(result)
                        }
                    }
                }
            }
            .overlay {
                if model.libraryResults.isEmpty {
                    ContentUnavailableView(
                        model.libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.selectedLibraryTag == nil
                            ? "No Indexed Files"
                            : "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text(libraryEmptyDescription)
                    )
                }
            }
        }
        .onAppear {
            model.ensureLibraryIndex()
        }
    }

    private var consolidatedLibraryResults: [LibrarySearchResult] {
        model.libraryResults.sorted { lhs, rhs in
            let lhsPriority = lhs.isExplicit ? 0 : (lhs.isRecent ? 2 : 1)
            let rhsPriority = rhs.isExplicit ? 0 : (rhs.isRecent ? 2 : 1)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func libraryResultRow(_ result: LibrarySearchResult) -> some View {
        Button {
            model.openLibraryResult(result)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.kind == .pdf ? "doc.richtext" : "doc.plaintext")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(result.name)
                            .lineLimit(1)
                        if result.isRecent {
                            Text("Recent")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if result.isExplicit {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help("Added to Library")
                        }
                    }
                    if !result.tags.isEmpty {
                        Text(result.tags.joined(separator: " · "))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }
                    Text(result.reason)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !result.snippet.isEmpty {
                        Text(result.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Text(result.location)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(result.url.path)
        .contextMenu {
            LibraryTagActions(model: model, url: result.url)

            Divider()

            Button("Add to Library", systemImage: "books.vertical") {
                model.addLibraryFile(result.url)
            }
            .disabled(result.isExplicit)

            Button("Copy to Library Folder…", systemImage: "doc.on.doc") {
                model.copyDocumentToLibraryFolder(result.url)
            }

            if result.isExplicit {
                Divider()
                Button("Remove from Library", systemImage: "minus.circle") {
                    model.removeLibraryFile(result.url)
                }
            }
        }
    }

    private var libraryEmptyDescription: String {
        if let selectedLibraryTag = model.selectedLibraryTag {
            return "No files are tagged “\(selectedLibraryTag)”. Choose another tag or clear the tag filter."
        }
        return model.libraryFolders.isEmpty
            ? "Open files or add a local folder to build the library."
            : "Try another filename, heading, or document phrase."
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
                            model.postPDFCommand(.pdfGoToPage, object: page)
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
                model.postPDFCommand(.pdfGoToPage, object: page)
            }
        } else {
            ContentUnavailableView("No PDF Open", systemImage: "doc.richtext")
        }
    }

    @ViewBuilder
    private var pdfAnnotations: some View {
        if let url = model.selectedPDFURL {
            let allEntries = model.pdfAnnotationEntries
            let entries = model.filteredPDFAnnotationEntries
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Picker("Annotation Filter", selection: $model.pdfAnnotationFilter) {
                        ForEach(PDFAnnotationFilter.allCases, id: \.self) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        model.exportPDFAnnotationSummary()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    .help("Export Annotation Summary")
                    .disabled(allEntries.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                Divider()

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
                    if allEntries.isEmpty {
                        ContentUnavailableView("No Annotations", systemImage: "note.text")
                    } else if entries.isEmpty {
                        ContentUnavailableView("No \(model.pdfAnnotationFilter.title)", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        } else {
            ContentUnavailableView("No PDF Open", systemImage: "doc.richtext")
        }
    }
}

struct LibraryTagActions: View {
    @ObservedObject var model: AppModel
    let url: URL

    @ViewBuilder
    var body: some View {
        Button("Add Tag…", systemImage: "tag") {
            model.addLibraryTag(to: url)
        }

        let tags = model.libraryTags(for: url)
        if !tags.isEmpty {
            Divider()
            ForEach(tags, id: \.self) { tag in
                Button("Remove Tag: \(tag)", systemImage: "tag.slash") {
                    model.removeLibraryTag(tag, from: url)
                }
            }
        }
    }
}
