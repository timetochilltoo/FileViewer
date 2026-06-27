# FileViewer

FileViewer is a local-first native macOS Markdown and PDF viewer/editor built with SwiftUI.

Current MVP build includes:

- Open Markdown and PDF files.
- New unsaved Markdown documents.
- Open multiple Markdown/PDF documents in tabs.
- Drag-and-drop file opening.
- Markdown source view.
- Markdown rendered preview.
- Markdown split view.
- Markdown editing.
- Markdown save and save-as.
- Markdown search count and preview highlighting.
- Markdown formatting buttons, right-click actions, and menu commands for common syntax.
- Help menu Markdown syntax guide.
- PDF rendering.
- PDF page navigation.
- PDF zoom controls.
- PDF thumbnails.
- Basic PDF search by matching pages.
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
