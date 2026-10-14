import AppKit
import AVFoundation
import Darwin

struct AudioPageMarker: Codable, Equatable, Identifiable {
    let id: UUID
    let seconds: Double
    let page: Int
    let markdownAnchor: AudioMarkdownAnchor?

    init(seconds: Double, page: Int, markdownAnchor: AudioMarkdownAnchor? = nil) {
        id = UUID()
        self.seconds = seconds
        self.page = page
        self.markdownAnchor = markdownAnchor
    }
}

struct AudioNote: Codable, Equatable, Identifiable {
    let id: UUID
    let documentURL: URL
    var title: String
    let created: Date
    let audioExtension: String
    var duration: Double
    var markers: [AudioPageMarker]
    var incomplete: Bool
}

enum AudioNoteError: LocalizedError {
    case invalidFile, unavailable, invalidMetadata, permission, recording, limit
    var errorDescription: String? {
        switch self {
        case .invalidFile: "Choose a readable local audio file up to 100 MiB and one hour long (M4A, WAV, AIFF, CAF, or MP3)."
        case .unavailable: "The local Audio Notes folder is unavailable."
        case .invalidMetadata: "This audio note has invalid or unsupported metadata."
        case .permission: "Use the packaged FileViewer app and allow microphone access in System Settings > Privacy & Security > Microphone to record, or import an existing recording."
        case .recording: "Recording could not start. Check the microphone and available disk space."
        case .limit: "Audio Notes holds up to 1,000 recordings. Move unused notes to Trash before adding another."
        }
    }
}

/// Only metadata is enumerated. Playback/import use bounded no-symlink reads;
/// recordings are independent of the original document and Library text cache.
@MainActor
final class AudioNoteStore {
    static let maximumBytes = 100 * 1024 * 1024
    static let maximumDuration: Double = 3600
    static let extensions: Set<String> = ["m4a", "wav", "aiff", "aif", "caf", "mp3"]
    static func isMarkdown(_ url: URL) -> Bool { ["md", "markdown"].contains(url.pathExtension.lowercased()) }
    static func supportsDocument(_ url: URL) -> Bool { url.isFileURL && (url.pathExtension.lowercased() == "pdf" || isMarkdown(url)) }
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FileViewer/Audio Notes", isDirectory: true)
    }

    func prepare() throws {
        guard root.isFileURL else { throw AudioNoteError.unavailable }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw AudioNoteError.unavailable }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    static func read(_ url: URL, limit: Int) throws -> Data {
        guard url.isFileURL else { throw AudioNoteError.invalidFile }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AudioNoteError.invalidFile }
        defer { Darwin.close(descriptor) }
        var statValue = stat()
        guard fstat(descriptor, &statValue) == 0, statValue.st_mode & S_IFMT == S_IFREG,
              statValue.st_size > 0, statValue.st_size <= limit else { throw AudioNoteError.invalidFile }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            guard count >= 0 else { throw AudioNoteError.invalidFile }
            if count == 0 { return data }
            guard data.count + count <= limit else { throw AudioNoteError.invalidFile }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    static func validate(_ note: AudioNote) throws {
        guard supportsDocument(note.documentURL),
              extensions.contains(note.audioExtension), note.title.count <= 120, !note.title.isEmpty,
              note.duration.isFinite, (0...maximumDuration + 1).contains(note.duration),
              note.markers.count <= 500,
              note.markers.allSatisfy({ $0.page > 0 && $0.seconds.isFinite && (0...maximumDuration).contains($0.seconds) }),
              note.markers.allSatisfy({ isMarkdown(note.documentURL) ? $0.markdownAnchor?.isValid == true : $0.markdownAnchor == nil }),
              Set(note.markers.map(\.id)).count == note.markers.count else { throw AudioNoteError.invalidMetadata }
    }

    func audioURL(for note: AudioNote) throws -> URL {
        try Self.validate(note)
        return root.appendingPathComponent(note.id.uuidString).appendingPathExtension(note.audioExtension)
    }

    private func metadataURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("json") }

    func checkCapacity() throws {
        try prepare()
        let count = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.count
        guard count < 1000 else { throw AudioNoteError.limit }
    }

    func save(_ note: AudioNote, creating: Bool = false) throws {
        try Self.validate(note)
        try prepare()
        let data = try JSONEncoder().encode(note)
        guard data.count <= 65536 else { throw AudioNoteError.invalidMetadata }
        let url = metadataURL(note.id)
        if creating { try checkCapacity() }
        try data.write(to: url, options: creating ? .withoutOverwriting : .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func list() throws -> [AudioNote] {
        try prepare()
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }.prefix(1000).compactMap { url in
                guard let data = try? Self.read(url, limit: 65536),
                      let note = try? JSONDecoder().decode(AudioNote.self, from: data),
                      note.id.uuidString == url.deletingPathExtension().lastPathComponent,
                      (try? Self.validate(note)) != nil else { return nil }
                return note
            }.sorted { $0.created > $1.created }
    }

    func data(for note: AudioNote) throws -> Data {
        try prepare()
        return try Self.read(audioURL(for: note), limit: Self.maximumBytes)
    }

    static func duration(of data: Data) throws -> Double {
        let player = try AVAudioPlayer(data: data)
        guard player.duration.isFinite, player.duration > 0, player.duration <= maximumDuration + 1 else { throw AudioNoteError.invalidFile }
        return min(player.duration, maximumDuration)
    }

    func importAudio(_ source: URL, documentURL: URL, page: Int, markdownAnchor: AudioMarkdownAnchor? = nil) throws -> AudioNote {
        guard Self.extensions.contains(source.pathExtension.lowercased()) else { throw AudioNoteError.invalidFile }
        let data = try Self.read(source, limit: Self.maximumBytes)
        let duration = try Self.duration(of: data)
        let note = AudioNote(id: UUID(), documentURL: documentURL.standardizedFileURL,
                             title: String(source.deletingPathExtension().lastPathComponent.prefix(120)), created: Date(),
                             audioExtension: source.pathExtension.lowercased(), duration: duration,
                             markers: [AudioPageMarker(seconds: 0, page: page, markdownAnchor: Self.isMarkdown(documentURL) ? (markdownAnchor ?? .documentStart) : nil)], incomplete: false)
        try checkCapacity()
        let destination = try audioURL(for: note)
        try data.write(to: destination, options: .withoutOverwriting)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            try save(note, creating: true)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return note
    }

    func trash(_ note: AudioNote) throws {
        try prepare()
        let audio = try audioURL(for: note)
        if FileManager.default.fileExists(atPath: audio.path) {
            try FileManager.default.trashItem(at: audio, resultingItemURL: nil)
        }
        try FileManager.default.trashItem(at: metadataURL(note.id), resultingItemURL: nil)
    }
}

@MainActor
final class AudioNotesController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = AudioNotesController()
    let store: AudioNoteStore
    @Published private(set) var notes: [AudioNote] = []
    @Published private(set) var recordingNote: AudioNote?
    @Published private(set) var pendingTabID: UUID?
    private(set) var recordingTabID: UUID?
    @Published private(set) var recordingSeconds: Double = 0
    @Published private(set) var playingID: UUID?
    private(set) var playbackTabID: UUID?
    @Published private(set) var playbackSeconds: Double = 0
    @Published private(set) var isPlaying = false
    @Published var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var requestID: UUID?
    private let permission: @Sendable () async -> Bool

    init(store: AudioNoteStore = AudioNoteStore(),
         permission: @escaping @Sendable () async -> Bool = {
             // A command-line Swift executable has no usage-description plist;
             // requesting protected hardware there can terminate the process.
             guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") is String else { return false }
             return await AVCaptureDevice.requestAccess(for: .audio)
         }) {
        self.store = store
        self.permission = permission
        super.init()
    }

    func refresh() {
        do { notes = try store.list() } catch { errorMessage = error.localizedDescription }
    }

    var isBusy: Bool { recordingNote != nil || pendingTabID != nil }

    func start(documentURL: URL, tabID: UUID, page: Int, title: String, markdownAnchor: AudioMarkdownAnchor? = nil) async {
        guard !isBusy else { return }
        errorMessage = nil
        guard AudioNoteStore.supportsDocument(documentURL), page > 0,
              markdownAnchor?.isValid != false else {
            errorMessage = AudioNoteError.invalidMetadata.localizedDescription
            return
        }
        let token = UUID()
        requestID = token
        pendingTabID = tabID
        let allowed = await permission()
        guard requestID == token, pendingTabID == tabID else { return }
        pendingTabID = nil
        requestID = nil
        guard allowed else { errorMessage = AudioNoteError.permission.localizedDescription; return }
        stopPlayback()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = AudioNote(id: UUID(), documentURL: documentURL.standardizedFileURL,
                             title: trimmed.isEmpty ? "Audio Note" : String(trimmed.prefix(120)), created: Date(),
                             audioExtension: "m4a", duration: 0,
                             markers: [AudioPageMarker(seconds: 0, page: page, markdownAnchor: AudioNoteStore.isMarkdown(documentURL) ? (markdownAnchor ?? .documentStart) : nil)], incomplete: true)
        do {
            try store.checkCapacity()
            let url = try store.audioURL(for: note)
            guard !FileManager.default.fileExists(atPath: url.path) else { throw AudioNoteError.unavailable }
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
            guard recorder.prepareToRecord() else { throw AudioNoteError.recording }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            // Keep a recovery record before microphone capture starts. Interrupted
            // audio stays local and is never silently deleted on the next launch.
            try store.save(note, creating: true)
            guard recorder.record(forDuration: AudioNoteStore.maximumDuration) else { throw AudioNoteError.recording }
            self.recorder = recorder
            recorder.delegate = self
            recordingNote = note
            recordingTabID = tabID
            recordingSeconds = 0
            startTimer()
            refresh()
        } catch {
            // A device/metadata failure may leave a partial audio file. Keep it
            // discoverable instead of deleting captured content or hiding it.
            if let url = try? store.audioURL(for: note), FileManager.default.fileExists(atPath: url.path),
               (try? store.list().contains(where: { $0.id == note.id })) != true {
                try? store.save(note, creating: true)
            }
            errorMessage = error.localizedDescription
            refresh()
        }
    }

    func addMarker(page: Int, documentURL: URL, markdownAnchor: AudioMarkdownAnchor? = nil) {
        guard var note = recordingNote, note.documentURL == documentURL.standardizedFileURL,
              note.markers.count < 500, page > 0 else { return }
        let marker = AudioPageMarker(seconds: min(AudioNoteStore.maximumDuration, recorder?.currentTime ?? recordingSeconds), page: page,
                                     markdownAnchor: AudioNoteStore.isMarkdown(documentURL) ? (markdownAnchor ?? .documentStart) : nil)
        note.markers.append(marker)
        do { try store.save(note); recordingNote = note; refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func stopRecording() {
        requestID = nil
        pendingTabID = nil
        guard var note = recordingNote else { return }
        recorder?.stop()
        recorder?.delegate = nil
        recorder = nil
        recordingNote = nil
        recordingTabID = nil
        timer?.invalidate()
        timer = nil
        do {
            note.duration = try AudioNoteStore.duration(of: store.data(for: note))
            note.incomplete = false
            try store.save(note)
        } catch {
            // Recovery metadata and audio remain available if finalization fails.
            errorMessage = "The recording is retained locally, but could not be finalized: " + error.localizedDescription
        }
        refresh()
    }

    func sourceClosed(tabID: UUID, documentURL: URL? = nil) {
        if recordingTabID == tabID || pendingTabID == tabID { stopRecording() }
        if playbackTabID == tabID || (playingID != nil && notes.first(where: { $0.id == playingID })?.documentURL == documentURL?.standardizedFileURL) {
            stopPlayback()
        }
    }

    func play(_ note: AudioNote, at seconds: Double = 0, tabID: UUID? = nil) {
        guard !isBusy else { return }
        errorMessage = nil
        stopPlayback()
        do {
            let data = try store.data(for: note)
            _ = try AudioNoteStore.duration(of: data)
            let player = try AVAudioPlayer(data: data)
            player.currentTime = min(max(0, seconds.isFinite ? seconds : 0), player.duration)
            guard player.play() else { throw AudioNoteError.invalidFile }
            self.player = player
            playingID = note.id
            playbackTabID = tabID
            isPlaying = true
            playbackSeconds = player.currentTime
            startTimer()
        } catch { errorMessage = error.localizedDescription }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingID = nil
        playbackTabID = nil
        isPlaying = false
        playbackSeconds = 0
        if recordingNote == nil { timer?.invalidate(); timer = nil }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false }
        else { isPlaying = player.play() }
    }

    func seek(to seconds: Double) {
        guard let player, seconds.isFinite else { return }
        player.currentTime = min(max(0, seconds), player.duration)
        playbackSeconds = player.currentTime
    }

    func addPlaybackMarker(page: Int, documentURL: URL, markdownAnchor: AudioMarkdownAnchor? = nil) {
        guard let playingID, var note = notes.first(where: { $0.id == playingID }),
              note.documentURL == documentURL.standardizedFileURL, page > 0, note.markers.count < 500 else { return }
        note.markers.append(AudioPageMarker(seconds: playbackSeconds, page: page,
                                           markdownAnchor: AudioNoteStore.isMarkdown(documentURL) ? (markdownAnchor ?? .documentStart) : nil))
        do { try store.save(note); refresh() } catch { errorMessage = error.localizedDescription }
    }

    func importAudio(_ url: URL, documentURL: URL, page: Int, markdownAnchor: AudioMarkdownAnchor? = nil) {
        errorMessage = nil
        do { _ = try store.importAudio(url, documentURL: documentURL, page: page, markdownAnchor: markdownAnchor); refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func trash(_ note: AudioNote) {
        guard recordingNote?.id != note.id else { return }
        if playingID == note.id { stopPlayback() }
        do { try store.trash(note); refresh() } catch { errorMessage = error.localizedDescription; refresh() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let recorder = self.recorder {
                    if !recorder.isRecording { self.stopRecording(); return }
                    self.recordingSeconds = recorder.currentTime
                    if let note = self.recordingNote,
                       let url = try? self.store.audioURL(for: note),
                       let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                       ((attributes[.size] as? NSNumber)?.intValue ?? 0) >= AudioNoteStore.maximumBytes {
                        self.stopRecording()
                    }
                } else if let player = self.player {
                    self.playbackSeconds = player.currentTime
                    if self.isPlaying && !player.isPlaying { self.stopPlayback() }
                }
            }
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let id = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == id else { return }
            if !flag { self.errorMessage = "Recording stopped unexpectedly. The local recording will be retained." }
            self.stopRecording()
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let id = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == id else { return }
            self.errorMessage = "Recording encountered an audio encoding error. The local recording will be retained."
            self.stopRecording()
        }
    }

    static func timeLabel(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(max(0, seconds), AudioNoteStore.maximumDuration)) : 0
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
