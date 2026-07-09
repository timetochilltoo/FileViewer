# FileViewer

FileViewer is a local-first native macOS Markdown and PDF viewer/editor built with SwiftUI.

Current MVP build includes:

- Open Markdown and PDF files.
- New unsaved Markdown documents.
- Open multiple Markdown/PDF documents in tabs or separate windows, including multiple copies of the same file.
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
- Markdown search current/total count, previous/next navigation, and preview highlighting.
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
- Stable fixed-width sidebar with custom sidebar tabs and a sidebar toggle that stays reachable.
- PDF annotation v1 on the `feature/pdf-annotation` branch:
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
  - detect fillable PDF form edits so normal Save becomes available after typing into a form
  - save embedded PDF annotations and fillable-form changes back to the PDF file
  - save an annotated PDF copy with Save Annotated Copy As / Command-Shift-S
  - warn before closing a PDF tab/window with unsaved PDF changes
- File-management actions are intentionally kept in menus/shortcuts instead of the crowded toolbar:
  - New Markdown Document
  - Save / Command-S
  - Save As / Command-Shift-S
  - Print / Command-P
- Print support for PDFs and Markdown source text.
- Recent files.
- Light and dark theme.

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

## Packaged App

The current development app bundle is here:

```text
build/FileViewer.app
```

It is built from the Swift release executable and signed locally with an ad-hoc development signature.

To rebuild the app bundle:

```bash
scripts/package_app.sh
```

## Documentation

- Requirements and specification: `docs/requirements-and-specification.md`
- MVP task list: `docs/mvp-task-list.md`
