import SwiftUI

struct PDFOCRView: View {
    @ObservedObject var model: AppModel
    let job: PDFOCRJob
    @State private var completed = 0
    @State private var result: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recognize PDF Text").font(.title2.bold())
            Text(job.name).lineLimit(2)
            Text("Recognition runs on this Mac. Your PDF stays unchanged. Results open in a temporary Markdown tab; save it if you want to keep it.")
                .foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red)
            } else if result != nil {
                Text("Recognized \(completed) \(completed == 1 ? "page" : "pages"). Review the text against the original PDF.")
            } else {
                ProgressView(value: Double(completed), total: Double(job.pages.count))
                Text("Page \(min(completed + 1, job.pages.count)) of \(job.pages.count)")
            }
            HStack {
                Spacer()
                Button(result == nil && error == nil ? "Cancel" : "Close") { model.pdfOCRJob = nil }
                    .keyboardShortcut(.cancelAction)
                if let result {
                    Button("Open as Markdown") {
                        guard model.pdfOCRJob?.id == job.id,
                              model.tabs.contains(where: { $0.id == job.tabID }) else { return }
                        model.pdfOCRJob = nil
                        model.openTemporaryMarkdownDocument(name: job.name + " OCR.md", text: result)
                        model.statusMessage = "Opened locally recognized PDF text."
                    }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24).frame(width: 480)
        .task {
            let worker = Task.detached(priority: .userInitiated) {
                try await PDFOCR.recognize(data: job.data, pages: job.pages, name: job.name) { count in
                    await MainActor.run { completed = count }
                }
            }
            do {
                let text = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard model.pdfOCRJob?.id == job.id else { return }
                result = text
            } catch is CancellationError {
                // Dismissal/close cancels the worker; never open a late result.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
