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
}
