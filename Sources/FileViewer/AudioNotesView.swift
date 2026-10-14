import SwiftUI
import UniformTypeIdentifiers

struct AudioNotesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var audio = AudioNotesController.shared
    @State private var title = "Audio Note"

    private var documentURL: URL? { model.isPDFDocument ? model.document?.url?.standardizedFileURL : nil }
    private var notes: [AudioNote] { audio.notes.filter { $0.documentURL == documentURL && $0.id != audio.recordingNote?.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Audio Notes").font(.headline)
                Spacer()
                Button("Import…") { importAudio() }.disabled(documentURL == nil || audio.isBusy)
                Button {
                    audio.stopRecording()
                    audio.stopPlayback()
                    model.audioNotesVisible = false
                } label: { Image(systemName: "xmark") }.help("Stop audio and close Audio Notes")
            }
            if let note = audio.recordingNote {
                HStack {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                    Text("Recording \(AudioNotesController.timeLabel(audio.recordingSeconds))").monospacedDigit()
                    Spacer()
                    Button("Stop & Save") { audio.stopRecording() }
                }
                HStack {
                    Text(note.documentURL.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Add Page Marker") {
                        if let documentURL { audio.addMarker(page: model.pdfPage, documentURL: documentURL) }
                    }.disabled(documentURL != note.documentURL || note.markers.count >= 500)
                }
            } else if audio.pendingTabID != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for microphone permission…")
                    Spacer()
                    Button("Cancel") { audio.stopRecording() }
                }
            } else {
                HStack {
                    TextField("Recording name", text: $title).frame(maxWidth: 180)
                    Button("Record", systemImage: "mic.fill") {
                        guard let documentURL, let tabID = model.selectedTabID else { return }
                        let page = model.pdfPage
                        Task {
                            guard model.tabs.contains(where: { $0.id == tabID && $0.document.url?.standardizedFileURL == documentURL }) else { return }
                            await audio.start(documentURL: documentURL, tabID: tabID, page: page, title: title)
                        }
                    }.disabled(documentURL == nil)
                }
                if audio.playingID == nil {
                    Text("Up to 1 hour. Recorded only after you press Record.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let playingID = audio.playingID, let note = audio.notes.first(where: { $0.id == playingID }) {
                HStack {
                    Text(note.title).lineLimit(1)
                    Text("\(AudioNotesController.timeLabel(audio.playbackSeconds)) / \(AudioNotesController.timeLabel(note.duration))").monospacedDigit()
                    Spacer()
                    Button("Stop") { audio.stopPlayback() }
                }
                HStack {
                    Slider(value: Binding(get: { audio.playbackSeconds }, set: { audio.seek(to: $0) }), in: 0...max(0.1, note.duration))
                        .accessibilityLabel("Audio playback position")
                    Button(audio.isPlaying ? "Pause" : "Resume") { audio.togglePlayback() }
                    Button("Mark Current Page") {
                        if let documentURL { audio.addPlaybackMarker(page: model.pdfPage, documentURL: documentURL) }
                    }.disabled(documentURL != note.documentURL || note.markers.count >= 500)
                }
            }
            if let message = audio.errorMessage {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(3)
                    Spacer()
                    Button("Dismiss") { audio.errorMessage = nil }
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if notes.isEmpty { Text("Record or import audio for this PDF. Page markers play from their timestamp and jump to that page; page edits can shift these links.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(note.title).fontWeight(.medium).lineLimit(1)
                                Text(note.incomplete ? "Interrupted / unfinished" : AudioNotesController.timeLabel(note.duration)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Play") { audio.play(note, tabID: model.selectedTabID) }.disabled(audio.isBusy)
                                Menu {
                                    Button("Reveal Audio in Finder") {
                                        if let url = try? audio.store.audioURL(for: note) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                    }
                                    Button("Move to Trash…") { trash(note) }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize()
                            }
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(note.markers.sorted { $0.seconds < $1.seconds }) { marker in
                                        Button("Page \(marker.page) · \(AudioNotesController.timeLabel(marker.seconds))") {
                                            guard marker.page <= model.pdfPageCount else {
                                                audio.errorMessage = "This page no longer exists in the PDF. The recording is still available."
                                                return
                                            }
                                            model.postPDFCommand(.pdfGoToPage, object: marker.page)
                                            audio.play(note, at: marker.seconds, tabID: model.selectedTabID)
                                        }.disabled(audio.isBusy)
                                    }
                                }
                            }
                        }
                        Divider()
                    }
                }
            }
        }
        .padding(12)
        .frame(height: 260)
        .onAppear { audio.refresh() }
    }

    private func importAudio() {
        guard let documentURL else { return }
        let page = model.pdfPage
        let panel = NSOpenPanel()
        panel.allowedContentTypes = AudioNoteStore.extensions.compactMap { UTType(filenameExtension: $0) }
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            audio.importAudio(url, documentURL: documentURL, page: page)
        }
    }

    private func trash(_ note: AudioNote) {
        let alert = NSAlert()
        alert.messageText = "Move this audio note to Trash?"
        alert.informativeText = "The local recording and its page-marker metadata will be moved to macOS Trash. The PDF is unchanged."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { audio.trash(note) }
    }
}
