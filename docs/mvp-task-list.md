# FileViewer MVP Task List

## 1. MVP Definition

The MVP is a native macOS SwiftUI document viewer and editor that supports:

- Opening Markdown and PDF files.
- Creating a new unsaved Markdown document from the main toolbar or File menu.
- Viewing Markdown as rendered preview, source text, or split view.
- Editing and saving Markdown files.
- Formatting Markdown from source or preview selections.
- Viewing PDFs with page navigation, zoom, thumbnails, and search.
- Remembering recent files.
- Light and dark themes.
- Opening documents in tabs and Finder/Open With documents in separate windows for side-by-side comparison.

PDF annotation and fillable-form support were implemented after the original MVP. View rotation and permanent rotation of the current page or all pages are also implemented. Larger PDF page-editing operations (reorder, delete, extract, merge) remain outside the original MVP and are tracked in the active post-MVP plan below.

## 2. Project Setup

- Create native SwiftUI macOS app structure.
- Set deployment target to macOS 26.
- Add basic app layout with toolbar, sidebar, and main viewer area.
- Add compact New Markdown action between the sidebar toggle and Open control.
- Add app-wide native styling.
- Support system light and dark appearance.
- Add persistent local settings storage using `UserDefaults`.

Acceptance criteria:

- App builds with the project Swift tools version 6.2 on macOS 26.
- App starts locally as a native macOS application.
- Main interface is visible.
- Theme can switch between light and dark.
- Basic layout works on desktop and tablet-sized screens.

## 3. File Opening

- Add open-file button.
- Add New Markdown button.
- Add drag-and-drop file opening.
- Add Finder/Open With file opening.
- Detect file type by extension and file metadata.
- Route Markdown files to Markdown workspace.
- Route PDF files to PDF workspace.
- Show clear message for unsupported files.
- Track current file name and file path when available.
- Use native `NSOpenPanel` or SwiftUI file importer.

Acceptance criteria:

- User can open `.md`, `.markdown`, and `.pdf` files.
- Drag-and-drop works, including multiple dropped files.
- Finder/Open With documents open in a target window only; existing windows must not all switch to the newest document.
- Opening a file already open in FileViewer brings the existing writable instance forward instead of creating another writable copy.
- Unsupported files do not crash the app.
- Current file name appears in the interface.

## 4. Recent Files

- Store recently opened files locally.
- Show recent files in sidebar or start state.
- Allow reopening recent files.
- Remove missing or inaccessible files from recent list.
- Store last opened timestamp.

Acceptance criteria:

- Recently opened files appear after app reload.
- User can reopen a recent document.
- Missing files show a graceful message.

## 5. Markdown Source View

- Load Markdown file as plain text.
- Display original Markdown source in a native `NSTextView` editor component.
- Preserve line breaks and formatting.
- Add source-only view mode.
- Add formatting toolbar/menu/context commands for common Markdown syntax.

Acceptance criteria:

- User can see the original Markdown text.
- Markdown source matches the file content.
- Large files remain usable.

## 6. Markdown Preview

- Render Markdown preview using native AppKit/SwiftUI components.
- Preserve Markdown block structure instead of flattening content into one paragraph.
- Support headings, paragraphs, basic lists, links, blockquotes, code blocks, basic tables, task lists, bold, italic, inline code, and underline convenience.
- Treat richer table styling, local images, richer code styling, and copy-code buttons as future preview-fidelity improvements.
- Generate a heading list from Markdown headings.
- Add preview-only view mode.
- Allow selected preview text to be formatted back into the Markdown source.

Acceptance criteria:

- Common Markdown basics render correctly.
- Code blocks are readable.
- Heading list appears in the sidebar.
- Preview-selection formatting works for common text selections, with repeated-text ambiguity documented as a limitation.

## 7. Markdown Split View and Live Preview

- Add view mode switcher: preview, source, split.
- In split view, show editor and preview side by side.
- Update preview when source text changes.
- Keep split view usable on smaller screens.
- Keep Markdown windows narrow enough for two documents side-by-side.

Acceptance criteria:

- User can switch between all three Markdown modes.
- Editing source updates preview.
- Layout does not overlap or hide content.

## 8. Markdown Editing and Save

- Track unsaved changes.
- Show saved/unsaved state in the interface.
- Add save action.
- Add save-as action.
- Warn before closing unsaved Markdown tabs/windows.
- Handle save errors clearly.

Acceptance criteria:

- User can edit Markdown and save changes.
- Saved file contains the edited text.
- Unsaved changes are visible to the user.
- Save failure does not lose user edits.
- Closing an unsaved Markdown tab/window asks Save, Don’t Save, or Cancel.
- Cancelling Save As cancels the close.

## 9. PDF Rendering

- Integrate PDFKit.
- Load local PDF files.
- Render pages clearly.
- Lazy-render pages for performance.
- Add loading and error states.
- Treat encrypted/password-protected PDFs as unsupported; password-entry UI is outside the product scope.

Acceptance criteria:

- User can open and read normal PDF files.
- Long PDFs remain responsive.
- Bad PDFs show an understandable error.

## 10. PDF Navigation

- Add next page and previous page controls.
- Add page number input.
- Add first page and last page actions.
- Use continuous scroll mode for MVP. The native viewer currently uses continuous scrolling by default; user-selectable single-page and two-page modes remain future work.
- Track current page while scrolling.
- Remember last page per file.

Acceptance criteria:

- User can move through a PDF easily.
- Page number display stays accurate.
- Reopening a PDF restores last page after session restore or per-file PDF state is available.

## 11. PDF Zoom and View Controls

- Add zoom in and zoom out.
- Add fit width.
- Add fit page.
- Add reset zoom.
- Preserve zoom preference per file.

Acceptance criteria:

- User can adjust PDF size.
- Fit width and fit page behave predictably.
- Zoom does not break page layout.

## 12. PDF Search

- Extract searchable text from PDF pages.
- Add search box.
- Highlight matching results.
- Add next result and previous result controls.
- Show result count.

Acceptance criteria:

- User can search text in a PDF.
- Matches are highlighted.
- User can see the current match and total match count.
- User can move to previous/next matches.

## 13. PDF Sidebar

- Add thumbnail sidebar.
- Use PDFKit thumbnails where possible.
- Click thumbnail to jump to page.
- Show PDF outline/table of contents when available.
- Allow sidebar mode switching between thumbnails, outline, and recent files.

Acceptance criteria:

- Thumbnails appear for PDFs.
- Clicking a thumbnail navigates to that page.
- Outline entries appear for PDFs that provide a table of contents/bookmarks.
- Clicking an outline entry navigates to its destination page when available.

## 14. Shared Search

- Use a consistent search interface for Markdown and PDF.
- Support keyboard shortcut for search.
- Show current match and total matches.
- Allow next and previous result.

Acceptance criteria:

- Search behavior feels consistent across file types.
- Keyboard shortcut opens search.
- Search field shows current match and total matches.
- Previous/next search controls move between matches.

## 15. Persistent Document State

- Store last page for PDFs.
- Store last scroll position for Markdown.
- Store last Markdown view mode.
- Store last zoom level.
- Store theme preference.

Acceptance criteria:

- Reopening a document restores useful context after persistence is implemented.
- App reload does not lose preferences.

## 16. Keyboard Shortcuts

- Open file.
- Save Markdown.
- Save Markdown as.
- Search.
- Zoom in.
- Zoom out.
- Reset zoom.
- Next page.
- Previous page.
- Toggle sidebar.

Acceptance criteria:

- Common shortcuts work.
- Shortcuts do not interfere with Markdown typing.

## 17. Error Handling

- Unsupported file type message.
- File read error message.
- File save error message.
- PDF render error message.
- Empty state when no file is open.
- Unsaved changes warning.

Acceptance criteria:

- Errors are clear and non-technical where possible.
- User edits are not lost after an error.

## 18. Testing and Verification

- Test opening Markdown files.
- Test editing and saving Markdown files.
- Test Markdown split view.
- Test opening PDF files.
- Test PDF navigation.
- Test PDF zoom.
- Test PDF search.
- Test recent files.
- Test light and dark themes.
- Test drag-and-drop.
- Test Finder/Open With opening multiple files into separate windows.
- Test shrinking two Markdown windows side-by-side.
- Test formatting buttons in Source and Preview modes.

Acceptance criteria:

- Core workflows pass on sample Markdown and PDF files.
- No obvious layout overlap on common screen sizes.
- App can be used without developer tools.
- App can be launched from Xcode, Swift build output, or packaged `.app` bundle.

## 19. Out of Scope for MVP

This section records the boundary of the original viewer MVP. Some items, including PDF annotation, were implemented in later iterations.

- PDF text editing.
- PDF annotation.
- PDF page reorder/delete/merge/extract/insert.
- Cloud sync.
- Login/accounts.
- Collaboration.
- Mobile app packaging.
- Office document preview.
- Markdown to PDF export.
- Mermaid and math rendering.
- AI assistant integration.

## 20. Suggested Build Order

1. Project setup and layout.
2. File opening and file type detection.
3. Markdown source view.
4. Markdown preview.
5. Markdown split view and live preview.
6. Markdown save and save-as.
7. PDF rendering.
8. PDF navigation and zoom.
9. PDF thumbnails.
10. PDF search.
11. Recent files.
12. Keyboard shortcuts and final polish.

## 21. Current Native Build Status

- SwiftUI macOS package has been created.
- Native app shell has been created.
- Markdown source, preview, split view, edit, save, and save-as have been implemented.
- PDFKit PDF viewing has been implemented.
- PDF page navigation, first/last page controls, zoom, thumbnails, search highlighting, search result count, and previous/next search navigation have been implemented.
- Recent files have been implemented.
- Multiple tabs per window have been implemented.
- File-backed tabs/windows restore after app restart.
- PDF page and zoom state restore after app restart.
- Reopened PDFs restore page and zoom from per-file PDF state even after the previous tab/window was closed.
- Reopened Markdown files restore Source and Preview vertical scroll position from per-file Markdown state.
- Session windows restore saved window size and position when possible.
- PDF outline/table-of-contents support has been implemented for PDFs that provide outline/bookmark entries.
- Finder/Open With opens documents in separate windows without changing existing document windows.
- Markdown windows can shrink for side-by-side comparison.
- Markdown formatting buttons work from Source and Preview selections.
- Markdown search shows current/total matches and supports previous/next result navigation.
- A visible Format dropdown gives text-labeled Markdown commands for beginners.
- Insert Table and Task List formatting helpers have been implemented.
- Basic Markdown table and task-list preview rendering has been implemented.
- Source-editor right-click formatting uses a custom Markdown command menu.
- Unsaved Markdown tab/window close confirmation has been implemented.
- A packaged `.app` bundle with icon and document type registration has been implemented.
- The main toolbar includes New Markdown between the sidebar toggle and Open, while Save, Save As, and Print remain menu/shortcut actions.
- The app builds successfully with Swift tools version 6.2 on macOS 26.
- PDF annotations, drawing, notes, form editing, safe PDF save, and annotation reports have been implemented after the original MVP.
- Reading-only view rotation plus permanent current-page/all-page rotation have been implemented. The permanent actions save only after an explicit Save or Save As.
- The original viewer MVP is complete. Later work has also implemented PDF annotation/form support and the AI assistant on `main`: a resizable right panel, per-tab in-memory conversations, PDF/Markdown selection capture, four explicit scopes, local retrieval, streaming, cancellation, provider/model discovery, and explicit remote document-transfer approval. Provider profiles now include LM Studio, Ollama, custom OpenAI-compatible servers, and OpenAI; credentials are stored only in Keychain.
- The Local Library slice now provides a Library sidebar with recent-file and user-selected-folder indexing, local filename/heading/text/annotation search, result snippets, and safe opening through the existing document flow. Indexed document text is memory-only; selected folder paths are stored locally.

## 22. Build-plan audit and Mac-first post-MVP plan (2026-09-19)

The original viewer MVP and later PDF annotation/form and AI milestones are implemented. The following plan items remain unfinished or partial:

- Local library: tags, incremental background refresh, and a durable searchable index remain future work; the current index is rebuilt on demand and keeps document text in memory only.
- Markdown preview: richer GitHub-Flavored Markdown tables, local image rendering, richer code presentation, copy-code actions, and heading-to-source navigation.
- PDF workflow: fullscreen/presentation mode, two-page spread or selectable single-page mode, and page delete/reorder/extract/merge/insert.
- PDF annotations: author and timestamp metadata.
- Export: Markdown-to-PDF/HTML, PDF page/image export, and advanced PDF operations.
- Advanced Markdown: Mermaid and math rendering.
- AI: richer retrieval/embedding search, complete-document hierarchical summaries, conversation persistence, clickable citations, and broader cache invalidation. Selection actions and the PDF per-tab extraction/index cache are implemented.
- Verification: focused UI/sample-file tests for PDF outline/search/annotation/forms, multi-window restoration, and live AI streaming/error states.

The active build plan deliberately targets local, single-user Mac workflows. Cloud sync, accounts, real-time collaboration, marketplace, infinite whiteboards, mobile packaging, and native Study Sets remain deferred.

### Phase A — high-value Mac features

1. **Local library and global search** — the first local folder/index/search slice is implemented; add tags, incremental refresh, durable index storage, and richer filters while keeping clear local-only controls.
2. **PDF page tools** — thumbnail multi-selection, reorder, duplicate, delete, extract/split, insert, and export, using the existing atomic-save and external-change protections.
3. **Reading and presentation** — fullscreen reading, presentation mode, page-advance shortcuts, temporary cursor/laser focus, and optional two-page spread.
4. **Markdown fidelity and templates** — local images, richer tables/task lists/code blocks, copy-code, heading navigation, and user-managed Markdown/PDF templates.
5. **Export workflow** — export selected/current PDF pages as PDF/image and Markdown as PDF/HTML where the result can be verified.

### Phase B — medium-effort features with optional hardware

1. **Pointer and tablet annotation** — stroke smoothing, lasso/eraser/object selection, and optional AppKit pressure/tilt input for external tablets; keep mouse/trackpad as a usable baseline.
2. **On-device OCR** — recognize scanned PDF text and captured ink locally, index results, and offer handwriting-to-text while preserving original strokes.
3. **Audio notes** — local recording, page/selection timestamps, playback, and optional on-device transcription.
4. **AI study helpers** — generate Markdown/CSV flashcards, summaries with stable source links, and Mermaid mind-map drafts from selected document context.
5. **Focused UI/sample tests** — exercise the new flows with real PDFs and Markdown fixtures.

Deliver one coherent feature at a time with safety tests and manual UI checks where PDFKit/AppKit behavior is involved.
