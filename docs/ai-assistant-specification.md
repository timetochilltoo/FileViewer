# FileViewer AI Assistant Panel Specification

Status: Phase 1 implemented on `feature/ai-assistant`; configurable provider profiles implemented (LM Studio, Ollama, OpenAI-compatible servers, and OpenAI)

## Implementation Note — 2026-07-11

The first functional vertical slice is implemented on the separate branch `feature/ai-assistant`:

- a toolbar sparkle button opens a resizable 280–600 point right panel;
- the panel header's gear button opens **AI Provider Settings**, where the user adds, edits, removes, and selects provider profiles;
- conversations are in memory and isolated by document tab;
- provider profiles are persisted locally, with LM Studio (`http://127.0.0.1:1234/v1`) as the safe default;
- the built-in profile choices are LM Studio, Ollama (`http://127.0.0.1:11434/v1`), a custom OpenAI-compatible server, and OpenAI (`https://api.openai.com/v1`);
- chat responses stream through the OpenAI-compatible `/v1/chat/completions` endpoint, including the OpenAI profile's supported Chat Completions endpoint;
- every provider exposes model discovery through `GET /v1/models` (or its configured equivalent endpoint);
- local loopback endpoints may be used immediately; a non-loopback endpoint is blocked until the user enables **Allow this provider to receive document text** in AI Provider Settings;
- OpenAI requires an API key; custom-compatible profiles may optionally use one. Saved provider credentials are stored only in macOS Keychain, never in UserDefaults, exported data, source code, or logs;
- opening AI Provider Settings does not inspect or reveal saved Keychain credentials. A saved key is read only when the active provider needs it for a connection or request; leaving the key field blank preserves any existing saved key;
- PDF text selection and its page number are captured from PDFKit;
- Markdown source/preview selection is read from the active or most recently active text view;
- Selected Text, Current Page/Section, Relevant Sections, and Whole Document scopes are implemented;
- PDF pages and Markdown headings are used as context labels;
- question, summary, translation, cancellation, errors, basic Markdown response rendering, and model selection are implemented;
- normal questions and summaries have an independent `Answer in` selector (English, Traditional Chinese, or Simplified Chinese); translation has its own three-language `Translate to` selector;
- the request transcript accurately names the selected scope, for example `Translate the selected text into Traditional Chinese` rather than implying the whole document is translated;
- `Relevant Sections` is intended for question answering. If it is selected when Translate is pressed, the app changes the effective scope to Current Page/Section, because translation prompts have no meaningful search terms and must not retrieve unrelated pages;
- summaries and translations use only the current request context; only a normal question carries the preceding conversation turns;
- the chat composer uses Return to send and Shift-Return to insert a line break, with the shortcut displayed under the editor;
- the manager depends on an `AIProvider` protocol and a common Chat-Completions transport, so compatible providers use the same document-context safeguards;
- automated tests cover context chunking, selection isolation, basic retrieval, local-endpoint enforcement in the legacy LM Studio adapter, and provider-profile defaults.

This is intentionally not the complete specification. Remaining work includes clickable citations, selection context-menu commands, hierarchical summaries for very large documents, persisted conversations, a mock streaming-provider test, accessibility review, and narrow-window overlay behavior. Context is capped at 12,000 characters and reports when it is truncated; Whole Document is therefore a preview, not yet a complete-document synthesis. The request also reserves 1,024 output tokens. No document text is sent until the user presses Send, Summarize, or Translate.

This document defines a provider-neutral AI assistant for FileViewer. It describes the user experience, document-context rules, privacy and security controls, internal interfaces, failure handling, and acceptance criteria. The active provider and model are selected at runtime; no provider credential is bundled with FileViewer.

## 1. Purpose

The AI assistant should help the user understand the document currently open in FileViewer without replacing normal reading, search, annotation, or editing workflows.

The first version should support:

- asking questions about the current document;
- summarizing the whole document, the current page/section, or selected text;
- translating the whole document, the current page/section, or selected text;
- selecting text in a PDF or Markdown document and using it as focused AI context;
- showing where an answer came from through PDF page or Markdown heading citations;
- copying the result without modifying the original document automatically.

“Translation” is used throughout this specification. If the earlier request used the word “transaction,” it is interpreted as translation.

## 2. Product Principles

- The document remains the main interface. AI appears in a right-side panel and does not cover the document.
- Local-first and private-by-default behavior is preferred.
- The user must know what content will be sent to an external provider before it is sent.
- AI output is assistance, not authoritative document content.
- Answers should be grounded in the open document and include citations whenever possible.
- The assistant must say when the requested information is not present in the document.
- AI actions must not silently edit, save, annotate, delete, or overwrite files.
- Provider-specific behavior must be isolated behind a common interface.

## 3. Right Panel Layout

### 3.1 Opening and Closing

- Add one `AI Assistant` button to the main toolbar, preferably near Search.
- The button uses a familiar symbol and a visible tooltip.
- Clicking it opens or closes a right-side panel belonging to the current FileViewer window.
- Suggested default width: 360 points.
- Suggested resizable range: 300–600 points.
- The panel width should be remembered per window or as an app preference.
- Opening the panel must not hide the left sidebar. The center document area should resize between the two panels.
- At narrow window widths, the AI panel may appear as an overlay sheet or temporarily hide the left sidebar, but this behavior must be predictable and reversible.

### 3.2 Panel Header

The header should show:

- `AI Assistant`;
- the current document name;
- a context scope control;
- a new-conversation button;
- a panel close button.

### 3.3 Primary Actions

Show three prominent actions when a conversation is empty:

- `Summarize`
- `Translate`
- `Ask a Question`

These actions may become compact buttons after the first response.

### 3.4 Conversation Area

The conversation area should show:

- user questions;
- AI responses rendered with basic Markdown;
- streaming progress while the response is generated; provider-private reasoning wrapped in `<think>…</think>` is filtered before rendering, copying, exporting, or passing conversation history into a follow-up request;
- a **Sources provided to the model** strip on every completed response. It lists the exact page or Markdown-heading chunks included in that individual request; PDF page chips are clickable and navigate to the corresponding page. This is provenance, not a claim that the model necessarily cited every chip in its prose;
- a **Save Conversation** command that writes the current in-memory conversation to a Markdown file, including source/model metadata and the source chunks provided to each answer. Conversations remain memory-only unless the user explicitly exports one;
- citations as clickable chips or links;
- Copy each completed response as Markdown and save it as a standalone Markdown note;
- a clear error message when a request fails;
- a Stop button during generation.

### 3.5 Input Area

The bottom input area should contain:

- a multi-line question field;
- a Send button;
- the active context scope;
- a short disclosure such as `Selected text will be sent to <provider>` or `Processed on this Mac`;
- an optional language selector when translation mode is active.

Phase 1 uses normal chat behaviour: Return sends the request and Shift-Return inserts a new line. The composer displays this shortcut. Command-Return also sends because it is treated as Return without Shift.

Before an AI action, the configuration area identifies whether the selected endpoint is local to this Mac or a remote provider and names the remote host. Whole Document also warns that the present implementation uses a 12,000-character preview and may be truncated; it is not a complete-document synthesis.

## 4. Context Scope

The assistant must never guess silently which portion of a document the user intended. Every request has an explicit scope.

Supported scopes:

1. `Selected Text`
2. `Current Page` for PDF or `Current Section` for Markdown
3. `Whole Document`
4. `Relevant Sections` for document question answering

### 4.1 Automatic Scope Selection

- If the user has a non-empty text selection, default to `Selected Text`.
- Otherwise, Summarize defaults to `Current Page/Section`.
- Ask defaults to `Relevant Sections` when document indexing is available.
- Translate defaults to `Selected Text` when text is selected, otherwise `Current Page/Section`.
- The user can change the scope before sending.

### 4.2 Selection Capture

For PDF:

- capture text from `PDFView.currentSelection`;
- retain page number and selection bounds for citation and navigation;
- multi-page selections should preserve page boundaries;
- if the PDF contains no selectable text, explain that the page may be scanned and that OCR is not yet available, unless OCR is implemented later.

For Markdown:

- use the selected source or preview text;
- retain the source range and nearest heading;
- preserve enough Markdown structure to understand lists, tables, and headings;
- the selected range should remain stable even after the user clicks the AI panel.

### 4.3 Selection Action

When text is selected, offer a small contextual action or right-click menu:

- `Ask AI About Selection…`
- `Summarize Selection`
- `Translate Selection…`

Choosing one opens the right panel and displays a preview of the captured selection before sending. It must not send immediately unless the user has explicitly enabled a future `Send immediately` preference.

## 5. Summarization

### 5.1 Summary Types

The Summarize action should offer:

- Brief summary
- Detailed summary
- Key points
- Action items
- Section-by-section summary

MVP requires Brief summary, Detailed summary, and Key points.

### 5.2 Whole-Document Summary

Large documents cannot always be sent as one request. FileViewer should:

1. extract document text locally;
2. divide it into page/heading-aware chunks;
3. summarize chunks when required;
4. combine them into a final summary;
5. retain citations to source pages/headings.

The UI should show progress such as `Reading page 12 of 85` and allow cancellation.

## 6. Translation

### 6.1 Supported Flow

- The user selects a target language.
- The source language defaults to automatic detection.
- The result should preserve paragraphs, headings, lists, and simple tables where practical.
- Translation output appears in the AI panel.
- Every completed assistant response offers **Copy Answer**, **Copy as Markdown**, and **Save as Markdown**. **Copy Answer** converts the response to readable plain text before copying it, removing Markdown formatting syntax. The Markdown actions preserve the raw response Markdown and add source document, selected context, model, and generated-time provenance. Saving can target an Obsidian vault directly. Creating a new unsaved Markdown document from the response remains future work.
- The original document is not modified.

### 6.2 Initial Languages

The UI should not hardcode a provider's exact language list. It should initially expose commonly used choices such as:

- English
- Traditional Chinese
- Simplified Chinese
- Japanese
- Korean

The provider adapter may report additional supported languages later.

## 7. Document Question Answering

### 7.1 Grounded Answers

Questions about the document should use retrieved document excerpts rather than sending the whole document by default.

The assistant should:

1. extract and chunk text locally;
2. identify relevant chunks;
3. send only those chunks with the question;
4. answer using those chunks;
5. cite each material claim with a PDF page or Markdown heading;
6. state `I could not find that in this document` when evidence is insufficient.

### 7.2 Citations

- PDF citation example: `Page 17`
- Markdown citation example: `Heading: Security Controls`
- Clicking a citation navigates the document to that page, heading, or selection.
- Citations should refer to the document displayed to the user, not internal chunk numbers.

### 7.3 Conversation Context

- Follow-up questions may reference earlier questions and answers.
- Document evidence should be retrieved again when necessary rather than relying entirely on chat history.
- Conversations belong to a document session, not globally to every window.
- Switching tabs switches the visible AI conversation to that tab's conversation.
- Closing a document clears its in-memory conversation unless conversation persistence is explicitly enabled later.

## 8. Provider-Neutral Architecture

Provider selection can be deferred, but it is not only a base-URL configuration detail. Providers may differ in authentication, request fields, streaming format, context limits, rate limits, safety behavior, privacy terms, tool support, and error responses.

FileViewer should define a common internal protocol similar to:

```swift
protocol AIProvider {
    var identifier: String { get }
    var displayName: String { get }
    var capabilities: AICapabilities { get }

    func streamResponse(
        request: AIRequest
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

Core request model:

```swift
struct AIRequest {
    let task: AITask
    let userPrompt: String
    let context: [DocumentContextChunk]
    let targetLanguage: String?
    let conversation: [AIMessage]
}
```

Required abstraction layers:

- `AIProvider`: provider/model communication;
- `AIAssistantService`: prompt construction and response orchestration;
- `DocumentContextExtractor`: PDF/Markdown text and selection extraction;
- `DocumentChunker`: page/heading-aware chunks;
- `DocumentRetriever`: selects relevant chunks for questions;
- `AIConversationStore`: in-memory, per-tab conversations;
- `AICredentialStore`: Keychain storage for API credentials;
- `AIAssistantPanel`: SwiftUI presentation.

Providers that offer a sufficiently compatible API may share an OpenAI-compatible transport implementation, with small provider adapters for authentication and response differences. An on-device Apple implementation would use a separate adapter but expose the same `AIProvider` interface.

## 9. Provider Settings

Add a Settings window before enabling cloud AI.

Suggested fields:

- Provider
- Model
- API base URL, when applicable
- API key entry
- Test Connection button
- Default processing mode: On-device or Cloud
- Default translation language
- Allow whole-document cloud requests
- Save conversation history

API keys must be stored in macOS Keychain. They must not be stored in UserDefaults, session JSON, logs, source code, or the app bundle.

## 10. Privacy and Security

### 10.1 Consent

Before the first cloud request, require the user to enable the profile's **Allow this provider to receive document text** control in AI Provider Settings. The setting makes the following clear:

- which provider receives the content;
- that selected document text may leave the Mac;
- that provider privacy and retention terms apply;
- that confidential or regulated documents should only be sent when authorized.

### 10.2 Per-Request Disclosure

Every cloud request should show its scope before sending:

- selected text;
- current page/section;
- relevant excerpts;
- whole document.

Whole-document cloud requests are subject to the same per-provider remote-access approval. The current implementation caps and labels this scope as a preview; a separate per-request whole-document confirmation remains future work.

### 10.3 Prompt Injection

Document text is untrusted data. System instructions must state that content inside the document is reference material and must not override application instructions.

The initial AI assistant must not receive tools capable of:

- saving or overwriting files;
- deleting files;
- changing annotations;
- executing shell commands;
- accessing unrelated documents;
- reading folders outside the selected document context.

### 10.4 Logging

- Do not log API keys.
- Do not log full document text or full prompts by default.
- Store saved API keys only in the macOS Keychain, keyed to the individual provider profile. Provider names, endpoints, selected model, and the remote-access approval may be stored in UserDefaults; credentials may not.
- Diagnostic logs may record provider identifier, model, duration, response status, token counts when available, and an anonymous request ID.
- Exported diagnostics must redact credentials and document content.

## 11. Local Document Processing

### 11.1 PDF

- Extract text page by page using PDFKit.
- Preserve page numbers in every chunk.
- Use PDF outline titles as optional section metadata.
- Exclude annotations from source text unless the user enables `Include annotations`.
- Treat fillable form values as sensitive and exclude them by default from cloud context.

### 11.2 Markdown

- Parse by headings and block boundaries.
- Preserve heading hierarchy.
- Keep code blocks intact where possible.
- Avoid splitting tables in the middle where possible.
- Preserve source ranges for navigation.

### 11.3 Chunk Cache

- Cache extracted/chunked text per document version to avoid repeated processing.
- Invalidate the cache when the document changes on disk, Markdown is edited, PDF form data changes, or annotations are included and modified.
- Keep cache data in memory for MVP.
- If disk caching is introduced later, make it optional, app-scoped, and removable from Settings.

## 12. Responsiveness and Resource Limits

- Text extraction, chunking, retrieval, and network work must not block the main thread.
- Requests must support cancellation.
- Only one active generation per document tab is required for MVP.
- Switching tabs should not cancel another tab's request unless the document closes.
- Apply configurable maximum input sizes.
- Show a useful explanation when the selected provider cannot accept the requested scope.
- Large-document progress must be visible.

## 13. Error Handling

User-facing errors should distinguish:

- missing API key;
- authentication failure;
- provider unavailable;
- rate limit;
- network failure;
- request too large;
- unsupported language;
- no selectable/extractable document text;
- response cancelled;
- malformed provider response.

Errors must not discard the user's question. The input remains available for retry or provider change.

## 14. Accessibility and Keyboard Support

- All controls need VoiceOver labels.
- AI output must be selectable and readable by VoiceOver.
- Keyboard focus should move predictably between the document, panel, and question field.
- Command-Return sends.
- Escape stops generation when a request is active; otherwise it returns focus to the document.
- Citations must be keyboard accessible.
- Active context and cloud/on-device status must not rely on color alone.

## 15. Persistence

MVP:

- remember whether the panel is open per window;
- remember panel width;
- keep conversations only in memory;
- store provider settings in UserDefaults except credentials;
- store credentials in Keychain.

Future optional persistence:

- local conversation history per document;
- export conversation to Markdown;
- clear one document's history;
- clear all AI history and caches.

Unsaved document text and conversations must not be restored silently after a crash unless explicit recovery support is implemented.

## 16. MVP Scope

### Included

- right-side resizable panel;
- selected-text capture for PDF and Markdown;
- current page/section scope;
- whole-document summary with chunking;
- brief/detailed/key-points summary;
- translation with target-language selection;
- grounded document questions;
- page/heading citations and navigation;
- streaming, cancellation, copy, and retry;
- provider settings and Keychain credentials;
- one provider adapter plus a mock provider for tests.

### Deferred

- OCR for scanned PDFs;
- image understanding;
- voice input/output;
- automatic document editing;
- automatic annotation creation;
- multi-document questions;
- internet search;
- persistent chat synchronization;
- provider comparison or automatic model routing;
- agentic file operations.

## 17. Suggested Implementation Phases

### Phase 1: Panel and Mock Provider

- Build the right panel and per-tab conversation state.
- Implement context scope UI and selected-text capture.
- Use a deterministic mock provider so UI and tests do not require a network or API key.

### Phase 2: Local Extraction and Citations

- Implement PDF/Markdown extractors, chunking, retrieval, and citation navigation.
- Add progress and cancellation.

### Phase 3: First Real Provider

- Add Settings and Keychain storage.
- Implement one provider adapter.
- Add streaming, provider errors, and privacy confirmation.

### Phase 4: Additional Providers

- Add adapters or configurations for other providers.
- Add capability checks and provider-specific model settings.
- Benchmark quality using representative English and Traditional Chinese documents.

## 18. Acceptance Criteria

1. Opening the AI panel does not cover the current document at normal window sizes.
2. Each window and document tab has independent AI state.
3. Selecting PDF or Markdown text and choosing `Ask AI About Selection` captures the intended text before focus moves to the panel.
4. The panel clearly displays whether context is selected text, current page/section, relevant excerpts, or whole document.
5. No cloud request is sent before provider configuration and first-use consent.
6. API keys are stored only in Keychain.
7. Summary and translation do not modify the source document.
8. Document questions provide clickable page or heading citations.
9. The assistant admits when evidence is not present.
10. Large-document processing remains responsive and can be cancelled.
11. Closing a document cancels its active request and releases its context/conversation memory.
12. Switching windows does not send commands or responses to another window.
13. Unit tests can run without a real AI account through a mock provider.
14. Logs and exported diagnostics contain no API keys or full document text.

## 19. Provider Decision

The provider can be chosen later because the product UI, context extraction, chunking, citations, and conversation model should be provider-independent.

However, changing providers is not guaranteed to be only a configuration change. If two providers expose compatible request and streaming formats, they can share one transport with different base URL, model, and credential settings. Providers with different authentication, streaming, limits, or on-device APIs require a small adapter. The architecture above keeps that difference contained so it does not affect the rest of FileViewer.
