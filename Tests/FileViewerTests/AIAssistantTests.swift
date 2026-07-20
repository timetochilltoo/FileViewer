import Foundation
import XCTest
@testable import FileViewer

final class AIAssistantTests: XCTestCase {
    func testMarkdownChunksUseHeadingLabels() {
        let chunks = AIContextBuilder.markdownChunks("""
        Intro text.

        # Security
        Keep data local.

        ## Privacy
        Do not upload documents.
        """)

        XCTAssertEqual(chunks.map(\.label), [
            "Heading: Document start",
            "Heading: Security",
            "Heading: Privacy"
        ])
        XCTAssertTrue(chunks[1].text.contains("Keep data local"))
    }

    func testSelectedMarkdownContextContainsOnlySelection() {
        let markdown = MarkdownDocument(
            url: nil,
            untitledName: "Test.md",
            text: "# One\nFirst section\n# Two\nSecond section",
            savedText: "# One\nFirst section\n# Two\nSecond section"
        )
        let document = ViewerDocument.markdown(markdown)
        let tab = DocumentTab(document: document)

        let payload = AIContextBuilder.build(
            document: document,
            tab: tab,
            markdownSelection: "First section",
            scope: .selectedText,
            question: "Explain this"
        )

        XCTAssertTrue(payload.text.contains("First section"))
        XCTAssertFalse(payload.text.contains("Second section"))
        XCTAssertEqual(payload.description, "Selected text")
        XCTAssertEqual(payload.sourceLabels, ["Selected Markdown text"])
    }

    func testRelevantContextPrefersMatchingSection() {
        let markdown = MarkdownDocument(
            url: nil,
            untitledName: "Test.md",
            text: "# Apples\nFruit notes\n# Security\nEncryption and access controls",
            savedText: "# Apples\nFruit notes\n# Security\nEncryption and access controls"
        )
        let document = ViewerDocument.markdown(markdown)
        let payload = AIContextBuilder.build(
            document: document,
            tab: DocumentTab(document: document),
            markdownSelection: "",
            scope: .relevantSections,
            question: "What encryption controls are described?"
        )

        XCTAssertTrue(payload.text.contains("Heading: Security"))
        XCTAssertTrue(payload.text.contains("Encryption and access controls"))
    }

    func testWholeDocumentUsesSafePreviewLimit() {
        let source = String(repeating: "A", count: 13_000)
        let markdown = MarkdownDocument(
            url: nil,
            untitledName: "Long.md",
            text: source,
            savedText: source
        )
        let document = ViewerDocument.markdown(markdown)
        let payload = AIContextBuilder.build(
            document: document,
            tab: DocumentTab(document: document),
            markdownSelection: "",
            scope: .wholeDocument,
            question: "Summarize this document"
        )

        XCTAssertLessThanOrEqual(payload.text.count, 12_000)
        XCTAssertTrue(payload.wasTruncated)
        XCTAssertEqual(payload.description, "Whole document preview")
        XCTAssertFalse(payload.sourceLabels.isEmpty)
    }

    func testMarkdownExportPreservesResponseAndProvenance() {
        let output = AIResponseMarkdownExport.make(
            response: "## Summary\n\n- Keep this Markdown.",
            sourceName: "Governance.pdf",
            contextDescription: "Page 7",
            modelName: "local-model",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(output.contains("**Source:** `Governance.pdf`"))
        XCTAssertTrue(output.contains("**Context:** Page 7"))
        XCTAssertTrue(output.contains("**Model:** local-model"))
        XCTAssertTrue(output.contains("## Summary\n\n- Keep this Markdown."))
        XCTAssertTrue(output.contains("1970-01-01T00:00:00Z"))
    }

    func testConversationExportIncludesMessagesAndPerAnswerSources() {
        let output = AIConversationMarkdownExport.make(
            messages: [
                AIMessage(role: .user, content: "What does this mean?"),
                AIMessage(role: .assistant, content: "It means testing is required.", sourceLabels: ["Page 9", "Page 3", "Page 8"])
            ],
            sourceName: "Guidance.pdf",
            modelName: "local-model",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(output.contains("## You"))
        XCTAssertTrue(output.contains("## Assistant"))
        XCTAssertTrue(output.contains("`Page 3`, `Page 8`, `Page 9`"))
        XCTAssertTrue(output.contains("1970-01-01T00:00:00Z"))
    }

    func testMarkdownSourceLabelsPreserveRelevanceOrder() {
        XCTAssertEqual(
            AISourceProvenance.orderedLabels(["Heading: Security", "Heading: Introduction"]),
            ["Heading: Security", "Heading: Introduction"]
        )
    }

    func testPlainTextExportRemovesMarkdownFormatting() {
        let output = AIResponsePlainTextExport.make(
            response: "## **Heading**\n\n<u>Underlined</u> and `code`."
        )

        XCTAssertEqual(output, "Heading\n\nUnderlined and code.")
    }

    func testLMStudioClientRejectsRemoteHosts() async {
        let client = LMStudioClient(baseURL: URL(string: "https://example.com/v1")!)
        do {
            _ = try await client.listModels()
            XCTFail("A remote AI server should be rejected in local-only mode.")
        } catch let error as LMStudioError {
            guard case .invalidLocalServer = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProviderProfilesUseExpectedSafeDefaults() {
        let lmStudio = AIProviderProfile(name: "LM Studio", kind: .lmStudio)
        let ollama = AIProviderProfile(name: "Ollama", kind: .ollama)
        let openAI = AIProviderProfile(name: "OpenAI", kind: .openAI)

        XCTAssertEqual(lmStudio.endpoint, "http://127.0.0.1:1234/v1")
        XCTAssertFalse(lmStudio.allowRemoteAccess)
        XCTAssertEqual(ollama.endpoint, "http://127.0.0.1:11434/v1")
        XCTAssertFalse(ollama.allowRemoteAccess)
        XCTAssertEqual(openAI.endpoint, "https://api.openai.com/v1")
        XCTAssertFalse(openAI.allowRemoteAccess)
    }

    func testOnlyOpenAIProfileRequiresAnAPIKeyByDefault() {
        XCTAssertTrue(AIProviderKind.openAI.needsAPIKey)
        XCTAssertFalse(AIProviderKind.lmStudio.needsAPIKey)
        XCTAssertFalse(AIProviderKind.ollama.needsAPIKey)
        XCTAssertFalse(AIProviderKind.openAICompatible.needsAPIKey)
    }

    func testAIReasoningTagsAreNotShownInDisplayableResponse() {
        XCTAssertEqual(
            AIAssistantManager.displayableResponse(
                from: "<think>Private reasoning that must not be displayed.</think>\n\n## Final answer\nVisible text."
            ),
            "## Final answer\nVisible text."
        )
        XCTAssertEqual(
            AIAssistantManager.displayableResponse(from: "Answer first <think>still streaming"),
            "Answer first"
        )
    }
}
