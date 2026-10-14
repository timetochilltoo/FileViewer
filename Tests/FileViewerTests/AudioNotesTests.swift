import AVFoundation
import XCTest
@testable import FileViewer

final class AudioNotesTests: XCTestCase {
    @MainActor
    private func fixture(in root: URL) throws -> URL {
        let url = root.appendingPathComponent("Silent Sample.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = 8000
        buffer.floatChannelData?[0].initialize(repeating: 0, count: 8000)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @MainActor
    func testImportIsIndependentPrivateAndPreservesPageMarkers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(in: root)
        let original = try Data(contentsOf: source)
        let store = AudioNoteStore(root: root.appendingPathComponent("Notes"))
        let document = root.appendingPathComponent("Document.pdf")
        var note = try store.importAudio(source, documentURL: document, page: 7)
        XCTAssertEqual(note.duration, 1, accuracy: 0.05)
        XCTAssertEqual(note.markers.first?.page, 7)
        XCTAssertEqual(note.documentURL, document)
        XCTAssertEqual(try store.data(for: note), original)
        note.markers.append(AudioPageMarker(seconds: 0.5, page: 8))
        try store.save(note)
        XCTAssertEqual(try store.list(), [note])
        XCTAssertEqual(try Data(contentsOf: source), original)
        let rootPermissions = try FileManager.default.attributesOfItem(atPath: store.root.path)[.posixPermissions] as? Int
        let audioPermissions = try FileManager.default.attributesOfItem(atPath: store.audioURL(for: note).path)[.posixPermissions] as? Int
        XCTAssertEqual(rootPermissions, 0o700)
        XCTAssertEqual(audioPermissions, 0o600)
        let second = try store.importAudio(source, documentURL: document, page: 2)
        XCTAssertNotEqual(second.id, note.id)
        XCTAssertEqual(try store.list().count, 2)
    }

    @MainActor
    func testRejectsRemoteSymlinkOversizeAndInvalidAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(in: root)
        let link = root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try AudioNoteStore.read(link, limit: AudioNoteStore.maximumBytes))
        XCTAssertThrowsError(try AudioNoteStore.read(source, limit: 10))
        XCTAssertThrowsError(try AudioNoteStore.read(URL(string: "https://example.com/audio.wav")!, limit: 100))
        let store = AudioNoteStore(root: root.appendingPathComponent("Notes"))
        let bad = root.appendingPathComponent("bad.wav")
        try Data("not audio".utf8).write(to: bad)
        XCTAssertThrowsError(try store.importAudio(bad, documentURL: root.appendingPathComponent("source.pdf"), page: 1))
        XCTAssertThrowsError(try store.importAudio(source, documentURL: URL(string: "https://example.com/source.pdf")!, page: 1))
        XCTAssertTrue(try store.list().isEmpty)
    }

    @MainActor
    func testMetadataValidationAndRecoveryDoNotDiscardAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioNoteStore(root: root.appendingPathComponent("Notes"))
        var note = try store.importAudio(fixture(in: root), documentURL: root.appendingPathComponent("source.pdf"), page: 1)
        let audio = try store.data(for: note)
        note.incomplete = true
        note.duration = 0
        try store.save(note)
        XCTAssertEqual(try store.list().first?.incomplete, true)
        XCTAssertEqual(try store.data(for: note), audio)
        var invalid = note
        invalid.markers = [AudioPageMarker(seconds: .nan, page: 1)]
        XCTAssertThrowsError(try AudioNoteStore.validate(invalid))
        invalid.markers = [AudioPageMarker(seconds: 1, page: 0)]
        XCTAssertThrowsError(try AudioNoteStore.validate(invalid))
        invalid.markers = (0...500).map { AudioPageMarker(seconds: Double($0), page: 1) }
        XCTAssertThrowsError(try AudioNoteStore.validate(invalid))
        invalid = note
        invalid.duration = .infinity
        XCTAssertThrowsError(try AudioNoteStore.validate(invalid))
        try Data("{}".utf8).write(to: store.root.appendingPathComponent("invalid.json"))
        XCTAssertEqual(try store.list(), [note])
        XCTAssertEqual(try store.data(for: note), audio)
    }

    @MainActor
    func testDeniedAndCancelledPermissionNeverStartsRecording() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let denied = AudioNotesController(store: AudioNoteStore(root: root), permission: { false })
        await denied.start(documentURL: root.appendingPathComponent("source.pdf"), tabID: UUID(), page: 1, title: "Test")
        XCTAssertFalse(denied.isBusy)
        XCTAssertNil(denied.recordingNote)
        XCTAssertNotNil(denied.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let gate = PermissionGate()
        let controller = AudioNotesController(store: AudioNoteStore(root: root), permission: { await gate.request() })
        let tabID = UUID()
        let task = Task { await controller.start(documentURL: root.appendingPathComponent("source.pdf"), tabID: tabID, page: 1, title: "Test") }
        for _ in 0..<100 where controller.pendingTabID == nil { await Task.yield() }
        XCTAssertEqual(controller.pendingTabID, tabID)
        controller.sourceClosed(tabID: tabID)
        await gate.finish(true)
        await task.value
        XCTAssertNil(controller.recordingNote)
        XCTAssertFalse(controller.isBusy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testTimeLabelsAreBounded() {
        XCTAssertEqual(AudioNotesController.timeLabel(65), "01:05")
        XCTAssertEqual(AudioNotesController.timeLabel(.infinity), "00:00")
        XCTAssertEqual(AudioNotesController.timeLabel(-1), "00:00")
        XCTAssertEqual(AudioNotesController.timeLabel(99999), "60:00")
    }

    @MainActor
    func testCommandLineBundleCannotRequestMicrophone() async throws {
        guard !(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") is String) else {
            throw XCTSkip("Only checks bundles lacking a microphone usage description")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let controller = AudioNotesController(store: AudioNoteStore(root: root))
        await controller.start(documentURL: root.appendingPathComponent("source.pdf"), tabID: UUID(), page: 1, title: "Test")
        XCTAssertNil(controller.recordingNote)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testPlaybackPauseSeekAndOwnerCloseAfterSaveAs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioNoteStore(root: root.appendingPathComponent("Notes"))
        let note = try store.importAudio(fixture(in: root), documentURL: root.appendingPathComponent("original.pdf"), page: 1)
        let controller = AudioNotesController(store: store, permission: { false })
        defer { controller.stopPlayback() }
        controller.refresh()
        let tabID = UUID()
        controller.play(note, tabID: tabID)
        guard controller.playingID == note.id else { throw XCTSkip("Audio output is unavailable in this test environment") }
        controller.togglePlayback()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playingID, note.id)
        controller.seek(to: 0.5)
        XCTAssertEqual(controller.playbackSeconds, 0.5, accuracy: 0.05)
        controller.addPlaybackMarker(page: 3, documentURL: note.documentURL)
        XCTAssertEqual(try store.list().first?.markers.last?.page, 3)
        controller.sourceClosed(tabID: UUID(), documentURL: root.appendingPathComponent("other.pdf"))
        XCTAssertEqual(controller.playingID, note.id)
        controller.sourceClosed(tabID: tabID, documentURL: root.appendingPathComponent("saved-as.pdf"))
        XCTAssertNil(controller.playingID)
        XCTAssertFalse(controller.isPlaying)
    }

    @MainActor
    func testMarkdownAudioImportPersistsHeadingAndPreservesOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Notes.md")
        let text = "# Introduction\n\nNotes\n\n## Results 🎧\n\nMore text"
        try Data(text.utf8).write(to: document)
        let audio = try fixture(in: root)
        let originalAudio = try Data(contentsOf: audio)
        let store = AudioNoteStore(root: root.appendingPathComponent("Audio"))
        let anchor = try XCTUnwrap(AudioMarkdownAnchor.options(for: AppModel.extractHeadings(from: text)).last)
        let note = try store.importAudio(audio, documentURL: document, page: 1, markdownAnchor: anchor)
        XCTAssertEqual(try store.list().first?.markers.first?.markdownAnchor, anchor)
        XCTAssertEqual(try store.data(for: note), originalAudio)
        XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), text)
        XCTAssertEqual(try Data(contentsOf: audio), originalAudio)
        let startNote = try store.importAudio(audio, documentURL: document, page: 1)
        XCTAssertEqual(startNote.markers.first?.markdownAnchor, .documentStart)
        var invalid = note
        invalid.markers = [AudioPageMarker(seconds: 0, page: 1)]
        XCTAssertThrowsError(try AudioNoteStore.validate(invalid))
    }

    @MainActor
    func testHeadingAnchorSurvivesOffsetsButRejectsRenamesAndAmbiguousDuplicates() throws {
        let text = "# Intro\n\n## Results 🎧\n\nText"
        let headings = AppModel.extractHeadings(from: text)
        let anchor = try XCTUnwrap(AudioMarkdownAnchor.options(for: headings).last)
        let edited = AppModel.extractHeadings(from: "Inserted 😀 text\n\n" + text)
        XCTAssertEqual(anchor.resolve(in: edited)?.title, "Results 🎧")
        XCTAssertNotEqual(anchor.resolve(in: edited)?.sourceLocation, headings.last?.sourceLocation)
        XCTAssertNil(anchor.resolve(in: AppModel.extractHeadings(from: "## Renamed\n")))
        XCTAssertNil(anchor.resolve(in: AppModel.extractHeadings(from: "## Results 🎧\n\n## Results 🎧")))
        let duplicates = AppModel.extractHeadings(from: "## Same\n\nText\n\n## Same\n")
        let second = try XCTUnwrap(AudioMarkdownAnchor.options(for: duplicates).last)
        XCTAssertEqual(second.occurrence, 1)
        XCTAssertEqual(second.resolve(in: duplicates), duplicates.last)
        XCTAssertNil(second.resolve(in: AppModel.extractHeadings(from: "## Same")))
        let fenced = AppModel.extractHeadings(from: "```\n# Not a heading\n```\n# Real")
        XCTAssertEqual(AudioMarkdownAnchor.options(for: fenced).map(\.title), ["Real"])
    }

    @MainActor
    func testLegacyPDFMetadataAndReadOnlyMarkdownNavigation() throws {
        let pdfNote = AudioNote(id: UUID(), documentURL: URL(fileURLWithPath: "/tmp/old.pdf"), title: "Old", created: Date(),
                                audioExtension: "wav", duration: 1, markers: [AudioPageMarker(seconds: 0, page: 3)], incomplete: false)
        let data = try JSONEncoder().encode(pdfNote)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("markdownAnchor"))
        let legacy = try JSONDecoder().decode(AudioNote.self, from: data)
        XCTAssertEqual(legacy, pdfNote)
        XCTAssertNoThrow(try AudioNoteStore.validate(legacy))
        let model = AppModel(opening: [])
        let text = "# Intro\n\n## Next\n\nBody"
        let tab = DocumentTab(document: .markdown(MarkdownDocument(url: URL(fileURLWithPath: "/tmp/notes.md"), untitledName: "Notes.md", text: text, savedText: text)))
        model.tabs = [tab]
        model.selectedTabID = tab.id
        let anchor = try XCTUnwrap(AudioMarkdownAnchor.options(for: model.markdownHeadings).last)
        XCTAssertTrue(model.navigateToAudioMarkdownAnchor(anchor))
        XCTAssertTrue(model.navigateToAudioMarkdownAnchor(.documentStart))
        guard case .markdown(let document) = model.document else { return XCTFail("Missing Markdown") }
        XCTAssertEqual(document.text, text)
        XCTAssertFalse(document.hasUnsavedChanges)
        model.updateMarkdown("# Intro\n\n## Changed\n\nBody")
        XCTAssertFalse(model.navigateToAudioMarkdownAnchor(anchor))
        guard case .markdown(let edited) = model.document else { return XCTFail("Missing Markdown") }
        XCTAssertTrue(edited.hasUnsavedChanges)
        XCTAssertEqual(edited.savedText, text)
    }
}

private actor PermissionGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var result: Bool?
    func request() async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ result: Bool) {
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}
