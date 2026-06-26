# FileViewer MVP Task List

## 1. MVP Definition

The MVP is a native macOS SwiftUI document viewer and editor that supports:

- Opening Markdown and PDF files.
- Viewing Markdown as rendered preview, source text, or split view.
- Editing and saving Markdown files.
- Viewing PDFs with page navigation, zoom, thumbnails, and search.
- Remembering recent files and last reading position.
- Light and dark themes.

PDF annotation and PDF page editing are not part of the MVP. They will be added after the core viewer is stable.

## 2. Project Setup

- Create native SwiftUI macOS app structure.
- Set deployment target to macOS 26.
- Add basic app layout with toolbar, sidebar, and main viewer area.
- Add app-wide native styling.
- Support system light and dark appearance.
- Add persistent local settings storage using `UserDefaults`.

Acceptance criteria:

- App builds with Xcode 26.5 / Swift 6.3.
- App starts locally as a native macOS application.
- Main interface is visible.
- Theme can switch between light and dark.
- Basic layout works on desktop and tablet-sized screens.

## 3. File Opening

- Add open-file button.
- Add drag-and-drop file opening.
- Detect file type by extension and file metadata.
- Route Markdown files to Markdown workspace.
- Route PDF files to PDF workspace.
- Show clear message for unsupported files.
- Track current file name and file path when available.
- Use native `NSOpenPanel` or SwiftUI file importer.

Acceptance criteria:

- User can open `.md`, `.markdown`, and `.pdf` files.
- Drag-and-drop works.
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
- Display original Markdown source in a SwiftUI `TextEditor` or native editor component.
- Preserve line breaks and formatting.
- Add source-only view mode.
- Add basic source search.

Acceptance criteria:

- User can see the original Markdown text.
- Markdown source matches the file content.
- Large files remain usable.

## 6. Markdown Preview

- Render Markdown to HTML.
- Render Markdown preview using native Swift Markdown support for the first version.
- Support GitHub-flavored Markdown.
- Support headings, lists, links, blockquotes, tables, code blocks, images, and task lists.
- Add syntax highlighting for code blocks.
- Add copy button for code blocks.
- Generate table of contents from headings.
- Add preview-only view mode.

Acceptance criteria:

- Common Markdown features render correctly.
- Code blocks are readable and copyable.
- Table of contents jumps to headings.

## 7. Markdown Split View and Live Preview

- Add view mode switcher: preview, source, split.
- In split view, show editor and preview side by side.
- Update preview when source text changes.
- Keep split view usable on smaller screens.
- Consider stacked split layout on narrow screens.

Acceptance criteria:

- User can switch between all three Markdown modes.
- Editing source updates preview.
- Layout does not overlap or hide content.

## 8. Markdown Editing and Save

- Track unsaved changes.
- Show saved/unsaved state in the interface.
- Add save action.
- Add save-as action.
- Warn before closing or switching away from unsaved edits.
- Handle save errors clearly.

Acceptance criteria:

- User can edit Markdown and save changes.
- Saved file contains the edited text.
- Unsaved changes are visible to the user.
- Save failure does not lose user edits.

## 9. PDF Rendering

- Integrate PDFKit.
- Load local PDF files.
- Render pages clearly.
- Lazy-render pages for performance.
- Add loading and error states.
- Support password/error messaging for encrypted or damaged PDFs.

Acceptance criteria:

- User can open and read normal PDF files.
- Long PDFs remain responsive.
- Bad PDFs show an understandable error.

## 10. PDF Navigation

- Add next page and previous page controls.
- Add page number input.
- Add first page and last page actions.
- Add continuous scroll mode for MVP.
- Track current page while scrolling.
- Remember last page per file.

Acceptance criteria:

- User can move through a PDF easily.
- Page number display stays accurate.
- Reopening a PDF restores last page.

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
- User can move between matches.

## 13. PDF Sidebar

- Add thumbnail sidebar.
- Use PDFKit thumbnails where possible.
- Click thumbnail to jump to page.
- Show PDF outline/table of contents when available.
- Allow sidebar mode switching between thumbnails, outline, and recent files.

Acceptance criteria:

- Thumbnails appear for PDFs.
- Clicking a thumbnail navigates to that page.
- Outline appears when the PDF provides one.

## 14. Shared Search

- Use a consistent search interface for Markdown and PDF.
- Support keyboard shortcut for search.
- Show current match and total matches.
- Allow next and previous result.

Acceptance criteria:

- Search behavior feels consistent across file types.
- Keyboard shortcut opens search.

## 15. Persistent Document State

- Store last page for PDFs.
- Store last scroll position for Markdown.
- Store last Markdown view mode.
- Store last zoom level.
- Store theme preference.

Acceptance criteria:

- Reopening a document restores useful context.
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

Acceptance criteria:

- Core workflows pass on sample Markdown and PDF files.
- No obvious layout overlap on common screen sizes.
- App can be used without developer tools.
- App can be launched from Xcode or the Swift build output.

## 19. Out of Scope for MVP

- PDF text editing.
- PDF annotation.
- PDF page reorder/delete/merge.
- Cloud sync.
- Login/accounts.
- Collaboration.
- Mobile app packaging.
- Office document preview.
- Markdown to PDF export.
- Mermaid and math rendering.

## 20. Suggested Build Order

1. Project setup and layout.
2. File opening and file type detection.
3. Markdown source view.
4. Markdown preview.
5. Markdown split view and live preview.
6. Markdown save and save-as.
7. PDF rendering.
8. PDF navigation and zoom.
9. PDF thumbnails and outline.
10. PDF search.
11. Recent files and persistent document state.
12. Keyboard shortcuts and final polish.

## 21. Current Native Build Status

- SwiftUI macOS package has been created.
- Native app shell has been created.
- Markdown source, preview, split view, edit, save, and save-as have been implemented.
- PDFKit PDF viewing has been implemented.
- PDF page navigation, zoom, thumbnails, and search highlighting have been implemented.
- Recent files have been implemented.
- The app builds successfully with Swift 6.3.2 / Xcode 26.5.

Next implementation work:

- Improve Markdown preview fidelity for GitHub-flavored tables and task lists.
- Add richer Markdown search result highlighting.
- Package the executable as a `.app` bundle for normal double-click launching.
- Add app icon and polished macOS menus.
- Add tests or sample files for repeatable verification.
