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

- Creates a `WindowGroup`.
- Installs `ContentView`.
- Sets minimum frame size to `1080 x 720`.
- Uses `.windowStyle(.titleBar)`.
- Registers `FileViewerCommands`.

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
- `MarkdownHeading`
- `ViewerDocument`
  - `.markdown(MarkdownDocument)`
  - `.pdf(PDFViewerDocument)`
- `DocumentTab`
  - wraps a `ViewerDocument`
  - stores per-tab `searchText`
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

`AppModel.document`, `searchText`, `pdfPage`, `pdfPageCount`, and `pdfScale` are computed wrappers over the selected tab. This is important: do not add new global document state unless it truly should apply across every tab. Most document-specific state should live inside `DocumentTab`.

Important methods:

- `openWithPanel()`
  - Opens an `NSOpenPanel`.
  - Allows multiple selection.
  - Supports PDF and text-ish files; actual Markdown detection is extension-based.
- `open(url:)`
  - Reuses an existing tab if the same URL is already open.
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

Implementation note:

- `AppModel.applyMarkdownFormat(_:)` now calls `markdownReplacement(for:in:selectedRange:)`, which returns the actual replacement range, replacement text, and post-format selection.
- This was needed for true toggles because removing formatting sometimes replaces a larger range than the user selected, for example removing `**` immediately outside the selected text.
- Whole-line commands still expand the original selection with `NSString.lineRange(for:)` before toggling.
- Selection math uses `NSString` lengths so the cursor behaves better with non-ASCII text than pure Swift `String.count`.
- Preview formatting uses `sourceRange(forPreviewSelection:command:in:)`.
  - For heading/list/quote-style commands, it tries to match the selected preview text against the comparable source line after removing Markdown line markers.
  - For inline commands such as bold and underline, it searches for the selected preview text in the source, then lets the normal toggle helper expand to surrounding Markdown markers.
  - Current limitation: if the exact same selected phrase appears multiple times, preview formatting may affect the first matching source occurrence. A future improvement could embed source-range metadata in the preview attributed string for perfect mapping.

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
- tab bar:
  - horizontal list of open tabs
  - selected tab has accent background
  - unsaved Markdown tabs show small orange dot
  - each tab has an `xmark` close button
- status bar:
  - current file name
  - unsaved changes indicator
  - status message
  - Markdown search match count
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

- Horizontal scroll view of icon-only buttons.
- One button per `MarkdownFormatCommand`.
- Buttons call `model.applyMarkdownFormat(command)`.
- Buttons are now toggles in the source editor for bold, italic, underline, heading, bullet list, numbered list, quote, and inline code.

Context menu:

- Same formatting commands are available through right-click context menu on the editor.

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
  - quote
  - fenced code block
- Inline content still uses `AttributedString(markdown:)` for simple inline formatting such as bold, italic, link, code, and strikethrough.
- Search highlight:
  - uses `model.searchText`
  - highlights matches in preview with yellow background
  - status bar shows match count
- Underline convenience:
  - source uses `<u>text</u>`
  - preview preprocesses this simple tag and applies underline styling manually because native Markdown parsing leaves it as literal HTML

Known limitations:

- Preview rendering is now structured but still not a full GitHub-Flavored-Markdown renderer.
- Tables and task lists may not render as richly as a dedicated Markdown engine.
- A local parser check showed native `AttributedString(markdown:)` parses bold, italic, heading, link, list, quote, inline code, fenced code, and strikethrough into plain attributed output, but tables flatten into text and task-list checkboxes appear as text.
- Local image support is not fully implemented.
- Formatting toolbar is new and should be manually verified after the native `NSTextView` replacement.
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
- Search is simple; no next/previous search result navigation yet.

### `SidebarView.swift`

Sidebar sections:

- Recent
  - list of recent documents
  - opens recent in tab
- Contents
  - generated from Markdown headings in selected Markdown tab
  - currently displays headings only; does not jump to heading yet
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
  - User has not yet verified after this change.

This handoff document itself should be committed after creation.

## 5. Current user-visible state

Expected after latest build:

- App launches from:

```text
/Users/patrickshi/Documents/Codex/FileViewer/build/FileViewer.app
```

- Opening multiple files should create tabs.
- Markdown tabs should show `Preview / Source / Split`.
- In Source or Split mode, the source editor should appear on the left/source pane with a formatting toolbar above it.
- Selecting text and pressing Bold should wrap selected text in `**`.
- If no text is selected and Bold is pressed, placeholder `**bold text**` should be inserted.
- Preview should update as text changes.
- Search should highlight Markdown preview matches and show match count.
- PDF search should highlight PDF matches and jump to the first.

Not yet verified by Patrick:

- Whether the latest native-editor replacement fixed the formatting buttons.

If Patrick says "still not working", do not return to the old `TextEditor` approach. Debug the `NSTextView` wrapper directly.

## 6. Known issues / likely next bugs

### 6.1 Formatting buttons may still need verification

The most recent user report was that formatting buttons were not working. A stronger fix was applied by replacing SwiftUI `TextEditor` with `NSTextView`, but no user confirmation has happened yet.

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

### 6.2 Unsaved tab close warning is missing

Closing a tab with unsaved Markdown changes currently closes immediately. This can lose in-memory edits. Implement a confirmation alert before closing unsaved Markdown tabs.

Suggested behavior:

- On close tab:
  - if Markdown has unsaved changes, prompt:
    - Save
    - Discard
    - Cancel
  - Save should call save logic for that tab.
  - Cancel should not close.

Be careful because current `saveMarkdown()` saves only selected tab. If adding close confirmation for a non-selected tab, either select it first or write a save method that accepts tab ID.

### 6.3 No session persistence for open tabs

Recents persist, but open tabs do not restore after app restart. PDF page/zoom state only lives in current session. Requirements mention later persistence; not implemented.

### 6.4 Markdown preview quality is limited

`AttributedString(markdown:)` is convenient but not a complete rich Markdown renderer. Known future improvements:

- Better tables
- Task-list checkbox rendering
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

Missing:

- result count
- next/previous match navigation
- clearing search highlights more predictably
- search result sidebar/list

### 6.8 PDF outline support missing

Requirements mention PDF outline/table of contents. Current sidebar Pages mode uses thumbnails only. No PDF outline mode yet.

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

1. Verify native Markdown formatting buttons with Patrick.
2. If still broken, debug `MarkdownSourceEditor` / `NSTextView` directly, not SwiftUI `TextEditor`.
3. Add unsaved-close confirmation for Markdown tabs.
4. Add Markdown formatting polish:
   - visual labels or tooltips that are clearer for beginners
   - maybe a small "Format" dropdown with text labels, not only icons
   - support "insert table" and "insert task list"
5. Improve Markdown preview rendering if Patrick relies heavily on tables/checklists.
6. Improve PDF search result navigation.
7. Add restore-open-tabs / last PDF page persistence.

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
