# FileViewer

FileViewer is a local-first native macOS Markdown and PDF viewer/editor built with SwiftUI.

Current MVP build includes:

- Open Markdown and PDF files.
- New unsaved Markdown documents.
- Open multiple Markdown/PDF documents in tabs or separate windows. A file already open in FileViewer is brought forward instead of creating a second writable copy.
- Separate document windows identify themselves as `<filename> — FileViewer` in the title bar and Window menu, so multiple FileViewer windows are distinguishable in the Dock and app switcher.
- Restore previously open file-backed tabs/windows after app restart.
- Restore session window size/position when possible.
- Restore PDF page/zoom and Markdown Source/Preview scroll position for reopened files.
- Markdown windows can be resized narrow enough for two documents side-by-side.
- Drag-and-drop file opening, including multiple dropped files.
- macOS Open With / external file-open handling for PDF, Markdown, and text files. Finder-opened documents use separate windows so existing windows do not all switch to the newest document.
- Markdown source view.
- Markdown rendered preview.
- Select text in Markdown preview and use formatting buttons to update the Markdown source.
- Structured Markdown preview for headings, lists, quotes, code blocks, basic tables, task lists, and underline convenience.
- Markdown split view.
- Markdown editing.
- Markdown save and save-as.
- Unsaved Markdown close confirmation for tabs and windows.
- Markdown search current/total count, previous/next navigation, and highlighting in both Preview and Source modes. Source mode highlights raw Markdown text without changing the document.
- Beginner-friendly Markdown formatting controls through a visible Format dropdown, icon buttons, source-editor right-click actions, and menu commands for common syntax:
  - bold
  - italic
  - underline
  - heading
  - bullet list
  - numbered list
  - quote
  - link insertion
  - inline code / code block
  - table insertion
  - task list insertion/conversion
- Help menu Markdown syntax guide.
- PDF rendering.
- PDF page navigation.
- PDF first/last page controls.
- PDF zoom controls.
- PDF thumbnails.
- PDF outline/table-of-contents sidebar when the PDF provides one.
- PDF search highlighting with current/total count and previous/next navigation.
- Stable fixed-width sidebar with custom sidebar tabs. A single compact `sidebar.left` toggle sits at the leading edge of the document toolbar and remains available whether the sidebar is shown or hidden.
- Sidebar launch preference in **FileViewer > Settings…**: Show Sidebar, Hide Sidebar, or Remember Last State. The setting applies to the next launch and newly-created document windows.
- PDF annotation and fillable-form support:
  - highlight selected PDF text
  - underline selected PDF text
  - strike through selected PDF text
  - choose the color used for newly-created PDF annotations
  - choose Thin, Medium, or Thick stroke width for new shapes, lines, arrows, and freehand ink
  - recolor existing PDF annotations
  - remove highlight/underline/strikeout markup from selected PDF text
  - add sticky note comments to the current PDF page
  - sticky notes use the standard PDF note icon and a larger Move/Edit/Delete hit target
  - add visible text box annotations
  - add rectangle, oval, line, and arrow shape annotations
  - draw freehand ink annotations
  - move sticky note icons and text boxes with Move Annotation mode
  - resize text boxes with Move Annotation mode
  - resize rectangle and oval annotations with Move Annotation mode
  - show resize/endpoint handles while Move Annotation mode is on
  - edit sticky note and text box text with Edit Annotation mode
  - delete sticky notes and text boxes with Delete Annotation mode
  - undo/redo recent PDF annotation changes
  - browse PDF annotations from the sidebar `Notes` tab and jump back to the selected annotation
  - filter the `Notes` sidebar by annotation type
  - export a Markdown annotation summary report
  - detect fillable PDF form edits; normal Save is available whenever a PDF is open so macOS menu-refresh timing cannot block saving a form
  - save embedded PDF annotations and fillable-form changes back to the PDF file
  - save an annotated PDF copy with Save Annotated Copy As / Command-Shift-S
  - rotate the reading view left, right, or 180° without modifying the PDF file
  - permanently rotate the current page or every page left, right, or 180°; the change is written only when the PDF is saved
  - warn before closing a PDF tab/window with unsaved PDF changes
  - confirm unsaved documents before Command-Q, block overwriting files changed outside FileViewer, and write PDF saves through a verified temporary file before replacing the original
  - keep PDF controls compact with navigation/search/Undo/Redo in the toolbar and fixed-size icon-only `Annotate` and `Rotate` menus for markup, notes, shapes, drawing, edit modes, color, stroke width, and page rotation; PDF icon-only actions use a plain 32×28 hit target and borderless menus so the default macOS grey button capsules do not make the PDF controls look oversized beside the Markdown toolbar; fixed control widths prevent adjacent controls from visually overlapping
- File-management actions are intentionally kept in menus/shortcuts instead of the crowded toolbar:
  - New Markdown Document
  - Save / Command-S
  - Save As / Command-Shift-S
  - Print / Command-P
- Print support for PDFs and Markdown source text.
- Recent files.
- Light and dark theme.
- Local AI assistant (feature branch `feature/ai-assistant`):
  - resizable right-side panel with per-document conversations
  - ask, summarize, and translate PDF or Markdown content
  - explicit Selected Text, Current Page/Section, Relevant Sections, and Whole Document scopes
  - PDF page and Markdown heading context labels for grounded answers
  - streaming responses, Stop, model discovery, and connection status
  - persisted provider profiles for local LM Studio and Ollama, custom OpenAI-compatible servers, and OpenAI
  - local endpoints work immediately; remote profiles require explicit approval before document text is sent, and API keys are kept in macOS Keychain

## Run Locally

The primary app is now a native SwiftUI macOS app targeting macOS Tahoe 26.5.1 / macOS 26.

```bash
swift run FileViewer
```

You can also open the package in Xcode:

```text
Package.swift
```

The earlier React/Vite prototype remains in the folder for reference, but SwiftUI is the official implementation direction.

## Automated Tests

The Swift package includes an XCTest target for fast safety and document-model checks. Run it with:

```bash
swift test
```

The suite verifies Markdown dirty-state behavior, file-version change detection, duplicate-open protection, Markdown file recognition, AI context chunking/retrieval, selected-text isolation, local-only legacy transport enforcement, and safe provider-profile defaults. PDFKit drawing and native window dialogs remain manual/UI-test work for now.

## Packaged App

The current development app bundle is here:

```text
build/FileViewer 0.1.1.app
```

It is built from the Swift executable and signed locally with an ad-hoc development signature. The package script defaults to a native Debug build; pass `release` when a Release bundle is needed.

To rebuild the app bundle:

```bash
bash scripts/package_app.sh
# or: bash scripts/package_app.sh release
```

## Documentation

- Requirements and specification: `docs/requirements-and-specification.md`
- AI assistant panel specification: `docs/ai-assistant-specification.md`
- MVP task list: `docs/mvp-task-list.md`
- Continuation handoff and implementation inventory: `HANDOFF.md`
