# FileViewer Handoff

Last updated: 2026-08-22
Active repo: `/Users/patrickshi/Documents/Codex/FileViewer`  
GitHub remote: `https://github.com/timetochilltoo/FileViewer.git`  
Current branch at time of writing: `feature/ai-assistant`
Current committed baseline before this checkpoint: `59670bb` (`Update handoff baseline`)

> Historical debugging and commit notes below are preserved because they explain prior regressions. Where an older note conflicts with the **Current implementation** sections, the current sections win.

## 1. Project purpose

FileViewer is Patrick's local-first native macOS document viewer/editor. It currently targets macOS Tahoe / macOS 26 only. Compatibility with older macOS versions is intentionally not required.

The app is intended to be a lightweight daily document workspace for:

- Markdown notes (`.md`, `.markdown`)
- PDFs (`.pdf`)
- multiple open documents through tabs
- simple Markdown editing, preview, search, and formatting assistance
- creating new unsaved Markdown documents
- printing PDFs and Markdown source text
- PDF reading, page navigation, zoom, thumbnails, search, view/page rotation, annotations, fillable forms, and annotation reports
- provider-configurable local/remote AI assistance with explicit document-transfer approval

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

Automated tests are present under `Tests/FileViewerTests` and are run with:

```bash
swift test
```

They cover document safety and core AI context/profile behavior without connecting to a real AI provider. They do not replace manual PDFKit/UI regression testing. Standard verification is:

- `swift build`
- `./scripts/package_app.sh`
- user manual testing with real Markdown/PDF files
- crash-log-driven fixes and focused manual PDF/Markdown/AI regression testing

## 3. High-level architecture

### SwiftUI app structure

```text
Sources/FileViewer/
├── AppCommands.swift
├── ContentView.swift
├── DocumentModel.swift
├── FileViewerApp.swift
├── FileViewerWindowRegistry.swift
├── AIAssistant.swift
├── AIAssistantPanel.swift
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
- A file already open in any FileViewer window is selected and brought forward instead of being opened as another writable instance. This is intentional data-loss protection: two independent `PDFDocument` instances for one URL can otherwise overwrite each other.
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
  - Selects the existing tab if the same URL is already open in the same model, rather than creating another writable PDF/Markdown instance.
  - The window registry also brings a document already open in another FileViewer window forward instead of duplicating it.
  - This protects against two independent writable `PDFDocument` instances overwriting one another.
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
- Restores saved window size/position through optional `SavedSessionWindow.frameString` when possible.
- Session restore is delayed briefly by `FileViewerWindowRegistry.scheduleSessionRestoreIfPossible(using:)`.
- If the app receives Finder/Open With URLs during launch, `suppressSessionRestore` is set and old session windows are not restored. This avoids the confusing case where opening `A.pdf` also reopens previously closed/restored `D.pdf`, `E.pdf`, and `G.pdf`.
- Skips unsaved Untitled Markdown documents because there is no safe file path to reopen.
- Skips missing files silently.
- Does not restore search text by design; search text is session-only and would be annoying to revive unexpectedly.
- Restores PDF page and zoom via saved `pdfPage` / `pdfScale`.
- Also stores per-file PDF page/zoom in `UserDefaults` key `FileViewer.pdf.lastStates`. This is separate from session restore. It lets `A.pdf` reopen to its previous page even after its tab/window was closed and removed from the session snapshot.
- Also stores per-file Markdown Source/Preview vertical scroll positions and first-visible text locations in `UserDefaults` key `FileViewer.markdown.lastStates`. This is separate from session restore and lets a Markdown file reopen near the previous reading/editing position after its tab/window was closed.
- Markdown Source and Preview scroll positions are tracked separately because the two panes can be at different vertical offsets.
- PDF state is saved when `pdfPage` / `pdfScale` changes, when session snapshots are made, before opening another file, before switching tabs, and before closing a tab/window.
- Markdown scroll state is kept in memory while scrolling and written during natural save points: session snapshot, opening another file, switching tabs, and closing a tab/window. It intentionally does not write to `UserDefaults` on every tiny scroll movement.
- Important Markdown scroll fix: closing a whole window goes through `canCloseAllDocuments()` / `windowShouldClose`, not `closeTab(at:)`. Therefore `canCloseAllDocuments()` now calls `saveDocumentStates()` after syncing visible state, otherwise Markdown scroll state could remain only in memory and be lost when the window model was removed.
- `pdfSyncCurrentState` notification asks the visible `PDFKitView` to synchronously push its current page/zoom back into `AppModel` before the model saves state. This covers the sequence: open `A.pdf`, go to page 67, open `B.pdf`, switch back to `A.pdf`, close, then reopen `A.pdf`.
- `markdownSyncCurrentState` notification asks visible Markdown Source/Preview scroll views to push their current vertical offsets back into `AppModel` before the model saves state.
- Important Markdown restore fix: Source/Preview scroll restoration can happen before NSTextView layout has calculated the full content height. `restoreInitialScrollIfNeeded()` now retries briefly when the saved offset is non-zero but the scroll view still reports no scrollable height.
- Important Markdown accuracy fix: pixel-only scroll restore can land on the wrong area after Markdown reflows due to window width, preview/source mode, or font/layout changes. Markdown panes now also save the first visible character location and prefer that when restoring; the older pixel scroll value remains as fallback for saved states that do not yet have a visible-location value. The visible-location implementation must convert between `NSScrollView` document coordinates and `NSTextView.textContainerOrigin`; using `scrollRangeToVisible` alone was not accurate enough because it only guarantees the target is visible somewhere, not aligned near the prior top-of-view position.
- `FileViewerWindowRegistry.saveCurrentSession()` collects live window model snapshots and writes them.
- `FileViewerWindowRegistry` keeps weak model-to-window references so session snapshots can include each window frame. Old saved sessions without `frameString` still load and simply center the window.
- Closing a window removes that window's model from the registry and resaves the session, so closed windows should not come back on next launch.
- Important crash/memory fix: do not release program-created `NSWindow` immediately inside `windowWillClose`. A delayed close callback keeps the window alive through AppKit's close animation, then removes it from `retainedWindows`. This avoids the earlier open/close crash without retaining every closed window for the life of the process.
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
- sidebar toggle button
  - Markdown mode control when Markdown tab is selected
- PDF toolbar when PDF tab is selected
- search field
  - implemented as `SearchTextField`, a small AppKit `NSTextField` bridge, because SwiftUI `TextField.onSubmit` did not reliably fire Return in the toolbar on macOS
  - shows current match / total matches while searching
  - up/down buttons move to previous/next match
- 2026-07-09 toolbar simplification:
  - Removed New File, Save, Save As, and Print icons from the toolbar because the PDF annotation toolbar became too crowded on Patrick's screen.
  - The functions still exist in menus and shortcuts:
    - New Markdown Document
    - Save / Command-S
    - Save As / Command-Shift-S
    - Print / Command-P
  - Do not re-add these as toolbar icons unless the toolbar layout is redesigned with overflow/adaptive grouping.
  - Return in the search field moves to next match

PDF rotation:

- The PDF toolbar has a compact **Rotate** menu (the `rotate.right` icon), and the same commands are available from **View** and **PDF** menus.
- 2026-08-01 toolbar-layout hardening: every PDF navigation/action icon has a 32×28-point visual and hit area; `Rotate` and `Annotate` now use icon-only menu labels, and `PDFToolbar` has layout priority plus a fixed horizontal intrinsic size. This prevents macOS from compressing multiple icons into the same apparent space. Keep any future PDF-toolbar additions inside this compact-menu approach rather than adding text labels.
- **Rotate View Left/Right/180°** is intentionally non-destructive. It changes the in-memory display of every page for the active tab, tracks the temporary angle in `DocumentTab.pdfViewRotation`, keeps the current page/zoom/visible position where PDFKit permits, and does not mark the PDF dirty.
- PDFKit does not expose a separate visual rotation transform, so view rotation temporarily changes each in-memory `PDFPage.rotation`. `PDFDocument.fileViewerPersistedCopy(removingViewRotation:)` creates a separate serialized copy with that temporary rotation subtracted. Both normal Save and Save As use this copy. This is the critical safety boundary: saving annotations, form edits, or a permanent page rotation must never accidentally save the reading-only view rotation.
- **Rotate Current Page** and **Rotate All Pages** are real page edits. They adjust the selected page or every page in memory, set the historical general PDF dirty flag `pdfHasUnsavedAnnotations`, and require Save or Save As to persist. The status message explicitly says that the page rotation is permanent only after saving.
- When a PDF contains both a temporary view rotation and a permanent page rotation, the next Save/Save As preserves only the permanent component. To discard an unsaved permanent rotation, close the PDF without saving; that also discards any other unsaved PDF changes in the normal way.
- Implemented directions are left (270°), right (90°), and 180°. The Display menu keyboard shortcuts are Command-Option-Left and Command-Option-Right for view rotation. Permanent page rotation is deliberately menu-driven to reduce accidental modification.
- `PDFWorkspace.Coordinator.refreshPageRotation(_:)` temporarily detaches and restores the current `PDFDocument` to make PDFKit recompute page geometry, then reapplies the active page, scale, and visible origin. Commands are URL-targeted using the established notification mechanism.

Rotation regression test:

- `DocumentSafetyTests.testPersistedPDFCopyRemovesOnlyTemporaryViewRotation` creates a valid one-page PDF, simulates a permanent 90° rotation plus a temporary 90° view rotation, and confirms the serialized copy is 90° while the live document remains 180°. This verifies the non-destructive save boundary.
- tab bar:
  - horizontal list of open tabs
  - selected tab has accent background
  - unsaved Markdown tabs show small orange dot
  - each tab has an `xmark` close button
- status bar:
  - current file name
  - unsaved changes indicator
  - status message
  - Markdown search current/total match status (the count is based on raw Markdown source text)
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

- `.pdfFirstPage`
- `.pdfPreviousPage`
- `.pdfNextPage`
- `.pdfLastPage`
- `.pdfGoToPage`
- `.pdfZoomIn`
- `.pdfZoomOut`
- `.pdfFitWidth`
- `.pdfFitPage`
- `.pdfApplyAnnotation`
- `.pdfAnnotationDidChange`

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
- Search highlighting and search navigation are intentionally separate.
- `DocumentTab.searchNavigationRequestID` changes only when the search text changes or the user explicitly requests previous/next/Return search navigation.
- `PDFKitView.Coordinator.applySearch(_:)` rebuilds the PDFKit highlighted selections and match count, but no longer scrolls the PDF by itself.
- `PDFKitView.Coordinator.goToSearchMatch(_:requestID:)` scrolls only when it receives a new navigation request ID. This prevents normal SwiftUI/PDFKit refreshes, annotation redraws, resizing, or manual scrolling from pulling the user back to the active search hit.
- `PDFKitView` binds `searchMatchIndex` and `searchMatchCount` back to `AppModel`.
- Search count updates are dispatched through stored `Binding` values on the next main-queue tick. This avoids mutating SwiftUI state directly during `PDFKitView.updateNSView`, which previously prevented the toolbar from reliably showing current/total matches.
- 2026-06-29 follow-up: PDF match count is also calculated immediately in `AppModel.searchText` using the selected `PDFDocument.findString(...)`. This makes the toolbar count deterministic even if the `PDFKitView` binding callback is delayed or skipped by SwiftUI/PDFKit refresh timing.
- PDF search status text is prefixed with `PDF:` so it is visually clear that the count is coming from PDF search, e.g. `PDF: 1 of 6`.
- Previous/next search buttons update `searchMatchIndex` and the search navigation request ID; `PDFKitView.Coordinator.goToSearchMatch(_:requestID:)` selects and scrolls to the requested `PDFSelection`.

PDF annotations and fillable forms:

- Implemented on branch `feature/pdf-annotation`.
- User flow:
  1. Open a PDF.
  2. Select text in the PDF view.
  3. Optionally choose an annotation color from the PDF toolbar color picker.
  4. Click Highlight, Underline, or Strikeout in the PDF toolbar, or use the PDF menu.
  5. The selected text receives a real PDFKit annotation.
  6. The tab/window is marked as having unsaved PDF changes.
  7. Use Command-S, File > Save, or PDF > Save PDF Changes to embed the annotation in the PDF file.
  8. To remove text markup, select the marked text and use Remove Markup from Selection / the eraser toolbar button.
  9. To add a sticky note, click Add Sticky Note, enter the note text, then save the PDF.
  10. To add visible page text, click Add Text Box, enter the text, then save the PDF.
  11. To add a rectangle or oval, click the matching toolbar button, then save the PDF.
  12. To add a line or arrow, click Line or Arrow, drag on the PDF from start to end, then save the PDF.
  13. To draw freehand ink, click Pen Drawing Mode, drag on the PDF, release to create the ink annotation, then save the PDF.
  14. To move a sticky note, text box, rectangle, oval, line, arrow, or ink annotation, turn on Move Annotation mode, drag the annotation, then save the PDF.
  15. To edit a sticky note or text box, turn on Edit Annotation mode, click the annotation, update the text, then save the PDF.
  16. To delete a sticky note, text box, rectangle, oval, line, arrow, or ink annotation, turn on Delete Annotation mode, click the annotation, confirm, then save the PDF.
  17. To undo/redo recent annotation changes, use the PDF toolbar undo/redo buttons or PDF > Undo/Redo PDF Annotation Change.
  18. To review annotations, switch the left sidebar to `Notes`. The list shows supported PDF annotations with type, page number, and note/text summary where available. Clicking a row jumps the PDF view to that annotation.
  19. Use the `Notes` filter dropdown to show All, Markup, Notes, Text Boxes, Shapes, or Ink.
  20. Use the export button in the `Notes` sidebar or PDF > Export Annotation Summary to save a Markdown report of the PDF annotations.
  21. To rotate only the current reading view, choose Rotate > Rotate View Left, Right, or 180°. It is not saved and does not modify the original PDF.
  22. To rotate actual PDF pages, choose Rotate > Rotate Current Page or Rotate All Pages, choose a direction, then use Save or Save As. Close without saving to discard the page rotation.
- Supported annotation types:
  - highlight: `PDFAnnotationSubtype.highlight`
  - underline: `PDFAnnotationSubtype.underline`
  - strikeout: `PDFAnnotationSubtype.strikeOut`
- Implementation details:
  - `PDFAnnotationKind` and `PDFAnnotationCommand` live in `DocumentModel.swift`.
  - `AppModel.pdfAnnotationColor` stores the SwiftUI color selected in the toolbar. `AppModel.pdfAnnotationNSColor` bridges it to `NSColor` for PDFKit.
  - `PDFToolbar.postAnnotation(_:)` posts `.pdfApplyAnnotation` with the selected PDF URL, annotation kind, and current annotation color.
  - The PDF toolbar color picker affects newly-created annotations and existing annotations recolored through Recolor Annotation mode.
  - `AppModel.resetPDFAnnotationColor()` resets the annotation color to yellow and is exposed from the toolbar reset button and PDF menu.
  - `AppModel.isPDFAnnotationRecolorModeEnabled` stores Recolor Annotation mode. Turning it on turns off Move, Delete, Edit, and line/arrow drawing modes. It is toggled from the toolbar paint-palette button or PDF > Recolor Annotation Mode.
  - `PDFKitView.Coordinator.applyAnnotation(_:)` checks that `command.url == parent.documentURL` before modifying the PDF. This protects multi-window use.
  - Annotation bounds come from `PDFSelection.selectionsByLine()` and `bounds(for:)`, so multi-line selected text becomes one annotation per selected line/page.
  - Text markup applies the selected color with alpha adjusted by type: highlight uses 55% opacity, underline/strikeout use 85%.
  - `PDFKitView.Coordinator.removeAnnotationsInSelection(_:)` removes only text-markup annotations whose bounds intersect the selected text bounds.
  - The remove command is intentionally scoped to `highlight`, `underline`, and `strikeOut` annotation types. It does not try to delete arbitrary notes/shapes yet.
  - Eraser limitation: it removes the whole overlapping annotation. If 10 words were highlighted as one annotation and the user selects 2 words inside it, the whole 10-word markup is removed. Partial erasing would require creating smaller annotations or splitting annotation geometry.
  - `PDFKitView.Coordinator.addStickyNote(_:)` asks for note text with an `NSAlert` and creates a `.text` PDF annotation.
  - Sticky note placement: if text is selected, the note is placed near the selected text bounds; otherwise it is placed near the center of the current visible page area.
  - Sticky notes use the selected annotation color with high opacity and the standard PDF note icon (`annotation.iconType = .note`).
  - 2026-07-05 follow-up: PDFKit keeps the native sticky-note icon visually small even when its bounds are enlarged, so do not promise a visibly larger icon. The note is now created with a 44×44 point bounds rectangle and `MovableAnnotationPDFView.annotationHit(for:matching:)` uses a larger 20-point hit padding for sticky notes in FileViewer's Move/Edit/Delete/Recolor modes. If Patrick later wants a visibly larger note marker, implement it as a custom visible text/shape annotation rather than native `.text`.
  - `PDFKitView.Coordinator.addTextBox(_:)` asks for text with an `NSAlert` and creates a `.freeText` PDF annotation.
  - Text box placement: if text is selected, the box is placed below the selected text; otherwise it is placed near the center of the current visible page area.
  - Text boxes use the selected annotation color as a translucent background.
  - 2026-07-01 fix: sticky note/text box creation now clamps the annotation rectangle inside the PDF page bounds. Before this, adding a text box below selected text near the bottom of a page could create it off-page, making it look like the user needed to retry several times.
  - `PDFShapeAnnotationKind` and `PDFShapeAnnotationCommand` live in `DocumentModel.swift`.
  - `PDFAnnotationStrokeWidth` lives in `DocumentModel.swift` and currently offers `Thin` = 1 pt, `Medium` = 2 pt, and `Thick` = 4 pt.
  - `AppModel.pdfAnnotationStrokeWidth` stores the current stroke width. The compact `Annotate` menu exposes color, stroke width, and reset-color controls.
  - Rectangle/oval shape creation posts `.pdfAddShapeAnnotation`. The coordinator creates real PDFKit `.square` or `.circle` annotations.
  - Line/arrow toolbar buttons call `AppModel.beginPDFLineDrawingMode(_:)`, which stores `.line` or `.arrow` in `AppModel.pdfLineDrawingMode`, turns off move/delete/edit modes, and tells the user to drag on the PDF.
  - `PDFKitView` passes `pdfLineDrawingMode` into `MovableAnnotationPDFView`. The custom PDF view intercepts mouse down/up while the mode is active, converts the drag start/end to PDF page coordinates, creates a `.line` annotation, marks the PDF dirty, and clears the drawing mode after release.
  - Arrow annotations are PDFKit line annotations with `endLineStyle = .closedArrow`; plain lines use no line ending.
  - Pen Drawing Mode is stored in `AppModel.isPDFInkDrawingModeEnabled`. Turning it on turns off move, delete, edit, recolor, and line/arrow drawing modes.
  - `PDFKitView` passes `isPDFInkDrawingModeEnabled` into `MovableAnnotationPDFView`. The custom PDF view captures mouse drag points in PDF page coordinates, draws a temporary live preview stroke during the drag, creates a real PDFKit `.ink` annotation on mouse release, marks the PDF dirty, and keeps the ink as a normal embedded PDF annotation.
  - Shape/line/arrow/ink annotations use the selected annotation stroke width. The existing Move, Delete, and Recolor modes can target ink annotations.
  - Live ink preview is drawn by a transparent `InkPreviewView` overlay added above the PDF view during the drag. The captured PDF page points are converted back to view coordinates for the overlay. The preview is not saved; it disappears when the real `.ink` annotation is added on mouse release.
  - Live ink preview uses the selected stroke width so the user sees the same width while dragging and after the real PDF annotation is created.
  - 2026-07-04 fix: `InkPreviewView` must use the normal unflipped AppKit coordinate system. A flipped overlay mirrored the temporary stroke vertically, so drawing near the bottom of a page showed a matching preview near the top.
  - Rectangle/oval placement: if PDF text is selected, the shape is placed around the selected bounds with padding. Otherwise it is placed near the center of the visible page. Rectangle/oval shapes have a fixed default size when no selection is available.
  - Line/arrow placement: the user now drags from start point to end point. This replaced the earlier fixed diagonal line/arrow behavior.
  - Shapes use the selected annotation color as a strong border plus a light transparent fill, so marked table cells or document areas remain readable.
  - `MovableAnnotationPDFView` subclasses `PDFView` to support sticky-note, free-text-box, rectangle, oval, line, arrow, and ink dragging when `isNoteMoveModeEnabled` is true. Normal PDF mouse handling is left alone when the mode is off.
  - Line/arrow endpoint adjustment is also handled in Move Annotation mode. If the click is close to a line annotation's start or end point, the drag moves only that endpoint. If the click is on the body/bounds instead, the whole line/arrow moves.
  - Text box and rectangle/oval resizing is also handled in Move Annotation mode. If the click is close to a text box/shape edge or corner, the drag resizes that side/corner. If the click is inside the annotation but not near an edge, the whole annotation moves.
  - Move Annotation mode shows a transparent `ResizeHandleOverlayView` above the PDF. It draws small blue/white handles around resizable text boxes, rectangles, and ovals, plus endpoint handles for lines/arrows. These handles are UI-only and are not saved into the PDF.
  - 2026-07-04 crash fix: overlays must not be repeatedly removed/re-added from SwiftUI/PDFKit layout refresh paths. That caused an AppKit constraint/layout recursion crash when clicking after handles were introduced. `updateNSView` now schedules handle refresh on the next main-loop tick, and the ink/handle overlays are hidden/shown instead of constantly removed/reinserted.
  - Recolor Annotation mode is handled in `MovableAnnotationPDFView.mouseDown(with:)`. It targets FileViewer-supported annotation types: highlight, underline, strikeout, sticky note, free text box, rectangle, oval, line, and arrow. It applies the currently selected toolbar color using type-appropriate opacity/fill rules and marks the PDF dirty.
  - `AppModel.isPDFNoteMoveModeEnabled` stores the mode. It is toggled from the toolbar hand button or PDF > Move Annotation Mode, and disabled when switching away from PDF content. The internal name still says “Note” for historical reasons.
  - `AppModel.isPDFAnnotationEditModeEnabled` stores Edit Annotation mode. Turning it on turns off Move and Delete modes. It is toggled from the toolbar pencil button or PDF > Edit Annotation Mode.
  - Edit Annotation mode is handled in `MovableAnnotationPDFView.mouseDown(with:)` before delete/move logic. It only targets `.text` sticky notes and `.freeText` text boxes, opens a small text-entry alert seeded with the existing annotation contents, updates `annotation.contents`, redraws the PDF view, and posts the dirty-state callback.
  - `AppModel.isPDFAnnotationDeleteModeEnabled` stores Delete Annotation mode. Turning it on turns off Move and Edit modes.
  - Delete Annotation mode is handled in `MovableAnnotationPDFView.mouseDown(with:)`. It targets `.text` sticky notes, `.freeText` text boxes, `.square` rectangles, `.circle` ovals, and `.line` line/arrow annotations, shows a confirmation alert, removes the annotation from its page, and posts the same dirty-state callback used by moves.
  - After a successful annotation, `PDFKitView` posts `.pdfAnnotationDidChange` with the PDF URL.
  - `ContentView` receives `.pdfAnnotationDidChange` and calls `model.markPDFAnnotationsChanged(for:)`.
  - PDF annotation undo/redo is now hybrid:
    - Newly-created annotation objects are undone/redone object-by-object. This path is used for text markup annotations, sticky notes, text boxes, rectangle/oval shapes, line/arrow shapes, and freehand ink. `PDFKitView.Coordinator.recordAddedAnnotations(_:)` posts `.pdfAnnotationDidAddObjects`, `ContentView` passes the object list into `AppModel.recordPDFAnnotationObjectChange(_:)`, and `AppModel.undoPDFAnnotation()` removes/re-adds the exact `PDFAnnotation` instances from their original `PDFPage`.
    - Mutating existing annotations still uses the snapshot fallback. Before move, resize, recolor, edit, delete, or erase operations, `PDFKitView.Coordinator.prepareAnnotationUndoSnapshot()` posts `.pdfAnnotationWillChange` with `PDFAnnotationUndoSnapshot(url:data:)`. `ContentView` receives it and calls `AppModel.preparePDFAnnotationUndoSnapshot(_:)`, which stores the current `PDFDocument.dataRepresentation()` in the selected PDF tab's snapshot undo stack and clears the snapshot redo stack.
    - Both paths share one chronological undo/redo timeline in `AppModel.pdfAnnotationActionUndoStacks` / `pdfAnnotationActionRedoStacks`. Do not split object actions and snapshot actions into separate priority queues; that would undo changes in the wrong order after mixed workflows such as draw → move → undo.
  - Why the hybrid design exists: the original all-snapshot approach fixed page-jump issues but PDFKit could still display stale/mixed shape appearances after repeated undo of overlapping or nearby rectangle/oval annotations. Object-level undo for newly-created annotations avoids replacing/reloading the whole PDF document and removes the exact object that was just created, so tests such as “draw bottom rectangle, middle oval, top rectangle, then undo twice” do not blend the oval and rectangle together.
  - 2026-07-04 follow-up 6: after switching newly-created annotations to object-level undo, some sessions could still contain stale/no-op snapshot or object entries in the chronological undo timeline. The visible symptom was that the first Undo removed the newest rectangle, but the second/third Undo sometimes appeared to do nothing unless the user clicked Undo several more times. `AppModel.undoPDFAnnotation()` and `redoPDFAnnotation()` now loop through no-op actions until one actually changes the visible PDF. Object actions report whether they really removed/re-added at least one annotation. Snapshot actions whose data matches the current PDF data are skipped.
  - 2026-07-04 follow-up 7: object-level undo originally checked whether the exact same `PDFAnnotation` object instance still existed in `PDFPage.annotations`. With more shapes, PDFKit can sometimes expose a different in-memory wrapper for the same visible annotation, making Undo skip the entry even though the annotation is still on the page. Newly-created annotations now receive a hidden `FileViewerUndoID` annotation key through `PDFAnnotation.ensureFileViewerUndoID()`. Object undo first tries identity and then falls back to matching this ID, so 5+ rectangle/oval sequences should behave the same as 3-item tests.
  - 2026-07-04 follow-up 8: when the app stayed open, the user could close a PDF tab, reopen the same PDF from Finder, draw annotations, and then need several Undo clicks again. Root cause: old PDFKit coordinators can briefly remain registered for global annotation notifications after their tab closes. If the same file URL is reopened, the old coordinator could record undo entries for the closed PDF document. `PDFAnnotationObjectChange` now carries the exact `PDFDocument` instance and `AppModel.recordPDFAnnotationObjectChange(_:)` only accepts the change when both the URL and live `PDFDocument` identity match the current tab. `PDFAnnotationObjectItem` also stores `pageIndex`, so object undo/redo resolves the page against the current PDF document before falling back to the original page reference.
  - 2026-07-04 follow-up 9: snapshot undo/redo for existing-annotation mutations, such as recoloring a rectangle, could restore the correct annotation color but shift the visible continuous-scroll position upward. `PDFKitView.updateNSView` now captures the enclosing PDF document scroll view's visible origin before swapping `view.document`, reapplies page/scale, and then reapplies the exact visible origin immediately and across the two delayed restoration ticks.
  - Snapshot undo/redo restore whole-PDF snapshots by constructing a new `PDFDocument(data:)` and replacing the current tab's `PDFViewerDocument`. Keep this only for existing-annotation mutations unless a later change implements object-level inverse operations for moves/resizes/recolors/deletes.
  - 2026-07-04 fix: restored PDF snapshots must force the viewer to refresh even though the file URL is unchanged. `PDFViewerDocument.==` now includes PDF object identity. A brief experiment keyed `PDFWorkspace` with `ObjectIdentifier(pdfDocument.document)`, but that recreated the whole viewer and caused an ugly full-document blink on undo/redo. The current approach keeps the existing PDF view alive and lets `PDFKitView.updateNSView` swap `view.document` when the in-memory PDF object changes.
  - 2026-07-04 follow-up: do not call `applyRestoredPageAndScale()` on every SwiftUI update. That caused manual scrolling to page 2, drawing an annotation, then pressing undo/redo to jump back to stale page 1. Restoration now runs only when the in-memory PDF document changes, and annotation snapshot/change paths sync the current PDF page/scale before posting model updates. `MovableAnnotationPDFView.scrollWheel(with:)` also tells the coordinator to sync page/scale after manual scrolling.
  - 2026-07-04 follow-up 2: PDFKit fires page-change notifications while replacing the in-memory PDF document for undo/redo, and those notifications can briefly report page 1. `PDFKitView.updateNSView` now captures the current visible page/scale before assigning `view.document`, suppresses page sync during the document replacement, and restores the captured page/scale after replacement. This prevents undo/redo from jumping back to page 1.
  - 2026-07-04 follow-up 3: the earlier `.pdfAnnotationWillChange` notification only sent the URL and let `AppModel` read `PDFDocument.dataRepresentation()` afterward. In practice this could capture the already-mutated PDF, so Undo restored a snapshot that still contained the new rectangle/annotation. `.pdfAnnotationWillChange` now carries `PDFAnnotationUndoSnapshot(url:data:)`, where the coordinator captures `parent.document.dataRepresentation()` immediately before mutation and sends that exact data to the model.
  - 2026-07-04 follow-up 4: keep `Coordinator.isReplacingDocument` true until the next main-loop tick after swapping `view.document`; delayed PDFKit page notifications can otherwise still overwrite the page with temporary page 1. `updateNSView` also sets `context.coordinator.parent = self` before the document swap so page restoration uses the new document.
  - 2026-07-04 follow-up 5: before Undo/Redo, `AppModel` now posts `.pdfSyncCurrentState` so the PDF view synchronously updates current page/scale before the snapshot restore. During restore, `PDFKitView.updateNSView` clears current selection/highlights, sets `view.document = nil`, assigns the restored document, skips search navigation while replacing, and restores the captured page/scale across two main-loop ticks. This is intentionally more conservative to avoid stale annotation drawing and page-1 jumps.
  - Each tab keeps its own PDF annotation undo/redo history. Object-level add history is capped at 50 actions per PDF tab. Snapshot history is capped at 10 snapshots per PDF tab to limit memory use.
  - Move/resize/line-endpoint changes capture the undo snapshot only when the first actual drag mutation occurs, not when the user merely clicks in Move Annotation mode.
  - PDF annotation sidebar:
    - `SidebarMode.annotations` is the sidebar `Notes` mode.
    - `AppModel.pdfAnnotationEntries` scans the selected PDF document and returns `PDFAnnotationEntry` values for supported annotation types.
    - `AppModel.pdfAnnotationFilter` stores the current annotation sidebar filter. `AppModel.filteredPDFAnnotationEntries` applies `PDFAnnotationFilter.includes(_:)`.
    - `PDFAnnotationFilter` groups annotations into All, Markup (`Highlight`, `Underline`, `Strikeout`), Notes (`Sticky Note`), Text Boxes, Shapes (`Rectangle`, `Oval`, `Line`), and Ink.
    - `DocumentModel.extractPDFAnnotations(from:)` currently includes highlight, underline, strikeout, sticky note, free-text box, rectangle, oval, line/arrow, and ink annotations.
    - `SidebarView.pdfAnnotations` renders the filter dropdown, export button, and list. Each row shows an SF Symbol, annotation type, page number, and a short summary. For sticky notes/text boxes, the summary is `annotation.contents`. For markup/shapes without text, it falls back to the annotation type.
    - Clicking a sidebar row posts `.pdfGoToAnnotation` with `PDFAnnotationNavigationTarget(url:page:bounds:)`.
    - `PDFKitView.Coordinator.goToAnnotation(_:)` verifies the URL matches the live PDF tab/window, then scrolls to a padded copy of the annotation bounds.
    - `AppModel.exportPDFAnnotationSummary()` presents an `NSSavePanel`, defaults to `<pdf name> annotation summary.md`, and writes a Markdown report generated by `AppModel.pdfAnnotationSummaryMarkdown(pdfName:pdfPath:entries:)`.
    - The exported report includes basic metadata, a table with Page / Type / Summary, and a Details section. It exports all supported annotations, not only the current sidebar filter. This avoids accidentally omitting annotations because a filter was left active.
    - Performance note: the sidebar currently scans PDF page annotations on demand whenever the sidebar renders. This is acceptable for the current app, but if large annotated PDFs feel slow, add a per-document cache invalidated by `.pdfAnnotationDidChange`, document replacement, and tab close.
  - 2026-07-05 sidebar toggle cleanup:
    - The app briefly showed two sidebar-looking icons: the native title-bar sidebar toggle and a custom in-content toolbar button.
    - A follow-up attempt kept only the native title-bar sidebar using `NavigationSplitViewVisibility`, but on Patrick's screen the sidebar could slide over the content and clip the left edge of sidebar rows while also changing the PDF page margin unexpectedly.
    - Current design: `ContentView` uses a plain `HStack` with a fixed-width 320-point `SidebarView`, a divider, and the document area. The only visible sidebar button is the app toolbar button. This is less “native magic” but much more predictable for this app.
    - 2026-07-06 follow-up: on a maximized window the sidebar could still compress to roughly 190 points and clip the left side of the `Notes` rows. `ContentView` now gives the sidebar a fixed min/ideal/max width of 320 points and a higher layout priority. `SidebarView` also has the same fixed width.
    - The sidebar mode control is no longer a native segmented picker. It is a custom `HStack` of buttons so `Recent / Contents / Pages / Notes` will not slide/clamp sideways inside a squeezed segmented control.
    - The `Notes` annotation list is no longer a native `List`; it is a `ScrollView` + `LazyVStack` with explicit horizontal padding. This avoids macOS sidebar-list row insets/clipping where only the page numbers were visible.
    - 2026-07-06 follow-up 2: the sidebar still compressed because the PDF annotation toolbar had a very large intrinsic minimum width. `ContentView.body` uses `GeometryReader` to explicitly reserve 320 points for the sidebar and assign the remaining width to the document area. The PDF controls were later condensed into an `Annotate` menu, reducing that pressure substantially.
    - 2026-07-06 follow-up 3: after the document/toolbar side became clipped, the toolbar sidebar button could disappear. The toggle now lives in the sidebar header while the sidebar is open, and only appears in the main toolbar when the sidebar is hidden. This avoids duplicate buttons while keeping the control reachable.
    - 2026-07-07 follow-up: after shrink/enlarge window cycles, the sidebar-header button could visually remain but its hit target could behave stale; clicking it sometimes activated the PDF pages/thumbnails and jumped page instead of hiding the sidebar. The open-sidebar toggle is now a top-level `ContentView` overlay positioned above the sidebar (`zIndex(50)`) with a fixed 32×32 hit area. `SidebarView` no longer owns the hide button. The closed-sidebar toggle remains in the main toolbar.
    - If this is revisited later, make sure the PDF page never sits under the sidebar and the left edge of `Notes` rows is never clipped.
  - `DocumentTab.pdfHasUnsavedAnnotations` is now the general PDF dirty flag. The name is historical; it drives the orange unsaved status, Command-S behavior, and close warning for both annotations and fillable-form edits.
  - `AppModel.savePDFAnnotations()` / `savePDFTab(at:)` writes through `PDFDocument.write(to:)`.
  - `AppModel.savePDFAnnotatedCopyAs()` presents an `NSSavePanel`, defaults the filename to `<original> annotated.pdf`, writes the same `PDFDocument` to the chosen URL, then switches the current tab to that new PDF URL. After this, normal Save writes to the annotated copy rather than the original.
  - Fillable PDF form support:
    - 2026-07-09: Patrick tested a fillable PDF where typing into form fields worked, but Save stayed disabled and only Save As could preserve the filled form. The app now treats PDF widget/form edits as PDF changes.
    - `PDFKitView.Coordinator.formFieldSignature()` scans every page for widget annotations and builds a lightweight signature from page index, field name, widget field type, rounded bounds, `widgetStringValue`, `buttonWidgetState`, and `buttonWidgetStateString`.
    - The baseline signature is captured when a PDF view is created and whenever the PDF document object is replaced.
    - `PDFWorkspace` observes likely AppKit form-control notifications: `NSControl.textDidChangeNotification`, `NSControl.textDidEndEditingNotification`, and `NSComboBox.selectionDidChangeNotification`.
    - `MovableAnnotationPDFView.mouseUp(with:)` also schedules a form-field check after normal PDFKit mouse handling, which catches checkbox/radio/button-style widget changes that may not emit text-control notifications.
    - Checks are debounced briefly on the main queue after local PDF form-control notifications, PDF mouse interaction, or the local key-event monitor. The former continuous 0.35-second full-document polling timer was removed because it repeatedly scanned every page, consumed CPU on large PDFs, and could accumulate after documents closed. If the current widget signature differs from the baseline, the coordinator posts `.pdfAnnotationDidChange`; the existing PDF dirty/save/close-warning path is reused.
    - 2026-07-10 follow-up: a Transport Department form visibly accepted typing but did not update its exposed widget signature, so Save still remained disabled. `MovableAnnotationPDFView` now adds a local key-event monitor while attached to a window. If the focused responder is an `NSTextView` or `NSTextField` inside that PDF view, it calls `Coordinator.markFormFieldEditedByUser()` immediately. This is deliberately scoped to text form controls, so page navigation and app shortcuts do not mark the PDF dirty.
    - The orange dirty status updated immediately, but the SwiftUI `Commands` menu did not revalidate until FileViewer lost and regained focus. To remove that macOS menu-refresh dependency, File > Save and PDF > Save PDF Changes are enabled whenever a PDF tab is open (writing an unchanged PDF is safe). Markdown Save remains enabled only for a new/dirty Markdown document.
    - After a successful PDF save, `AppModel.savePDFTab(at:)` posts `.pdfFormFieldBaselineDidReset` with the PDF URL so the live coordinator can reset its form-field baseline and avoid immediately marking the just-saved file dirty again.
    - Limitation: fillable-form edits currently do not create FileViewer undo/redo entries. Use Save to persist them, or close without saving to discard changes.
- Known limitations:
  - Freehand ink is implemented and shows a live preview while dragging.
  - Text boxes can be added, moved, resized, edited, recolored, and deleted.
  - Sticky notes can be added, moved, edited, and deleted.
  - Rectangle, oval, line, arrow, and freehand ink shapes are implemented.
- Existing annotation recoloring, text box resizing, rectangle/oval edge/corner resizing, and line/arrow endpoint adjustment are implemented.
- Visible resize/endpoint handles are shown while Move Annotation mode is on.
  - Text markup is still erased through selected text overlap, not direct object-click deletion.
  - Annotation creation and supported annotation edits have an undo/redo implementation; fillable-form edits and permanent page rotation are not currently represented in the FileViewer annotation undo stack.
  - Normal Save still writes back to the current PDF file. Use Save Annotated Copy As before marking important source PDFs if you want to preserve the original untouched.
  - The current implementation depends on PDF text selection. Scanned-image PDFs without OCR text cannot be highlighted this way.

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
- `ContentView` sets both `.focusedSceneValue(\.fileViewerModel, model)` and `.focusedSceneObject(model)`.
- 2026-07-02 fix: app menu commands now use `activeModel`, which falls back to `FileViewerWindowRegistry.shared.activeModel` when SwiftUI `@FocusedValue` is nil. Patrick reported that toolbar Save / Save As / Print worked, but File menu Save / Save As / Print were greyed out. The fallback uses the key window/main window to find the correct registered `AppModel`.
- 2026-07-26 follow-up: `FileViewerCommands` also observes the focused `AppModel` through `@FocusedObject`. `@FocusedValue` by itself changes when focus moves but does not observe the model's published tab changes. Without the focused object, File > Save could remain disabled after New Markdown Document until FileViewer lost and regained focus. A fresh untitled Markdown document is saveable immediately; Save opens the normal Save As panel because it has no URL yet. `DocumentSafetyTests.testNewMarkdownDocumentIsImmediatelySaveable` guards the model-side contract.

Menus:

- File/New replacement:
  - New Markdown Document
  - 2026-07-05 fix: New Markdown switches to Split mode and requests focus for the source editor. This avoids the confusing case where a new blank Markdown document opens while the app is still in Preview mode, making it look like typing is broken.
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

Historical commits already merged into `main`:

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
  - Historical behavior (superseded): opening the same PDF/Markdown created multiple tabs/copies. The current app brings the existing writable instance forward; see the Current implementation note at the top of this handoff.
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
- 2026-07-01 — PDF annotation v1 on branch `feature/pdf-annotation`
  - Added selection-based PDF text annotations: Highlight, Underline, and Strikeout.
  - Added a PDF Save button and wired Command-S so annotated PDFs can be saved back to the original file.
  - Added Save Annotated Copy As / Command-Shift-S for PDFs. This writes a new PDF and switches the active tab to the copy.
  - Added close confirmation for PDFs with unsaved annotations.
  - Annotation commands are routed with a `PDFAnnotationCommand(url:kind:)` payload, so a toolbar/menu action targets the active PDF URL instead of blindly applying to every open PDF window.
  - This is intentionally not freehand drawing, shape annotation, or full annotation management yet.
- 2026-08-22 — Markdown Source search highlighting
  - Reused the case-insensitive, trimmed search-range helper for both the rendered Markdown Preview and the raw Markdown Source editor.
  - Source matches are drawn with `NSLayoutManager` temporary background attributes (yellow for non-current matches, orange for the current match), so highlighting never changes the Markdown text or save state.
  - Source navigation follows the shared search field: query edits, Return, and previous/next navigation select and scroll to the current match. A stable query does not force the editor back to the match after ordinary manual scrolling.
  - Documented the intentional raw-source versus rendered-preview search-count difference in the known-issues section below.

This handoff document itself should be committed after creation.

## 5. Current user-visible state

Expected after latest build:

- App launches from:

```text
/Users/patrickshi/Documents/Codex/FileViewer/build/FileViewer.app
```

- Opening multiple files from inside a window can create tabs in that window.
- Historical decision (superseded): duplicate PDF/Markdown opens created another copy. Current safety policy is one writable in-memory instance per file, with the existing tab/window brought forward.
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
- Search should also highlight matches in Markdown Source mode. All raw-source matches use a yellow temporary background and the current match uses orange; Return/up/down navigation moves the current highlight and scrolls the source editor to it.
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
- Check whether menu command can see `activeModel?.isMarkdownDocument == true` or `activeModel?.isPDFDocument == true`.
- Check `FileViewerWindowRegistry.activeModel`, especially if multiple windows are open.

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

### 6.5 Markdown source search (implemented 2026-08-22)

The shared toolbar search now works in Markdown Source mode as well as Preview mode:

- Search is case-insensitive and trims leading/trailing whitespace.
- Every non-overlapping match in the raw Markdown source receives a temporary yellow background; the current match receives an orange background.
- Return in the search field, plus the previous/next buttons, updates the per-tab navigation request and scrolls the Source editor to the selected match.
- Changing the query or opening Source mode with an active query scrolls to the current match. Clearing the query removes temporary highlights.
- Manual scrolling does not repeatedly snap back to the same match. Scrolling occurs only for a query change, an explicit navigation request, or the initial Source view setup.
- Highlighting is implemented with `NSTextView`/`NSLayoutManager` temporary attributes, so it does not modify the Markdown string, dirty the document, or disturb the editor selection/cursor.
- Source mode searches raw Markdown, including syntax markers such as `#`, `**`, and backticks. Preview mode searches the rendered preview text. The shared Markdown match count is currently the raw-source count, so a query can show a different count from the rendered Preview when Markdown syntax is removed or transformed during rendering.

Implementation: `MarkdownWorkspace.swift` provides the shared `markdownSearchRanges` helper for Preview and Source, and `MarkdownSourceEditor.Coordinator.applySearch` owns Source highlighting/navigation.

### 6.6 Markdown table of contents does not jump

The Contents sidebar lists Markdown headings but clicking a heading does not scroll source or preview to that heading.

### 6.7 PDF search is basic

PDF search:

- highlights all matches
- jumps to first match only when the search text changes
- shows current result and total results in the shared search field
- supports previous/next result navigation

Missing:

- search result sidebar/list

Known bug reported by Patrick on 2026-07-02:

- Search can keep pulling the document back to the active match after the user scrolls away to keep reading. Example: search for `chapter 17.1`, the app jumps to the correct match, then manual scrolling may jump back to that same match.
- Clearing the search field can sometimes jump back to the top of the document/page unexpectedly. Patrick said this is intermittent, not every time.
- 2026-07-05 fix: `PDFKitView.updateNSView` still calls `goToSearchMatch(searchMatchIndex)`, but `goToSearchMatch(_:)` now only navigates when the requested match index actually changes. Normal SwiftUI/PDFKit refreshes should no longer pull the document back to the same search match after the user manually scrolls away. Search text changes still jump to the first match, and Return/next/previous still jump intentionally.
- 2026-07-08 fix: the PDF search jump behavior was tightened again. Search text changes and previous/next/Return now create an explicit per-tab navigation request ID. `applySearch(_:)` only updates highlights/counts, while `goToSearchMatch(_:requestID:)` performs scrolling only once per new request. Clearing search removes highlights/counts without issuing a fresh PDF scroll.

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

### 6.9 Current PDF annotation limitations

PDF annotation support is intentionally conservative. Text markup is selection-based; notes, text boxes, shapes, and pen ink are object/page-based.

Implemented:

- highlight selected text
- underline selected text
- strike through selected text
- choose the color for newly-created annotations
- remove highlight/underline/strikeout markup from selected text
- add sticky note comments
- add visible text box annotations
- add rectangle, oval, line, and arrow shape annotations
- draw freehand ink annotations
- move sticky notes, text boxes, rectangles, ovals, lines, arrows, and ink annotations with Move Annotation mode
- edit sticky note and text box text with Edit Annotation mode
- delete sticky notes, text boxes, rectangles, ovals, lines, arrows, and ink annotations with Delete Annotation mode
- show resize/endpoint handles while Move Annotation mode is on
- mark PDF tab/window as dirty after annotation
- detect fillable PDF form edits and mark the PDF tab/window dirty
- save annotations and fillable-form edits back into the PDF file
- save an annotated copy through Save Annotated Copy As
- close warning for unsaved PDF changes
- undo/redo recent annotation changes
- sidebar `Notes` list for jumping to annotations
- basic sticky-note styling polish: standard note icon plus larger FileViewer Move/Edit/Delete hit target

Important caution:

Normal Save writes into the current PDF file. Use Save Annotated Copy As first when you want to protect an original PDF.

### 6.10 App lifecycle and document model

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

The AI assistant is implemented on `feature/ai-assistant`. See `docs/ai-assistant-specification.md` and the implementation section below before continuing it.

1. Continue PDF annotation:
   - author/timestamp metadata in annotation reports
   - consider explicit undo/redo support for permanent page rotations only if it can be implemented without replacing/reloading the full PDF document
2. Improve Markdown preview rendering if Patrick relies heavily on richer tables/checklists.
3. Add remaining Markdown formatting polish:
   - smarter link editing/toggling for arbitrary existing Markdown links
   - more precise preview-to-source mapping when repeated phrases exist
4. Add restore polish if needed:
   - restore exact window positions/sizes
   - optionally restore search text if Patrick later wants it
5. Add repeatable sample files/tests for PDF outline, PDF search counts, Markdown formatting, PDF annotation, form editing, and multi-window restore.

## 10.1 Automated test baseline

`Package.swift` declares `FileViewerTests`, with XCTest coverage in `Tests/FileViewerTests/DocumentSafetyTests.swift` and `Tests/FileViewerTests/AIAssistantTests.swift`. Run `swift test` before committing changes. Tests cover Markdown dirty state, fresh file-version detection, duplicate-open protection, Markdown extension recognition, PDF temporary-view-rotation save isolation, AI chunking/retrieval, selection isolation, local transport enforcement, and safe provider defaults. They intentionally avoid live network streaming, PDFKit drawing/form editing, native modal dialogs, and full UI interaction; those still require manual or future UI testing.

### PDF rotation manual test procedure

Use a disposable copy of a multi-page PDF, preferably one with text in a clear upright orientation.

1. Open the copy and note the current page and orientation.
2. Choose **Rotate > Rotate View Right** from the PDF toolbar. Confirm all pages display rotated while the PDF is not marked with the orange unsaved-PDF status.
3. Add a simple annotation or fill a form field, save, close, and reopen the PDF. Confirm the annotation/form change persists but the original page orientation returns. This verifies view rotation was not saved.
4. Choose **Rotate > Rotate Current Page Right**. Confirm only the active page rotates and the PDF is marked as unsaved. Close without saving, reopen, and confirm that page returns to its original orientation.
5. Repeat the current-page rotation, use **File > Save**, reopen, and confirm only that page remains rotated.
6. On a fresh disposable copy, choose **Rotate > Rotate All Pages 180°**, then **File > Save As**. Confirm the new file has all pages rotated and the original file is unchanged.
7. Combined safety check: apply **Rotate View Right**, then **Rotate Current Page Right**, save a copy, reopen the copy, and confirm it has only the current page’s permanent right rotation—not an additional view rotation on every page.
8. While rotated, navigate pages, change zoom, and use search. Confirm the active page, zoom, and position remain usable after each rotation command.

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

## 12. AI assistant handoff

Branch: `feature/ai-assistant`

The first functional AI slice began with local LM Studio at `http://127.0.0.1:1234/v1`. It now supports persisted provider profiles for LM Studio, Ollama, custom OpenAI-compatible servers, and OpenAI. At implementation time the local LM Studio server exposed `qwen2.5-7b-instruct-uncensored` and an embedding model. A live streaming smoke test returned `LOCAL_OK` successfully. The code filters embedding models out of the chat-model picker.

Architecture:

```text
ContentView
├── toolbar sparkle toggle
├── document workspace
└── AIAssistantPanel (resizable right panel)
    └── AIAssistantManager (per-tab sessions and generation tasks)
        ├── AIContextBuilder (PDF pages / Markdown heading chunks)
        └── AIProvider protocol
            ├── ConfiguredAIProviderClient (configured HTTP/SSE Chat Completions adapter)
            └── LMStudioClient (legacy loopback-only adapter retained for local transport testing)
```

User setup: open the AI panel with the sparkle toolbar icon, then use the gear in the panel header to open **AI Provider Settings**. Add a profile, select its type, endpoint, optional/default model and API key, explicitly enable remote document transfer if its host is not local, save it, then select it from the panel's Provider picker and press Retry to discover models. For OpenAI, use the built-in OpenAI profile, enter an API key, enable remote transfer, save, select the profile, then press Retry.

Source files:

- `Sources/FileViewer/AIAssistant.swift`: messages, scopes, sessions, persisted `AIProviderProfile` definitions, `AIProviderCredentialStore` Keychain access, provider protocol, configured HTTP/SSE Chat-Completions transport, legacy LM Studio loopback adapter, streaming orchestration, prompt construction, document extraction, chunking, keyword retrieval, the 12,000-character safety cap, and filtering of streamed `<think>…</think>` reasoning before it reaches visible messages or chat history.
- `Sources/FileViewer/AIAssistantPanel.swift`: provider/model controls, the AI Provider Settings sheet, scope picker, Summarize/Translate actions, conversation rendering, draft editor, Stop/Send controls, and local-processing disclosure.
- `Sources/FileViewer/ContentView.swift`: sparkle toolbar button, panel layout, and drag resizing.
- `Sources/FileViewer/DocumentModel.swift`: panel state, assistant manager ownership, per-tab PDF selection state, Markdown selection capture, and session cleanup on tab close.
- `Sources/FileViewer/PDFWorkspace.swift`: observes `PDFViewSelectionChanged` and stores selected text/page in the selected tab.
- `Tests/FileViewerTests/AIAssistantTests.swift`: Markdown chunk labels, selection isolation, relevance preference, remote-host rejection in the legacy local adapter, and safe provider-profile defaults.

Privacy and safety behavior:

- The default LM Studio and Ollama profiles use loopback endpoints. A remote profile is rejected before a request is created unless the user enables **Allow this provider to receive document text** in AI Provider Settings.
- OpenAI profiles require an API key; custom-compatible profiles may optionally use one. All saved provider keys are stored under the individual profile UUID in macOS Keychain; credentials never enter UserDefaults, exported data, or logs.
- The provider settings UI must not probe Keychain merely to display whether a key exists. It presents a neutral field and preserves an existing key when left blank. Keychain access occurs only when a provider connection/request actually needs the credential.
- The common configured transport uses `GET /models` and streaming `POST /chat/completions`. It is compatible with LM Studio, Ollama's OpenAI-compatible API, custom compatible servers, and OpenAI's supported Chat Completions endpoint.
- Some reasoning-capable models return private scratch work wrapped in `<think>…</think>`. FileViewer retains the raw response only while it streams, displays only the content outside those tags, then discards the raw buffer. The hidden material is therefore not copied, exported, or supplied as follow-up chat history.
- Every assistant message stores the labels for the exact `AIContextPayload` chunks supplied to that request. The panel renders these as **Sources provided to the model**. PDF `Page N` labels are sorted into ascending page order for human review and are buttons that post the existing `.pdfGoToPage` command; Markdown heading labels remain informative chips. Sorting only affects display: Relevant Sections still sends chunks in relevance order. Do not call them citations or external links unless the answer itself makes a specific citation claim.
- The assistant panel shows a local/remote disclosure derived from the active provider endpoint. A remote endpoint explicitly names its host; Whole Document additionally warns it is currently a 12,000-character preview. The header's download button performs an explicit **Save Conversation as Markdown** export; the transcript includes model/source metadata and assistant-message source labels. Sessions are still not persisted by the app.
- Extraction and retrieval happen in the app. A request is made only after Send, Summarize, or Translate.
- The system prompt treats document excerpts as untrusted reference data and forbids claiming file mutations.
- AI has no save, annotation, deletion, shell, or file-editing tools.
- Conversations are memory-only and are deleted when their document tab closes.

Known limitations / next work:

- the app shows request provenance rather than model-generated citations: PDF `Page N` labels are clickable navigation targets, while Markdown heading labels are informational only;
- selection-based context works from the panel, but contextual `Ask AI About Selection` menu items are not implemented;
- context is capped at 12,000 characters to fit common local-model context windows while reserving 1,024 output tokens. Whole Document is therefore a preview rather than a complete-document synthesis; hierarchical summaries remain future work;
- keyword scoring is intentionally simple and does not yet use the available embedding model;
- the AI panel separates `Summary & Q&A` from `Translation`: questions and summaries use the per-session `Response language` setting (English, Traditional Chinese, or Simplified Chinese), while translation has an independent target-language setting with the same choices;
- `Relevant Sections` is a keyword-retrieval mode for questions. Translation automatically changes this scope to `Current Page/Section`: a generic translation instruction cannot reliably retrieve the visible material and previously could select an unrelated page. The panel explains this behavior while Relevant Sections is selected;
- summary and translation requests deliberately omit prior chat turns so an earlier response from another page cannot contaminate the new result. Normal Ask requests retain the most recent eight messages as conversational history;
- the AppKit-backed composer deliberately uses Return to send and Shift-Return for a newline. Do not replace it with SwiftUI `TextEditor` without retaining this behavior;
- the AI context builder currently performs PDF text extraction synchronously when sending; very large PDFs may briefly delay the UI and should later use a cached background extraction/index;
- the panel uses side-by-side resizing at all widths; the specified narrow-window overlay behavior remains future work;
- provider profiles, active provider, selected model, endpoints, and remote-access approval persist in UserDefaults; credentials persist only in Keychain;
- OpenAI is supported through its Chat Completions endpoint for common streaming transport. Migrating the OpenAI profile to the Responses API is an optional future enhancement, not a current functional requirement;
- summary and translation use the currently selected scope; translation changes `Relevant Sections` to `Current Page/Section` and labels the effective scope accurately. Future polish could add task-specific automatic defaults unless the user explicitly changed the scope;
- conversations are not persisted. **Retry** is implemented for provider connection/model discovery. Each completed assistant response has **Copy Answer** (readable plain text with Markdown syntax removed), **Copy as Markdown**, and **Save as Markdown** actions. The Markdown export prepends source document, context, model, and timestamp metadata, and the normal Save panel can target an Obsidian vault; there is no direct Obsidian integration.

Verification commands:

```bash
cd /Users/patrickshi/Documents/Codex/FileViewer
swift test --jobs 1
curl http://127.0.0.1:1234/v1/models
scripts/package_app.sh
codesign --verify --deep --strict build/FileViewer.app
```
