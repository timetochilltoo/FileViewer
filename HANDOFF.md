# FileViewer Handoff

Last updated: 2026-06-27  
Active repo: `/Users/patrickshi/Documents/Codex/FileViewer`  
GitHub remote: `https://github.com/timetochilltoo/FileViewer.git`  
Current branch at time of writing: `main`  
Latest known committed handoff baseline before the New/Print/Markdown syntax fixes: `7bab439` (`Add detailed FileViewer handoff`)

## 1. Project purpose

FileViewer is Patrick's local-first native macOS document viewer/editor. It currently targets macOS Tahoe / macOS 26 only. Compatibility with older macOS versions is intentionally not required.

The app is intended to be a lightweight daily document workspace for:

- Markdown notes (`.md`, `.markdown`)
- PDFs (`.pdf`)
- multiple open documents through tabs
- simple Markdown editing, preview, search, and formatting assistance
- creating new unsaved Markdown documents
- printing PDFs and Markdown source text
- PDF reading, page navigation, zoom, thumbnails, and search

The repo still contains an older React/Vite prototype (`src/`, `dist/`, `package.json`, `vite.config.*`, etc.), but the official implementation direction is now the native SwiftUI app under `Sources/FileViewer`. Do not spend time extending the React/Vite prototype unless Patrick explicitly asks.

## 2. Current development environment

- Swift package: `Package.swift`
- Swift tools version: `6.2`
- Platform: `.macOS(.v26)`
- Main app target: executable target `FileViewer`
- App entry point: `Sources/FileViewer/FileViewerApp.swift`
- Packaged app path:

```text
/Users/patrickshi/Documents/Codex/FileViewer/build/FileViewer.app
```

Build commands:

```bash
cd /Users/patrickshi/Documents/Codex/FileViewer
swift build
./scripts/package_app.sh
```

`scripts/package_app.sh`:

1. builds release executable with `swift build -c release`
2. creates `build/FileViewer.app`
3. generates the app icon using Python/Pillow
4. writes `Info.plist`
5. ad-hoc signs the app with `codesign --force --deep --sign -`
6. verifies the app signature

There is not yet a formal automated test suite. Verification so far has been:

- `swift build`
- `./scripts/package_app.sh`
- user manual testing with real Markdown/PDF files
- crash-log-driven fixes

## 3. High-level architecture

### SwiftUI app structure

```text
Sources/FileViewer/
├── AppCommands.swift
├── ContentView.swift
├── DocumentModel.swift
├── FileViewerApp.swift
├── MarkdownSyntaxHelp.swift
├── MarkdownWorkspace.swift
├── PDFWorkspace.swift
└── SidebarView.swift
```

### `FileViewerApp.swift`

Defines the app entry point:

- Uses `@NSApplicationDelegateAdaptor(FileViewerAppDelegate.self)` for macOS file-open events.
- Creates a `WindowGroup`.
- Installs `ContentView`.
- Sets minimum frame size to `520 x 620`.
- This smaller minimum is intentional. Patrick compares documents side-by-side and reported that Markdown windows could not be dragged narrow enough, unlike PDF Preview windows.
- Uses `.windowStyle(.titleBar)`.
- Registers `FileViewerCommands`.

`FileViewerAppDelegate.application(_:open:)` routes Finder / Open With file-open events through `FileViewerWindowRegistry`. This replaced an earlier global notification approach after Patrick reported that opening document B from Finder caused every existing FileViewer window to switch to B.

Current behavior is window-based:

- `FileViewerAppDelegate.application(_:open:)` calls `FileViewerWindowRegistry.shared.openExternal(urls)` on the main actor.
- `ContentView.onAppear` registers its per-window `AppModel` with the registry.
- The registry reuses an empty startup window for the first external file if one exists.
- If existing windows already contain documents, each later Finder/Open With URL opens in a fresh `NSWindow` with its own `ContentView(initialURLs:)` and own `AppModel`.
- If macOS delivers a file-open event before the startup window registers, the registry briefly stores the URL in `pendingExternalURLs`; the first registering empty window consumes it. If no window registers on the next main-loop pass, the registry creates a new window itself.
- Do not reintroduce a global `.openFileURLs` notification unless it is targeted to a specific window/model; otherwise every open window will respond and show the same newest document.

### `FileViewerWindowRegistry.swift`

Coordinates macOS external file-open events with per-window state.

- Holds weak references to registered `AppModel` instances so closed windows do not keep models alive.
- Retains manually-created `NSWindow` instances while they are visible.
- `openExternal(_:)` opens each external URL independently:
  - first tries to reuse an empty registered window/model
  - otherwise creates a new window
- `pendingExternalURLs` prevents a document-launched app from creating both an empty startup window and a separate document window when timing is unlucky.
- Manually-created windows default to `760 x 720` with `minSize = 520 x 620`, so two Markdown windows can fit side-by-side more easily.
- The registry also installs a retained `WindowCloseDelegate` for each registered `NSWindow`. This delegate calls `AppModel.canCloseAllDocuments()` so closing a whole window checks unsaved Markdown tabs before the window disappears.
- This file exists specifically because Patrick wants Finder-opened documents to appear in separate windows, not merely separate tabs, and because broadcasting file-open events to every `ContentView` caused all windows to show the same document.

### `DocumentModel.swift`

This is the main state/model file. It is annotated `@MainActor` for UI state safety.

Important types:

- `DocumentKind`
  - `.markdown`
  - `.pdf`
- `MarkdownMode`
  - `.preview`
  - `.source`
  - `.split`
- `MarkdownFormatCommand`
  - `.bold`
  - `.italic`
  - `.underline`
  - `.heading`
  - `.bulletList`
  - `.numberedList`
  - `.quote`
  - `.link`
  - `.code`
- `SidebarMode`
  - `.recent`
  - `.contents`
  - `.pages`
- `RecentDocument`
- `SavedSessionWindow`
- `SavedSessionTab`
- `SavedPDFState`
- `SavedMarkdownState`
- `MarkdownHeading`
- `PDFOutlineEntry`
- `ViewerDocument`
  - `.markdown(MarkdownDocument)`
  - `.pdf(PDFViewerDocument)`
- `DocumentTab`
  - wraps a `ViewerDocument`
  - stores per-tab `searchText`
  - stores per-tab `searchMatchIndex` and `searchMatchCount`
  - stores per-tab `markdownSourceScrollY` and `markdownPreviewScrollY`
  - stores per-tab `pdfPage`, `pdfPageCount`, and `pdfScale`
- `MarkdownDocument`
  - `url`
  - `text`
  - `savedText`
  - `hasUnsavedChanges`
- `PDFViewerDocument`
  - `url`
  - `PDFDocument`

Important `AppModel` published state:

- `tabs: [DocumentTab]`
- `selectedTabID`
- `sidebarMode`
- `markdownMode`
- `statusMessage`
- `recents`

`AppModel.document`, `searchText`, `searchMatchIndex`, `searchMatchCount`, `pdfPage`, `pdfPageCount`, and `pdfScale` are computed wrappers over the selected tab. This is important: do not add new global document state unless it truly should apply across every tab. Most document-specific state should live inside `DocumentTab`.

Each window owns its own `AppModel` via `ContentView`'s `@StateObject`. Do not make `AppModel` a singleton. A singleton model would recreate the bug where every window shows the same selected document.

Important methods:

- `openWithPanel()`
  - Opens an `NSOpenPanel`.
  - Allows multiple selection.
  - Supports PDF and text-ish files; actual Markdown detection is extension-based.
- `open(url:)`
  - Always appends a new tab, even if the same URL is already open.
  - This is intentional: Patrick asked to allow multiple copies of the same PDF/Markdown file at the same time.
  - For Finder/Open With, this is called on the target window's model only. It must not be broadcast to all models/windows.
  - Opens Markdown by reading UTF-8 text.
  - Opens PDF using `PDFDocument(url:)`.
  - Adds recents.
- `selectTab(_:)`
- `closeTab(_:)`
- `newMarkdownDocument()`
  - creates an untitled Markdown tab without writing a temporary file
  - Save on an untitled document routes to Save As
- `updateMarkdown(_:)`
- `saveMarkdown()`
- `saveMarkdownAs()`
- `printDocument()`
  - PDFs print through PDFKit
  - Markdown currently prints source text through an `NSTextView`
- `setMarkdownMode(_:)`
- `reopenRecent(_:)`
- `sessionSnapshot()`
- `loadSavedSessionWindows()`
- `saveSessionWindows(_:)`
- `restore(window:)`
- `savePDFStateIfNeeded(for:)`
- `loadPDFState(for:)`
- `saveMarkdownStateIfNeeded(for:)`
- `loadMarkdownState(for:)`

Session restore:

- Implemented with `UserDefaults` key `FileViewer.session.windows`.
- Restores file-backed Markdown/PDF tabs and additional windows on launch.
- Session restore is delayed briefly by `FileViewerWindowRegistry.scheduleSessionRestoreIfPossible(using:)`.
- If the app receives Finder/Open With URLs during launch, `suppressSessionRestore` is set and old session windows are not restored. This avoids the confusing case where opening `A.pdf` also reopens previously closed/restored `D.pdf`, `E.pdf`, and `G.pdf`.
- Skips unsaved Untitled Markdown documents because there is no safe file path to reopen.
- Skips missing files silently.
- Does not restore search text by design; search text is session-only and would be annoying to revive unexpectedly.
- Restores PDF page and zoom via saved `pdfPage` / `pdfScale`.
- Also stores per-file PDF page/zoom in `UserDefaults` key `FileViewer.pdf.lastStates`. This is separate from session restore. It lets `A.pdf` reopen to its previous page even after its tab/window was closed and removed from the session snapshot.
- Also stores per-file Markdown Source/Preview vertical scroll positions in `UserDefaults` key `FileViewer.markdown.lastStates`. This is separate from session restore and lets a Markdown file reopen near the previous reading/editing position after its tab/window was closed.
- Markdown Source and Preview scroll positions are tracked separately because the two panes can be at different vertical offsets.
- PDF state is saved when `pdfPage` / `pdfScale` changes, when session snapshots are made, before opening another file, before switching tabs, and before closing a tab/window.
- Markdown scroll state is kept in memory while scrolling and written during natural save points: session snapshot, opening another file, switching tabs, and closing a tab/window. It intentionally does not write to `UserDefaults` on every tiny scroll movement.
- `pdfSyncCurrentState` notification asks the visible `PDFKitView` to synchronously push its current page/zoom back into `AppModel` before the model saves state. This covers the sequence: open `A.pdf`, go to page 67, open `B.pdf`, switch back to `A.pdf`, close, then reopen `A.pdf`.
- `markdownSyncCurrentState` notification asks visible Markdown Source/Preview scroll views to push their current vertical offsets back into `AppModel` before the model saves state.
- `FileViewerWindowRegistry.saveCurrentSession()` collects live window model snapshots and writes them.
- Closing a window removes that window's model from the registry and resaves the session, so closed windows should not come back on next launch.
- Important crash fix: do not release program-created `NSWindow` immediately inside `windowWillClose`, and do not mutate the retained window array from a delayed close callback. Patrick hit AppKit/Swift crashes after open/close/open and after closing multiple restored PDF windows. The app now keeps program-created windows retained for the life of the process; this small temporary memory cost is safer than fighting AppKit close-animation lifetime.
- `releaseClosedWindowLater(_:)` only removes the delegate after a delay. It intentionally does not remove the window from `retainedWindows`.
- `saveCurrentSession()` must not perform aggressive closed-window cleanup for the same reason. It only removes dead model references.
- `FileViewerWindowRegistry.restoreAdditionalSessionWindowsIfNeeded(from:)` opens saved windows after the first restored `ContentView` registers.
- `markdownMatchCount()`
- `applyMarkdownFormat(_:)`

### Important Markdown formatting implementation detail

Formatting currently depends on a native `NSTextView`, not SwiftUI `TextEditor`.

History:

1. First implementation used SwiftUI `TextEditor`.
2. Formatting buttons did not work reliably because SwiftUI hides the backing `NSTextView`, and clicking a toolbar button changes first responder / loses selection.
3. A patch attempted to remember/find the hidden text view, but the user still reported the buttons not working.
4. Latest implementation replaced `TextEditor` with a custom `NSViewRepresentable` wrapper around `NSTextView` (`MarkdownSourceEditor` in `MarkdownWorkspace.swift`).

Patrick confirmed the native-editor direction was the right one, then asked for source-editor toggles first. The source editor now uses toggle-style formatting for common commands: applying formatting to plain text and removing it when the selected text is already wrapped by that syntax.

`AppModel` still keeps a weak `lastActiveMarkdownTextView`. `MarkdownSourceEditor` calls `model.rememberMarkdownTextView(textView)` through the `onTextViewReady` callback. `applyMarkdownFormat(_:)` chooses a target text view using:

1. `NSApp.keyWindow?.firstResponder as? NSTextView`
2. `lastActiveMarkdownTextView`
3. recursive search of key window content view for a matching `NSTextView`

After formatting, it calls:

```swift
textView.window?.makeFirstResponder(textView)
updateMarkdown(textView.string)
```

Formatting behavior:

- If text is selected, wrap/transform the selected text unless it is already formatted, in which case remove that formatting.
- If the cursor selection is inside existing inline formatting, the formatter expands to include the surrounding markers and removes them. Example: selecting `word` inside `**word**` and pressing Bold changes it back to `word`.
- Preview selections can also be formatted. The preview pane is now a read-only native `NSTextView`, so `AppModel` can read the selected preview text and map it back to Markdown source before applying the same source toggle logic.
- If no text is selected, insert placeholder text.
- Bold toggles `**text**`
- Italic toggles `*text*`; it avoids mistaking bold `**text**` markers for italic markers.
- Underline toggles `<u>text</u>` because Markdown itself has no standard underline syntax.
- Heading toggles selected/current lines:
  - if every non-empty selected line is already a Markdown heading (`#` through `######`), remove the heading markers
  - otherwise normalize each non-empty selected line to `## text`
- Bullet list toggles `- ` line prefixes.
- Numbered list toggles ordered-list prefixes such as `1. ` and `2. `.
- Quote toggles `> ` line prefixes.
- Link: `[text](https://example.com)`
- Code toggles inline backticks for one-line selections; multiline code still inserts a fenced triple-backtick block.
- Insert Table inserts a three-column Markdown table template. If text is selected, it converts comma-separated selected lines into a Markdown table.
- Task List inserts an unchecked task-list template. If lines are selected, it converts each selected line into an unchecked task item.

Patrick confirmed on 2026-06-27 that bold, underline, and heading work in the source editor, then confirmed preview formatting works after the preview was switched to a selectable native text view. Treat the formatting button path as working unless a new specific bug report appears.

Implementation note:

- `AppModel.applyMarkdownFormat(_:)` now calls `markdownReplacement(for:in:selectedRange:)`, which returns the actual replacement range, replacement text, and post-format selection.
- This was needed for true toggles because removing formatting sometimes replaces a larger range than the user selected, for example removing `**` immediately outside the selected text.
- Whole-line commands still expand the original selection with `NSString.lineRange(for:)` before toggling.
- Selection math uses `NSString` lengths so the cursor behaves better with non-ASCII text than pure Swift `String.count`.
- Preview formatting uses `sourceRange(forPreviewSelection:command:in:)`.
  - For heading/list/quote-style commands, it tries to match the selected preview text against the comparable source line after removing Markdown line markers.
  - For inline commands such as bold and underline, it searches for the selected preview text in the source, then lets the normal toggle helper expand to surrounding Markdown markers.
  - Current limitation: if the exact same selected phrase appears multiple times, preview formatting may affect the first matching source occurrence. A future improvement could embed source-range metadata in the preview attributed string for perfect mapping.
  - Link formatting inserts/toggles the app's default example-link form. Smarter toggling of arbitrary existing Markdown links is a possible future polish item.

### `ContentView.swift`

Top-level UI shell.

Main pieces:

- `NavigationSplitView`
  - sidebar: `SidebarView`
  - detail: toolbar, tab bar, status bar, document body
- toolbar:
- Open button
- New button
- sidebar toggle button
  - Markdown mode control when Markdown tab is selected
  - Save / Save As buttons when Markdown tab is selected
- PDF toolbar when PDF tab is selected
- Print button when any document is selected
- search field
  - implemented as `SearchTextField`, a small AppKit `NSTextField` bridge, because SwiftUI `TextField.onSubmit` did not reliably fire Return in the toolbar on macOS
  - shows current match / total matches while searching
  - up/down buttons move to previous/next match
  - Return in the search field moves to next match
- tab bar:
  - horizontal list of open tabs
  - selected tab has accent background
  - unsaved Markdown tabs show small orange dot
  - each tab has an `xmark` close button
- status bar:
  - current file name
  - unsaved changes indicator
  - status message
  - Markdown search current/total match status
  - PDF page count
- document body:
  - `MarkdownWorkspace`
  - `PDFWorkspace`
  - `EmptyDocumentView`

Recent UI layout changes:

- The `Sidebar` label was moved above the segmented picker in `SidebarView` because it previously rendered vertically squeezed in a narrow sidebar.
- The `Markdown View` label was moved above the `Preview / Source / Split` segmented picker because it previously wrapped awkwardly as `Mark-down View`.

### `MarkdownWorkspace.swift`

Responsible for Markdown editor/preview/split view.

Modes:

- `.source`: source editor plus formatting toolbar
- `.preview`: rendered preview only
- `.split`: `HSplitView` with editor left, preview right

Current source editor:

- `MarkdownSourceEditor`, a custom `NSViewRepresentable`
- wraps `NSTextView` inside `NSScrollView`
- configured as plain text:
  - `isRichText = false`
  - disables smart quotes/dashes/text replacement
  - `allowsUndo = true`
  - monospaced system font
  - resizable horizontally and vertically

Formatting toolbar:

- Horizontal scroll view containing a visible `Format` dropdown plus icon buttons.
- The `Format` dropdown was added because Patrick is new to Markdown and asked for clearer assistance than icon-only controls. Keep it visible unless replacing it with something even clearer.
- One button per `MarkdownFormatCommand`.
- Buttons call `model.applyMarkdownFormat(command)`.
- Each command has `helpText` in `MarkdownFormatCommand`; toolbar icon buttons and dropdown items use it for help/tooltips.
- Buttons are now working in both Source and Preview selection contexts.
- Source editor buttons toggle bold, italic, underline, heading, bullet list, numbered list, quote, and inline code.
- Preview buttons map selected preview text back to Markdown source and then run the same toggle logic.
- Link insertion works from the toolbar/menu/context command; arbitrary link-toggle polish can be improved later.

Context menu:

- Same formatting commands are available through right-click context menu on the editor.
- Important implementation note: the source editor is an AppKit `NSTextView`. A SwiftUI `.contextMenu` did not reliably replace the native text-view right-click menu; the working implementation assigns a custom `NSMenu` directly to `textView.menu` inside `MarkdownSourceEditor.Coordinator.contextMenu()`. Keep this AppKit menu path if improving right-click behavior.
- The custom right-click menu lists Markdown formatting commands first, then Cut / Copy / Paste.

Markdown preview:

- Uses a lightweight block parser (`MarkdownPreviewBlock`) and a read-only selectable `NSTextView` (`MarkdownPreviewTextView`) instead of rendering the whole file as one SwiftUI `Text`.
- This was changed after the user reported that the preview flattened headings/lists/paragraphs into one strange paragraph.
- The later switch to `MarkdownPreviewTextView` was made so formatting commands can read preview selections and update the Markdown source.
- Supported block types:
  - blank line
  - heading levels 1-6
  - paragraph
  - unordered bullet
  - numbered list item
  - task list item
  - quote
  - fenced code block
  - basic Markdown table
- Inline content still uses `AttributedString(markdown:)` for simple inline formatting such as bold, italic, link, code, and strikethrough.
- Basic tables are parsed by detecting a header line plus a Markdown separator line. Preview currently renders them as aligned monospaced rows with a divider under the header. This is intentionally readable but not a rich spreadsheet-like grid.
- Task lists are parsed from `- [ ] item` / `- [x] item` style lines and render as `☐` / `☑` in preview.
- Search highlight:
  - uses `model.searchText`
  - highlights matches in preview with yellow background
  - highlights the current match with stronger orange background
  - search field/status bar shows current match and total match count
  - previous/next search buttons update `model.searchMatchIndex` and scroll the selected match into view
- Underline convenience:
  - source uses `<u>text</u>`
  - preview preprocesses this simple tag and applies underline styling manually because native Markdown parsing leaves it as literal HTML

Known limitations:

- Preview rendering is now structured but still not a full GitHub-Flavored-Markdown renderer.
- Tables and task lists now render in a basic readable form, but not as richly as a dedicated Markdown engine.
- A local parser check showed native `AttributedString(markdown:)` parses bold, italic, heading, link, list, quote, inline code, fenced code, and strikethrough into plain attributed output, but tables flatten into text and task-list checkboxes appear as text.
- Local image support is not fully implemented.
- Preview-selection formatting is text-match based. If the same selected phrase appears multiple times, it can target the first matching source occurrence rather than the visually selected occurrence.
- Link insertion works, but smart detection/removal of arbitrary existing links is not fully implemented.
- Table/task-list insertion is implemented. Richer table styling, better checkbox visuals, and more complete GitHub-Flavored-Markdown compatibility remain future Markdown preview improvements.
- The source editor is now more reliable for selection formatting, but this is still a custom bridge and may need polish for cursor positioning, undo grouping, and selection persistence.

### `PDFWorkspace.swift`

PDF support uses PDFKit.

`PDFWorkspace` wraps `PDFKitView`.

`PDFKitView`:

- `NSViewRepresentable` around `PDFView`
- display mode: `.singlePageContinuous`
- display direction: `.vertical`
- auto scales initially
- binds:
  - search text
  - page
  - page count
  - scale

PDF toolbar controls communicate through `NotificationCenter` names defined in `ContentView.swift`:

- `.pdfPreviousPage`
- `.pdfNextPage`
- `.pdfGoToPage`
- `.pdfZoomIn`
- `.pdfZoomOut`
- `.pdfFitWidth`
- `.pdfFitPage`

Crash fix already implemented:

The app previously crashed when opening/changing PDFs because PDFKit sometimes returned an invalid page index (`NSNotFound`). Code then did `index + 1`, causing arithmetic overflow.

Fix in `PDFKitView.Coordinator.syncPage()`:

```swift
let index = parent.document.index(for: currentPage)
guard index != NSNotFound,
      index >= 0,
      index < parent.document.pageCount else { return }
```

Same guard exists in `PDFThumbnailSidebar.Coordinator.pageChanged()`.

If another PDF crash happens, first check whether another PDFKit callback is producing `NSNotFound` or stale page/document references.

PDF search:

- `applySearch(_:)` uses `parent.document.findString(text, withOptions: [.caseInsensitive])`.
- Highlights results through `pdfView?.highlightedSelections`.
- Jumps to the first result.
- `PDFKitView` binds `searchMatchIndex` and `searchMatchCount` back to `AppModel`.
- Search count updates are dispatched through stored `Binding` values on the next main-queue tick. This avoids mutating SwiftUI state directly during `PDFKitView.updateNSView`, which previously prevented the toolbar from reliably showing current/total matches.
- 2026-06-29 follow-up: PDF match count is also calculated immediately in `AppModel.searchText` using the selected `PDFDocument.findString(...)`. This makes the toolbar count deterministic even if the `PDFKitView` binding callback is delayed or skipped by SwiftUI/PDFKit refresh timing.
- PDF search status text is prefixed with `PDF:` so it is visually clear that the count is coming from PDF search, e.g. `PDF: 1 of 6`.
- Previous/next search buttons update `searchMatchIndex`; `PDFKitView.Coordinator.goToSearchMatch(_:)` selects and scrolls to the requested `PDFSelection`.

### `SidebarView.swift`

Sidebar sections:

- Recent
  - list of recent documents
  - opens recent in tab
- Contents
  - for Markdown: generated from Markdown headings in the selected Markdown tab
  - Markdown headings currently display only; clicking a heading does not jump to that heading yet
  - for PDF: generated from the PDF outline/table of contents when the PDF provides outline/bookmark entries
  - PDF outline entries navigate to their destination page by posting `.pdfGoToPage`
  - PDF outline extraction checks both direct outline destinations and `PDFActionGoTo` destinations
  - PDFs without an outline show `No PDF Outline`
- Pages
  - PDF thumbnails through `PDFThumbnailSidebar`
  - clicking a thumbnail posts `.pdfGoToPage`

The segmented picker now has a separate `Sidebar` label above it to avoid the squeezed vertical text layout.

### `AppCommands.swift`

Defines app menu commands via SwiftUI `Commands`.

Focused model:

- Uses custom `FocusedValueKey` `FileViewerModelKey`.
- `ContentView` sets `.focusedSceneValue(\.fileViewerModel, model)`.

Menus:

- File/New replacement:
  - New Markdown Document
  - Open...
- Save group:
  - Save
  - Save As...
- Print replacement:
  - Print...
- View menu:
  - Toggle Sidebar
  - Markdown Preview / Source / Split
  - Fit Page / Fit Width / Zoom In / Zoom Out
- Navigate menu:
  - Previous Page
  - Next Page
- Markdown menu:
  - Bold (`Cmd+B`)
  - Italic (`Cmd+I`)
  - Underline (`Cmd+U`)
  - Heading (`Option+Cmd+H`)
  - Bullet List
  - Numbered List
  - Quote
  - Link (`Cmd+K`)
  - Code
- Help replacement:
  - Markdown Syntax Guide (`Shift+Cmd+/`)

### `MarkdownSyntaxHelp.swift`

Creates a reusable `NSWindow` containing `MarkdownSyntaxHelpView`.

`MarkdownSyntaxHelpPresenter.shared.show()`:

- Reuses existing help window if open.
- Otherwise creates a 760 x 680 resizable window.
- Uses `NSHostingView(rootView: MarkdownSyntaxHelpView())`.

Guide content includes:

- Heading
- Bold
- Italic
- Bold + Italic
- Strikethrough
- Link
- Image
- Bullet list
- Numbered list
- Task list
- Quote
- Inline code
- Code block
- Table
- Horizontal rule

## 4. Recent commit history and why it matters

Recent commits on `main`:

- `12bb968` — `Guard invalid PDF page indexes`
  - Fixed PDFKit `NSNotFound + 1` arithmetic-overflow crash.
- `20f8625` — `Add document tabs and Markdown help`
  - Added multiple document tabs.
  - Added per-tab state.
  - Added Help menu Markdown Syntax Guide.
  - Added Markdown preview search highlighting/match count.
- `23d455b` — `Improve markdown controls and formatting`
  - Improved sidebar/Markdown View labels.
  - Added Markdown toolbar/right-click/menu formatting commands.
  - Still used SwiftUI `TextEditor`, which user reported did not work.
- `3b5badc` — `Fix markdown formatting buttons`
  - Tried to remember/find hidden SwiftUI `TextEditor` backing text view.
  - User reported the buttons still did not work.
- `1b802ed` — `Use native Markdown source editor`
  - Replaced SwiftUI `TextEditor` with custom `NSTextView`.
  - Built and pushed.
  - Later confirmed as the correct direction after follow-up fixes.
- `c2f7da5` — `Add source editor formatting toggles`
  - Added toggle behavior for source editor formatting commands.
  - User confirmed bold, underline, and heading worked.
- `28ebdbb` — `Enable markdown formatting from preview selection`
  - Replaced preview rendering with selectable read-only `NSTextView`.
  - Added preview-selection formatting that maps selected preview text back to Markdown source.
  - User confirmed preview formatting works.
- `9c479b3` — `Allow multiple document copies`
  - Removed the duplicate-URL guard in `open(url:)`.
  - Opening the same PDF/Markdown more than once now creates multiple tabs/copies.
  - Drag-and-drop now opens every dropped file instead of only the first provider.
  - Added `FileViewerAppDelegate` for macOS Open With/external file-open events.
  - Package script now registers document types for PDF, Markdown, and text files in `Info.plist`.
- `17c35e1` — `Open Finder documents in separate windows`
  - Replaced the global external-open notification with `FileViewerWindowRegistry`.
  - Finder/Open With external opens now create/reuse one target window only.
  - This fixes the bug where opening document B from Finder made every open FileViewer window show document B.
  - `ContentView` now accepts `initialURLs` and constructs its own `AppModel(opening:)`.
  - `AppModel` now has `canAcceptExternalOpenInCurrentWindow` so the registry can reuse an empty startup window.
- `c36e3aa` — `Allow narrower markdown windows`
  - Lowered the main app minimum width to support side-by-side Markdown document comparison.
  - Made Finder-created document windows default to `760 x 720` with minimum size `520 x 620`.
  - Reduced Markdown split-pane minimum widths.
  - Made the top toolbar more compact so Markdown windows can shrink more like Preview/PDF windows.
- `aee0801` — `Confirm before closing unsaved markdown`
  - Added Save / Don’t Save / Cancel prompts for unsaved Markdown tab close.
  - Added window-close protection through `WindowCloseDelegate`.
  - Added tab-specific save helpers so closing a non-selected unsaved tab saves the correct Markdown document.
  - Untitled unsaved documents route through Save As; cancelling Save As cancels the close.
- `8ad7966` — `Add markdown table and task list helpers`
  - Added Insert Table and Task List Markdown format commands.
  - The commands appear in the toolbar, right-click menu, and Markdown app menu.
  - Table inserts a template or converts comma-separated selected lines.
  - Task List inserts a template or converts selected lines to unchecked task items.
- 2026-06-28 — Markdown table preview and custom source right-click menu
  - Added lightweight table parsing/rendering in Markdown preview. It detects a normal Markdown header/separator table and displays aligned monospaced columns with a header divider.
  - Added lightweight task-list preview rendering for `- [ ]` and `- [x]` items.
  - Replaced the SwiftUI `.contextMenu` on the source editor with a custom AppKit `NSMenu` assigned directly to the underlying `NSTextView`, because Patrick saw the default macOS Font/Spelling menu instead of Markdown commands.
  - The new source-editor right-click menu shows Markdown commands first, then Cut / Copy / Paste.
- 2026-06-29 — Search navigation regression fixes
  - Replaced the toolbar search `TextField` with native `SearchTextField` so pressing Return reliably advances to the next Markdown/PDF search match.
  - Changed PDF search result count updates to write back through `Binding` values asynchronously after PDFKit finishes finding selections, so the toolbar shows current/total PDF matches.
  - Follow-up fix after Patrick confirmed PDF count was still missing: `AppModel.searchText` now computes PDF match count directly from the open PDF document, and PDF status text displays with a `PDF:` prefix.

This handoff document itself should be committed after creation.

## 5. Current user-visible state

Expected after latest build:

- App launches from:

```text
/Users/patrickshi/Documents/Codex/FileViewer/build/FileViewer.app
```

- Opening multiple files from inside a window can create tabs in that window.
- Opening the same PDF/Markdown file more than once should create another copy, not jump to an existing tab.
- Dragging multiple files onto the app should open each supported file as a tab.
- Finder / Open With file-open events should open in a separate window when existing windows already contain documents.
- Opening document A from Finder, then document B from Finder, should leave the A window showing A and create/show a B window showing B.
- Markdown tabs should show `Preview / Source / Split`.
- In Source or Split mode, the source editor should appear on the left/source pane with a formatting toolbar above it.
- Selecting text and pressing Bold should wrap selected text in `**`; pressing Bold again on already-bold text should remove the markers.
- If no text is selected and Bold is pressed, placeholder `**bold text**` should be inserted.
- Selecting text in Preview and pressing Bold/Underline/Heading should update the Markdown source and refresh the preview.
- Preview should update as text changes.
- Search should highlight Markdown preview matches and show match count.
- PDF search should highlight PDF matches and jump to the first.

Patrick verified on 2026-06-27 that source formatting and preview formatting work. If a future formatting bug appears, do not return to the old `TextEditor` approach. Debug the native `NSTextView` wrappers directly.

## 6. Known issues / likely next bugs

### 6.1 Formatting button regression checks

Recommended manual test:

1. Open a Markdown file.
2. Switch to Source mode.
3. Type `hello world`.
4. Select `hello`.
5. Click Bold toolbar button.
6. Expected source: `**hello** world`.
7. Undo should work.
8. Select multiple lines.
9. Click Bullet List.
10. Expected: each selected line gets `- ` prefix.
11. Try same in Split mode.
12. Try right-click menu.
13. Try app menu `Markdown > Bold`.
14. Try keyboard shortcut `Cmd+B`.
15. Switch to Preview mode.
16. Select rendered text and click Bold / Underline / Heading.
17. Expected: the Markdown source changes and the preview refreshes.
18. In Split mode, test both source-pane and preview-pane selections.

If toolbar works but keyboard/menu does not:

- Check `FocusedValue` propagation in `ContentView`.
- Check whether menu command can see `model?.isMarkdownDocument == true`.

If none works:

- Put temporary logging/breakpoint in `AppModel.applyMarkdownFormat(_:)`.
- Confirm `lastActiveMarkdownTextView` is non-nil.
- Confirm the text view string matches `currentMarkdownText`.
- Confirm `textView.insertText(_:replacementRange:)` is called.

If insertion happens but UI does not update:

- Check `textDidChange(_:)` in `MarkdownSourceEditor.Coordinator`.
- Check `updateMarkdown(_:)` updates selected tab.
- Check `document.text` passed to `MarkdownWorkspace` refreshes.

### 6.2 Unsaved close confirmation is implemented

Closing a tab or window with unsaved Markdown changes now prompts before data can be lost.

Implemented behavior:

- Tab close:
  - `ContentView` calls `model.requestCloseTab(tab.id)`.
  - If the tab is a Markdown document with unsaved changes, `AppModel` shows an `NSAlert`:
    - Save
    - Don’t Save
    - Cancel
  - Save writes the specific tab, not merely the currently selected tab.
  - Untitled documents route through `NSSavePanel`; cancelling Save As cancels the close.
  - Save failures keep the tab open and show an error alert.
- Window close:
  - `FileViewerWindowRegistry` installs `WindowCloseDelegate` on registered windows.
  - `windowShouldClose(_:)` calls `model.canCloseAllDocuments()`.
  - Each unsaved Markdown tab in that window is checked.
  - Cancel on any prompt cancels the whole window close.

Implementation detail:

- `saveMarkdown()` still saves the selected tab for normal menu/toolbar Save.
- Close-confirmation saving uses private tab-index-specific helpers (`saveMarkdownTab(at:)`, `saveMarkdownTabAs(at:)`) so closing a non-selected tab saves the correct document.

### 6.3 Session persistence for open tabs/windows

File-backed tabs/windows restore after app restart. PDF page/zoom state is restored. Markdown Source/Preview scroll state is restored for file-backed Markdown documents. Unsaved Untitled Markdown documents are intentionally not restored.

### 6.4 Markdown preview quality is limited

`AttributedString(markdown:)` is convenient but not a complete rich Markdown renderer. Known future improvements:

- Richer table styling beyond the current aligned monospaced preview
- More polished task-list checkbox rendering beyond the current `☐` / `☑` preview
- Local image rendering
- Code block styling / copy button
- Mermaid diagrams
- Math rendering
- HTML export / PDF export

### 6.5 Markdown source search does not highlight source pane

Search highlights the preview and shows match count. It does not highlight inside the source editor. If implementing this, use native `NSTextView` APIs (`layoutManager`, temporary attributes, selected ranges, or find panel integration).

### 6.6 Markdown table of contents does not jump

The Contents sidebar lists Markdown headings but clicking a heading does not scroll source or preview to that heading.

### 6.7 PDF search is basic

PDF search:

- highlights all matches
- jumps to first match
- shows current result and total results in the shared search field
- supports previous/next result navigation

Missing:

- clearing search highlights more predictably
- search result sidebar/list

### 6.8 PDF outline support is basic

Implemented in `SidebarView.contentsList` and `AppModel.extractPDFOutline(from:)`.

Behavior:

- The Contents sidebar shows PDF outline/table-of-contents entries when `PDFDocument.outlineRoot` is available.
- The outline tree is flattened into `PDFOutlineEntry` rows with indentation based on outline level.
- Clicking an entry with a destination page posts `.pdfGoToPage`.
- Entries without a destination page are displayed but disabled.
- The extraction handles both `PDFOutline.destination` and `PDFActionGoTo.destination`.
- PDFs without an outline show `No PDF Outline`.

Known limitations:

- There is no collapsible PDF outline tree yet; it is a flat indented list.
- It only navigates to a page, not an exact coordinate within the page.
- Some unusual PDFs may encode outline actions differently; if a PDF shows disabled entries even though Preview can jump from them, inspect the `PDFOutline.action` type and add support for that action.

### 6.9 App lifecycle and document model

This app is a custom tabbed viewer, not a macOS `DocumentGroup` app. That makes tab control simpler, but it means native document lifecycle features are manual:

- open external files
- close confirmation
- save prompts
- restoring state
- opening file from Finder with app association

## 7. Build / release checklist for future changes

For normal changes:

```bash
cd /Users/patrickshi/Documents/Codex/FileViewer
swift build
./scripts/package_app.sh
git status --short
```

Then manually test the app bundle:

```text
/Users/patrickshi/Documents/Codex/FileViewer/build/FileViewer.app
```

If acceptable:

```bash
git add <changed files>
git commit -m "<clear message>"
git push
```

Patrick has generally wanted commits/pushes when work is complete.

## 8. Repository hygiene

The repo contains build outputs and older prototype artifacts. Current source of truth:

- Swift app: `Sources/FileViewer`
- Swift package: `Package.swift`
- packaging: `scripts/package_app.sh`
- documentation:
  - `README.md`
  - `docs/requirements-and-specification.md`
  - `docs/mvp-task-list.md`
  - `HANDOFF.md`

Do not delete the older React/Vite files casually. They may be historical artifacts, and removing them would be a separate cleanup decision.

## 9. User preferences / communication context

Patrick prefers:

- practical, user-facing UI improvements
- non-technical explanations unless debugging requires detail
- app bundle rebuilt after code changes
- commits and pushes when a meaningful unit of work is done
- detailed handoff documentation when context may run out

Patrick is newer to Markdown and wants the app to teach/assist him. The Help guide and formatting toolbar were added for this reason. Continue leaning toward UI affordances over expecting the user to remember syntax.

## 10. Suggested next steps

Recommended order:

1. Improve Markdown preview rendering if Patrick relies heavily on richer tables/checklists.
2. Add remaining Markdown formatting polish:
   - smarter link editing/toggling for arbitrary existing Markdown links
   - more precise preview-to-source mapping when repeated phrases exist
3. Add restore polish if needed:
   - restore exact window positions/sizes
   - optionally restore search text if Patrick later wants it
4. Add repeatable sample files/tests for PDF outline, PDF search counts, Markdown formatting, and multi-window restore.

## 11. Quick mental model for future agents

Think of the app as:

```text
AppModel
└── tabs: [DocumentTab]
    ├── document: ViewerDocument
    │   ├── MarkdownDocument(text, savedText, url)
    │   └── PDFViewerDocument(PDFDocument, url)
    ├── searchText
    ├── pdfPage
    ├── pdfPageCount
    └── pdfScale

ContentView
├── SidebarView
├── toolbar
├── tab bar
├── status bar
└── selected document workspace
    ├── MarkdownWorkspace
    │   ├── MarkdownSourceEditor(NSTextView)
    │   └── AttributedString markdown preview
    └── PDFWorkspace
        └── PDFKitView(PDFView)
```

Most bugs will be caused by one of three state boundaries:

1. selected tab vs global app state
2. SwiftUI state vs AppKit wrapped view state
3. PDFKit callbacks referencing stale page/document objects

When debugging, first identify which boundary is involved.
