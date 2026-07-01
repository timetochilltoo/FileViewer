# FileViewer MVP Task List

## 1. MVP Definition

The MVP is a native macOS SwiftUI document viewer and editor that supports:

- Opening Markdown and PDF files.
- Viewing Markdown as rendered preview, source text, or split view.
- Editing and saving Markdown files.
- Formatting Markdown from source or preview selections.
- Viewing PDFs with page navigation, zoom, thumbnails, and search.
- Remembering recent files.
- Light and dark themes.
- Opening documents in tabs and Finder/Open With documents in separate windows for side-by-side comparison.

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
- Opening the same file more than once is allowed.
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
- The app builds successfully with Swift 6.3.2 / Xcode 26.5.

Next implementation work:

- Continue PDF annotation beyond v1:
  - improve text box editing/resizing
  - improve sticky note editing
  - freehand ink
  - shapes
  - direct annotation selection/move/undo
- Improve Markdown preview fidelity for richer GitHub-flavored tables, local images, and task-list polish if needed later.
- Add tests or sample files for repeatable verification.
