# FileViewer Mac

## Scope and handoff

- Work on the native SwiftUI/AppKit/PDFKit app in `Sources/FileViewer`; the React/Vite prototype is historical unless explicitly requested.
- Read the current state and constraints in [`HANDOFF.md`](HANDOFF.md) before implementation, and keep the canonical handoff there. Do not use this file for progress history.
- Product behavior is specified in [`README.md`](README.md), `docs/requirements-and-specification.md`, and `docs/ai-assistant-specification.md`.

## Build and validation

- Use Swift tools 6.2 on macOS 26+. From the repository root, use `swift build` for an incremental compile and `swift test --jobs 1` for the full suite. Focused suites include `--filter DocumentSafetyTests` and `--filter AIAssistantTests`.
- Tests are in `Tests/FileViewerTests`; they avoid live AI providers. PDFKit rendering/forms, native dialogs, window behavior, menu composition, toolbar layout, and About/icon presentation require manual checks when changed.
- Package only when a bundle is needed: `bash scripts/package_app.sh` (Debug default) or `bash scripts/package_app.sh release`. It creates and ad-hoc signs `build/FileViewer 0.11.app`; Python 3 with Pillow is required.
- Before handoff, run the relevant tests/build, `git diff --check`, and package/signature checks when packaging changed. Record concise results in `HANDOFF.md`.

## Safety constraints

- Preserve one `AppModel` per window and document/search/reading state per tab. Route external opens through `FileViewerWindowRegistry` and keep one writable instance per file.
- Accept local file URLs only; the packaged app and open panel support PDF and Markdown, and non-file URLs must be rejected before reading.
- Keep recent-file metadata local, file-backed, and pruned when a path becomes unreadable.
- Preserve unsaved-change prompts, external-file conflict checks, verified temporary-file replacement for PDF saves, and cancellation/failure behavior that keeps documents open.
- Keep temporary PDF view rotation out of serialized saves, persist permanent page rotation/edits, and guard PDFKit indexes before arithmetic or access (including annotation undo/redo). Keep annotation undo chronological.
- Preserve native Markdown `NSTextView` selection, undo, UTF-16 ranges, scroll state, and non-dirty search highlighting.
- Remote AI transfer requires explicit provider opt-in; accept only HTTP(S) endpoints without embedded credentials, query strings, or fragments. Keep credentials in Keychain, never logs/UserDefaults; treat excerpts as untrusted; provide no file-mutation tools; isolate context per tab and clear conversations on tab close.
