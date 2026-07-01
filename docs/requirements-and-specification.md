# FileViewer Requirements and Specification

## 1. Product Overview

FileViewer is a local-first native macOS document viewing application focused on Markdown and PDF files. The app should let users open, read, edit Markdown, search, navigate, and organize documents with a clean SwiftUI interface. It should support practical PDF editing through annotations and page operations in later versions, while treating full PDF content editing as an advanced future feature.

The app targets macOS Tahoe 26.5.1 and newer within the macOS 26 generation. Compatibility with lower macOS versions is not required.

The first version should feel like a useful everyday viewer, not a demo. Users should be able to drag in a file, immediately read it, search it, adjust the view, and continue later from where they left off.

## 2. Primary Goals

- Provide a fast, reliable Markdown viewer.
- Provide a PDF viewer with navigation, zoom, thumbnails, and search.
- Support common document workflows such as recent files, tabs, separate side-by-side windows, Finder/Open With file opening, and drag-and-drop opening.
- Keep files local unless the user explicitly chooses an export or sharing action.
- Support useful PDF annotations without pretending PDFs are as easy to edit as Word documents.
- Build the app in a way that can later grow into a full desktop document workspace.
- Use SwiftUI as the primary UI framework.
- Use native macOS document and file APIs wherever practical.

## 3. Target Users

- Students reading notes, PDFs, research material, and Markdown study documents.
- Developers reading technical Markdown and PDF documentation.
- Office users reviewing contracts, reports, forms, and exported PDFs.
- Personal knowledge workers who want a simple local document viewer.

## 4. Supported File Types

### 4.1 Required for MVP

- Markdown: `.md`, `.markdown`
- PDF: `.pdf`

### 4.2 Future Supported Types

- Plain text: `.txt`
- Rich text: `.rtf`
- Images: `.png`, `.jpg`, `.jpeg`, `.webp`
- Office documents through conversion or preview: `.docx`, `.pptx`, `.xlsx`

## 5. Core User Workflows

### 5.1 Open Documents

The user can open a document by:

- Clicking an open-file button.
- Dragging and dropping a file into the app.
- Selecting a recent file.
- Opening a file from the operating system, if packaged as a desktop app.

Expected behavior:

- The app detects file type automatically.
- Unsupported file types show a clear message.
- Opening multiple supported files inside one app window keeps them available as tabs.
- Opening files from Finder / Open With uses separate windows when existing windows already contain documents, so comparing two Markdown/PDF files side-by-side is practical.
- Opening document A from Finder, then document B from Finder, should leave the A window showing A and open/show B in a different window.
- Opening the same supported file more than once is allowed. The app should create another tab/window copy rather than jump to an existing one.
- Each open tab keeps its own search text, current search match, PDF page, and zoom state during the current session.
- File-backed tabs/windows restore after app restart.
- Session windows restore saved size and position when possible.
- Reopened PDFs restore page and zoom state.
- Reopened PDFs also restore page and zoom from per-file PDF state after the previous tab/window was closed.
- Reopened Markdown files restore Source and Preview vertical scroll position from per-file Markdown state after the previous tab/window was closed.
- Unsaved Untitled Markdown documents are not restored unless they have been saved to a file.
- Search text remains session-only by design unless a later workflow needs it.

### 5.2 Read and Edit a Markdown File

The user opens a Markdown file and can view either the rendered preview, the original source text, or both side by side. The user can edit the Markdown source and save changes back to the file.

Expected behavior:

- Headings, basic lists, links, code blocks, blockquotes, basic tables, task lists, and underline convenience render in the native preview.
- Tables and task lists render in a basic readable form. Richer table styling, more polished checkbox visuals, and local images are known preview-fidelity improvement areas, not fully complete MVP behavior yet.
- The user can switch between preview only, source only, and split view.
- The source view shows the original Markdown text.
- The user can edit the Markdown source.
- The preview updates while editing.
- The app shows whether the file has unsaved changes.
- The user can create a new unsaved Markdown document.
- The user can save changes to the original file.
- The user can save changes as a new Markdown file.
- The user can search within the document.
- Markdown search highlights matches in preview, reports current/total match count, and supports previous/next result navigation.
- A Help menu Markdown syntax guide is available for common Markdown patterns.
- Common Markdown formatting can be inserted from the editor toolbar, visible Format dropdown, source-editor right-click menu, or Markdown app menu.
- Common formatting can also be applied by selecting text in Preview; the app maps the selected preview text back to Markdown source and applies the same formatting command.
- Generated headings must operate on whole lines so Markdown preview recognizes them.
- Underline is represented as `<u>text</u>` in source and rendered by the app preview as a supported convenience even though underline is not standard Markdown.
- Preview must preserve Markdown block structure instead of flattening the document into a single paragraph.
- Markdown windows must be resizable narrow enough for side-by-side comparison with another document window.
- The user can switch between light and dark system appearances.
- The sidebar can list headings generated from Markdown content. Jump-to-heading behavior is a future improvement.

### 5.3 Read a PDF File

The user opens a PDF and can move through it comfortably.

Expected behavior:

- Pages render clearly.
- The user can go to next page, previous page, first page, last page, or a specific page number.
- The user can zoom in, zoom out, fit page, and fit width.
- The user can search text within the PDF.
- PDF search reports current/total match count and supports previous/next result navigation.
- The user can use thumbnails to jump between pages.
- If the PDF has an outline/table of contents, the app displays it.

### 5.4 Annotate a PDF

The user can add review marks on top of a PDF.

Expected behavior:

- The user can highlight text.
- The user can add text notes.
- The user can draw freehand marks.
- The user can add simple shapes such as rectangles, circles, lines, and arrows.
- The user can undo and redo annotation changes.
- The user can save annotations into a new PDF or sidecar project file.

### 5.5 Manage PDF Pages

The user can perform common page-level operations.

Expected behavior:

- Rotate pages.
- Delete pages.
- Reorder pages.
- Extract selected pages into a new PDF.
- Merge another PDF into the current PDF.
- Save the result as a new PDF.

## 6. Feature Requirements

## 6.1 App Shell

Required:

- Top toolbar with file open, search, print, and document-specific view controls.
- Left sidebar that can switch between thumbnails, table of contents, and recent files.
- Main document viewing area.
- Status area showing file name, current page or section, and loading state.
- Keyboard-friendly navigation.
- Tab strip for multiple open documents within a window.
- Separate app windows for Finder/Open With document comparison.
- Markdown document windows should be able to shrink to roughly half-screen width.

Recommended:

- Split view for comparing two documents.
- Command palette for common actions.

## 6.2 Markdown Viewer

Required:

- Render Markdown preview with native AppKit/SwiftUI components.
- Show original Markdown source text.
- Edit Markdown source text.
- Save Markdown changes.
- Save Markdown as a new file.
- Switch between preview, source, and split view.
- Update preview while editing.
- Show saved and unsaved state.
- Support common Markdown basics: headings, paragraphs, unordered lists, ordered lists, quotes, code blocks, basic tables, task lists, bold, italic, underline convenience, and inline code.
- Generate a heading list from Markdown headings in the sidebar.
- Search within rendered content.
- Help menu syntax guide for Markdown beginners.
- Formatting assistance such as bold, italic, underline-like HTML, link, heading, list, quote, and code commands from toolbar buttons, a visible Format dropdown, menu items, keyboard shortcuts, or right-click/context actions.
- Formatting assistance should work from source selections and preview selections.
- Print Markdown source text.
- Preserve readable typography across different screen sizes.

Recommended:

- A richer text-editor bridge that can preserve cursor/selection state more predictably across SwiftUI refreshes.
- A richer Markdown renderer for polished tables, local images, and more GitHub-Flavored-Markdown-compatible output. Native `AttributedString(markdown:)` parses many constructs but flattens tables/task lists, so the app currently uses its own lightweight parser for basic table and task-list preview support.
- Copy code block contents.
- Export Markdown to PDF.
- Export Markdown to HTML.
- Mermaid diagram rendering.
- Math rendering using KaTeX or MathJax.
- Front matter display or hiding.

## 6.3 PDF Viewer

Required:

- Render PDF pages.
- Page navigation.
- Page number jump.
- Zoom controls.
- Fit width.
- Fit page.
- Text search.
- Thumbnail sidebar.
- Document outline sidebar when available.
- Text selection and copy.
- Print.
- Save a copy.
- Rotate view.

Recommended:

- Fullscreen reading mode.
- Presentation mode.
- Two-page spread mode.
- Continuous scroll and single-page modes.
- Remember last page and zoom per file.
- Password-protected PDF support.

## 6.4 PDF Annotation

Implemented v1 on branch `feature/pdf-annotation`:

- Highlight selected text.
- Underline selected text.
- Strike through selected text.
- Remove highlight/underline/strikeout markup from selected text.
- Add sticky note comments.
- Move sticky note icons with a dedicated Move Note mode.
- Save embedded annotations back to the PDF file.
- Save an annotated PDF copy without overwriting the original.
- Warn before closing a PDF tab/window with unsaved annotations.

Still required after v1:

- Add text boxes.
- Draw freehand ink.
- Add rectangle, ellipse, line, and arrow shapes.
- Select, move, and edit annotations.
- Undo and redo annotation actions.

Recommended:

- Annotation sidebar.
- Filter annotations by type.
- Export annotation summary.
- Author name and timestamp for annotations.
- Color picker and stroke width controls.

## 6.5 PDF Page Operations

Required after MVP:

- Rotate selected pages.
- Delete selected pages.
- Reorder pages using thumbnails.
- Extract selected pages.
- Merge PDFs.
- Insert blank pages.
- Save edited PDF as a new file.

Recommended:

- Split PDF by page ranges.
- Compress PDF.
- Add watermark.
- Add page numbers.
- Flatten annotations.

## 6.6 Existing PDF Text Editing

Changing existing PDF text is not recommended for the MVP.

Reason:

PDFs usually store visual instructions instead of editable document structure. Text can be split into many positioned fragments, fonts may be embedded, and paragraphs are not always preserved as logical text blocks.

Possible future support:

- Limited visual replacement: cover old text and place new text on top.
- Object-level editing for simple PDFs.
- Convert PDF to editable document format, edit, then export back to PDF.

The app should clearly distinguish between true content editing and annotation/page editing.

## 7. Non-Functional Requirements

## 7.1 Performance

- Open common Markdown files instantly.
- Render normal PDFs smoothly.
- Lazy-load PDF pages instead of rendering every page at once.
- Keep scrolling responsive for long PDFs.
- Avoid blocking the interface during file parsing.

## 7.2 Privacy

- Files should stay on the user's device by default.
- The app should not upload documents unless a cloud feature is explicitly added.
- Recent file data should be stored locally.

## 7.3 Reliability

- Never overwrite the original file without clear user confirmation.
- For PDF edits, default to saving a new copy.
- Recover gracefully if a file cannot be opened.
- Show useful errors for corrupted, encrypted, or unsupported documents.

## 7.4 Accessibility

- Support keyboard navigation.
- Provide visible focus states.
- Keep strong text contrast.
- Use readable default font sizes.
- Provide labels/tooltips for icon buttons.

## 8. Suggested MVP Scope

The MVP should include:

- Open local Markdown and PDF files.
- Drag-and-drop file opening.
- Markdown rendered preview.
- Markdown source view.
- Markdown editing.
- Markdown split view.
- Save Markdown changes.
- Save Markdown as a new file.
- PDF rendering with page navigation.
- PDF zoom, fit width, and fit page.
- Search within Markdown and PDF.
- Thumbnail sidebar for PDFs.
- Table of contents for Markdown.
- Recent files.
- Light and dark theme.
- Restore last position per file.

The MVP should not include:

- Full PDF text editing.
- Cloud sync.
- User accounts.
- Office document support.
- Advanced annotation collaboration.

## 9. Suggested Version Roadmap

### Version 0.1: Viewer MVP

- File opening.
- Markdown rendering.
- Markdown source view and editing.
- Markdown preview/source/split modes.
- Markdown save and save as.
- PDF rendering.
- Search.
- Zoom.
- Sidebar.
- Recent files.
- Theme switch.

### Version 0.2: Reading Workspace

- Tabs.
- Better table of contents.
- Markdown code copy buttons.
- PDF outline support.
- Remember reading position.
- Keyboard shortcuts.

### Version 0.3: PDF Annotation

- Highlights.
- Notes.
- Text boxes.
- Freehand drawing.
- Shape annotations.
- Save annotated PDF copy.

### Version 0.4: PDF Page Tools

- Rotate, delete, reorder pages.
- Extract pages.
- Merge PDFs.
- Insert blank pages.

### Version 0.5: Export and Advanced Markdown

- Markdown to PDF export.
- Markdown to HTML export.
- Mermaid diagrams.
- Math rendering.

## 10. Technical Recommendations

## 10.1 App Framework

Required:

- SwiftUI for the app shell, toolbar, sidebar, Markdown workspace, and app state.
- AppKit bridges only where native controls are needed, such as PDFKit integration.
- macOS 26 as the deployment target.
- Xcode 26.5 / Swift 6.3 as the expected development environment.

## 10.2 Markdown Rendering

Recommended libraries:

- Swift `AttributedString(markdown:)` for the first native preview.
- A custom Markdown renderer or embedded rendering engine can be considered later if GitHub-flavored Markdown fidelity becomes a priority.
- Mermaid and math support should be treated as future enhancements.

## 10.3 PDF Rendering and Editing

Recommended libraries:

- `PDFKit` for native PDF rendering, navigation, search, thumbnails, and selection.
- PDF page operations can be added later with PDFKit and lower-level PDF document APIs.
- Annotation support should use PDFKit annotations where possible.

Important note:

PDFKit is excellent for native viewing and common PDF workflows. True PDF content editing is still difficult because the PDF format is layout-oriented, not document-structure-oriented.

## 10.4 Desktop Packaging

Required:

- Build as a native macOS app.
- Swift Package or Xcode project may be used during early development.
- Release packaging should produce a `.app` bundle.

## 11. Data Storage

Local app data should include:

- Recent files.
- Last opened file.
- Last page or scroll position.
- Last zoom level.
- Theme preference.
- Per-file viewing preferences.
- Optional annotation sidecar files before PDF export is implemented.

Possible storage options:

- `UserDefaults` for simple app preferences and recent document metadata.
- App-scoped local JSON files if richer state is needed.
- macOS security-scoped bookmarks may be needed for persistent file access outside the app sandbox.

## 12. Key Design Principles

- The first screen should be the viewer itself, not a marketing page.
- The app should feel quiet, fast, and practical.
- Toolbars should use familiar icons with tooltips.
- Reading should be the center of the experience.
- Editing tools should appear only when useful.
- PDF editing should be honest about what is annotation, page editing, and true content editing.

## 13. Open Questions

- Should PDF annotations be saved as a separate project file first, or directly embedded into exported PDFs?
- Should there be a file browser panel, or only open/recent files?
- Should the design target technical users first, general office users first, or both?
