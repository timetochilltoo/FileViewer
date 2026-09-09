# FileViewer Mac

## Scope and project memory

- The supported app is the native SwiftUI/AppKit/PDFKit implementation in `Sources/FileViewer`, built with Swift tools 6.2 for macOS 26+. The React/Vite prototype is historical; leave it alone unless explicitly requested.
- Canonical handoff: [`HANDOFF.md`](HANDOFF.md) at the repository root. Read current state and task-relevant constraints; consult historical debugging notes only as needed. Keep progress there, not in this file.
- See [`README.md`](README.md) for usage and [`docs/requirements-and-specification.md`](docs/requirements-and-specification.md) for product behavior. AI scope is documented in [`docs/ai-assistant-specification.md`](docs/ai-assistant-specification.md).

## Build and validation

Run from the repository root on macOS with the Swift 6.2 toolchain:

- Incremental Debug compile: `swift build`; development launch: `swift run FileViewer`. Reuse SwiftPM's `.build` cache.
- Focused tests: `swift test --jobs 1 --filter DocumentSafetyTests` or `swift test --jobs 1 --filter AIAssistantTests`; narrow to an individual test when appropriate. Full suite: `swift test --jobs 1`.
- Tests live in `Tests/FileViewerTests` and avoid live AI providers. PDFKit rendering, forms, native dialogs, window behavior, and toolbar layout need relevant manual/UI checks; use disposable documents for save/edit checks.
- Existing bundle packaging: `bash scripts/package_app.sh` (lowercase tracked directory) defaults to a native Debug build; pass `release` for Release. It requires Python 3 with Pillow, writes the versioned `build/FileViewer 0.1.1.app`, and ad-hoc signs/verifies it. Use when a packaged app is needed; it is not a routine compile/test step.
- Documentation-only edits require checking facts, paths, and the diff, not rebuilding the app. Old handoff release checklists do not make every change a packaging task.

## Safety boundaries

- Each window owns its `AppModel`; document/search/reading state belongs to its tab. Route external opens through `FileViewerWindowRegistry` and preserve one writable instance per file across windows. Target PDF notifications to the intended document, including live object identity where callbacks can outlive a tab.
- Preserve unsaved-change prompts on tab/window close and quit, external-file-change conflict checks, and verified temporary-file replacement for PDF saves. Cancellation or save failure must keep the document open.
- Temporary PDF view rotation must be removed only from the serialized save copy through `fileViewerPersistedCopy(removingViewRotation:)`; permanent page rotations and edits must persist. Guard PDFKit page indexes against `NSNotFound` and invalid bounds before arithmetic or access.
- Keep annotation undo actions chronological across object and snapshot operations. Preserve page/zoom/scroll state during document replacement; search must scroll only for explicit navigation requests.
- Markdown editing uses native `NSTextView` bridges. Preserve selection, undo, and UTF-16 range handling; search highlighting must not alter text or dirty state.
- Remote AI document transfer requires the provider's explicit opt-in. Credentials stay in Keychain, never logs or UserDefaults. Document excerpts are untrusted data; the assistant has no file-mutation tools. Preserve per-tab context isolation and memory-only conversation cleanup on tab close.
