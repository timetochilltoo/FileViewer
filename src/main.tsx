import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import * as pdfjsLib from "pdfjs-dist";
import pdfWorkerUrl from "pdfjs-dist/build/pdf.worker.min.mjs?url";
import {
  BookOpen,
  ChevronLeft,
  ChevronRight,
  Columns2,
  Download,
  FileText,
  FolderOpen,
  Moon,
  PanelLeft,
  Save,
  Search,
  SplitSquareHorizontal,
  Sun,
  TextCursorInput,
  ZoomIn,
  ZoomOut,
} from "lucide-react";
import "highlight.js/styles/github-dark.css";
import "./styles.css";

pdfjsLib.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;

type FileKind = "markdown" | "pdf";
type MarkdownMode = "preview" | "source" | "split";
type SidebarMode = "recent" | "toc" | "thumbnails";

type OpenDocument =
  | {
      kind: "markdown";
      name: string;
      key: string;
      text: string;
      savedText: string;
      handle?: FileSystemFileHandle;
    }
  | {
      kind: "pdf";
      name: string;
      key: string;
      data: ArrayBuffer;
    };

type RecentFile = {
  name: string;
  kind: FileKind;
  key: string;
  openedAt: number;
};

type Heading = {
  id: string;
  level: number;
  text: string;
};

type PdfPageView = {
  pageNumber: number;
  canvasUrl: string;
  text: string;
};

const recentKey = "fileviewer.recentFiles";
const settingsKey = "fileviewer.settings";
const stateKeyPrefix = "fileviewer.document.";

const fileTypes = [
  {
    description: "Markdown and PDF",
    accept: {
      "text/markdown": [".md", ".markdown"],
      "application/pdf": [".pdf"],
    },
  },
];

function App() {
  const [doc, setDoc] = useState<OpenDocument | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("recent");
  const [markdownMode, setMarkdownMode] = useState<MarkdownMode>("split");
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const [recentFiles, setRecentFiles] = useState<RecentFile[]>([]);
  const [query, setQuery] = useState("");
  const [message, setMessage] = useState("");
  const [pdfPages, setPdfPages] = useState<PdfPageView[]>([]);
  const [pdfTotalPages, setPdfTotalPages] = useState(0);
  const [pdfCurrentPage, setPdfCurrentPage] = useState(1);
  const [pdfScale, setPdfScale] = useState(1.15);
  const [pdfLoading, setPdfLoading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const markdownScrollRef = useRef<HTMLDivElement | null>(null);
  const pdfScrollRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const storedRecent = localStorage.getItem(recentKey);
    const storedSettings = localStorage.getItem(settingsKey);

    if (storedRecent) {
      setRecentFiles(JSON.parse(storedRecent));
    }

    if (storedSettings) {
      const parsed = JSON.parse(storedSettings) as {
        theme?: "light" | "dark";
        markdownMode?: MarkdownMode;
      };
      setTheme(parsed.theme ?? "light");
      setMarkdownMode(parsed.markdownMode ?? "split");
    }
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    localStorage.setItem(settingsKey, JSON.stringify({ theme, markdownMode }));
  }, [theme, markdownMode]);

  useEffect(() => {
    if (!doc) return;
    addRecent(doc.name, doc.kind, doc.key);
    const stored = localStorage.getItem(stateKeyPrefix + doc.key);
    if (!stored) return;
    const state = JSON.parse(stored) as {
      markdownMode?: MarkdownMode;
      pdfPage?: number;
      pdfScale?: number;
    };

    if (doc.kind === "markdown" && state.markdownMode) {
      setMarkdownMode(state.markdownMode);
    }

    if (doc.kind === "pdf") {
      setPdfCurrentPage(state.pdfPage ?? 1);
      setPdfScale(state.pdfScale ?? 1.15);
    }
  }, [doc?.key]);

  useEffect(() => {
    if (!doc) return;
    const state = doc.kind === "pdf" ? { pdfPage: pdfCurrentPage, pdfScale } : { markdownMode };
    localStorage.setItem(stateKeyPrefix + doc.key, JSON.stringify(state));
  }, [doc, markdownMode, pdfCurrentPage, pdfScale]);

  useEffect(() => {
    if (doc?.kind !== "pdf") {
      setPdfPages([]);
      setPdfTotalPages(0);
      return;
    }

    let cancelled = false;

    async function renderPdf() {
      if (!doc || doc.kind !== "pdf") return;
      setPdfLoading(true);
      setMessage("Rendering PDF...");
      try {
        const source = doc.data.slice(0);
        const pdf = await pdfjsLib.getDocument({ data: source }).promise;
        if (cancelled) return;
        setPdfTotalPages(pdf.numPages);
        const rendered: PdfPageView[] = [];

        for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
          const page = await pdf.getPage(pageNumber);
          const viewport = page.getViewport({ scale: pdfScale });
          const canvas = document.createElement("canvas");
          const context = canvas.getContext("2d");
          if (!context) continue;
          canvas.width = Math.floor(viewport.width);
          canvas.height = Math.floor(viewport.height);
          await page.render({ canvas, canvasContext: context, viewport }).promise;
          const textContent = await page.getTextContent();
          const text = textContent.items
            .map((item) => ("str" in item ? item.str : ""))
            .join(" ");
          rendered.push({ pageNumber, canvasUrl: canvas.toDataURL("image/png"), text });
          if (!cancelled) setPdfPages([...rendered]);
        }
        setMessage("");
      } catch (error) {
        setMessage(error instanceof Error ? error.message : "Could not open this PDF.");
      } finally {
        if (!cancelled) setPdfLoading(false);
      }
    }

    renderPdf();

    return () => {
      cancelled = true;
    };
  }, [doc?.key, pdfScale]);

  const markdownHeadings = useMemo(() => {
    if (doc?.kind !== "markdown") return [];
    return extractHeadings(doc.text);
  }, [doc]);

  const markdownUnsaved = doc?.kind === "markdown" && doc.text !== doc.savedText;

  const pdfSearchMatches = useMemo(() => {
    if (doc?.kind !== "pdf" || !query.trim()) return [];
    const needle = query.toLowerCase();
    return pdfPages.filter((page) => page.text.toLowerCase().includes(needle)).map((page) => page.pageNumber);
  }, [doc, pdfPages, query]);

  function addRecent(name: string, kind: FileKind, key: string) {
    setRecentFiles((current) => {
      const next = [{ name, kind, key, openedAt: Date.now() }, ...current.filter((item) => item.key !== key)].slice(0, 12);
      localStorage.setItem(recentKey, JSON.stringify(next));
      return next;
    });
  }

  async function openWithPicker() {
    setMessage("");
    try {
      if (window.showOpenFilePicker) {
        const [handle] = await window.showOpenFilePicker({ multiple: false, types: fileTypes });
        if (!handle) return;
        const file = await handle.getFile();
        await openFile(file, handle);
        return;
      }
      fileInputRef.current?.click();
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      setMessage("Could not open the file.");
    }
  }

  async function openFile(file: File, handle?: FileSystemFileHandle) {
    const kind = detectFileKind(file);
    setQuery("");
    setMessage("");
    setSidebarMode(kind === "pdf" ? "thumbnails" : "toc");

    if (kind === "markdown") {
      const text = await file.text();
      setDoc({
        kind,
        name: file.name,
        key: `${file.name}:${file.size}:${file.lastModified}`,
        text,
        savedText: text,
        handle,
      });
      return;
    }

    if (kind === "pdf") {
      const data = await file.arrayBuffer();
      setDoc({
        kind,
        name: file.name,
        key: `${file.name}:${file.size}:${file.lastModified}`,
        data,
      });
      return;
    }

    setMessage("This file type is not supported yet. Please open a Markdown or PDF file.");
  }

  async function saveMarkdown() {
    if (doc?.kind !== "markdown") return;

    try {
      if (doc.handle) {
        const writable = await doc.handle.createWritable();
        await writable.write(doc.text);
        await writable.close();
        setDoc({ ...doc, savedText: doc.text });
        setMessage("Saved.");
        return;
      }

      downloadText(doc.text, doc.name);
      setDoc({ ...doc, savedText: doc.text });
      setMessage("Saved as a download. Browser security prevents direct overwrite for dropped files.");
    } catch {
      setMessage("Could not save the Markdown file.");
    }
  }

  async function saveMarkdownAs() {
    if (doc?.kind !== "markdown") return;

    try {
      if (window.showSaveFilePicker) {
        const handle = await window.showSaveFilePicker({
          suggestedName: doc.name,
          types: [
            {
              description: "Markdown",
              accept: { "text/markdown": [".md", ".markdown"] },
            },
          ],
        });
        const writable = await handle.createWritable();
        await writable.write(doc.text);
        await writable.close();
        setDoc({ ...doc, handle, savedText: doc.text });
        setMessage("Saved as new Markdown file.");
        return;
      }

      downloadText(doc.text, doc.name);
      setMessage("Downloaded Markdown file.");
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      setMessage("Could not save a new Markdown file.");
    }
  }

  function jumpToPdfPage(pageNumber: number) {
    const page = Math.min(Math.max(pageNumber, 1), Math.max(pdfTotalPages, 1));
    setPdfCurrentPage(page);
    document.getElementById(`pdf-page-${page}`)?.scrollIntoView({ block: "start", behavior: "smooth" });
  }

  function onDrop(event: React.DragEvent) {
    event.preventDefault();
    const [file] = Array.from(event.dataTransfer.files);
    if (file) openFile(file);
  }

  return (
    <div className="app" onDragOver={(event) => event.preventDefault()} onDrop={onDrop}>
      <input
        ref={fileInputRef}
        className="hidden"
        type="file"
        accept=".md,.markdown,.pdf"
        onChange={(event) => {
          const [file] = Array.from(event.target.files ?? []);
          if (file) openFile(file);
          event.currentTarget.value = "";
        }}
      />

      <header className="toolbar">
        <div className="brand">
          <BookOpen size={20} />
          <span>FileViewer</span>
        </div>
        <button className="toolButton labeled" onClick={openWithPicker} title="Open file">
          <FolderOpen size={18} />
          <span>Open</span>
        </button>
        <button className="toolButton" onClick={() => setSidebarOpen((value) => !value)} title="Toggle sidebar">
          <PanelLeft size={18} />
        </button>

        {doc?.kind === "markdown" && (
          <>
            <div className="segmented" aria-label="Markdown view mode">
              <button className={markdownMode === "preview" ? "active" : ""} onClick={() => setMarkdownMode("preview")} title="Preview">
                <FileText size={17} />
              </button>
              <button className={markdownMode === "source" ? "active" : ""} onClick={() => setMarkdownMode("source")} title="Source">
                <TextCursorInput size={17} />
              </button>
              <button className={markdownMode === "split" ? "active" : ""} onClick={() => setMarkdownMode("split")} title="Split view">
                <SplitSquareHorizontal size={17} />
              </button>
            </div>
            <button className="toolButton" onClick={saveMarkdown} title="Save Markdown">
              <Save size={18} />
            </button>
            <button className="toolButton" onClick={saveMarkdownAs} title="Save as">
              <Download size={18} />
            </button>
          </>
        )}

        {doc?.kind === "pdf" && (
          <>
            <button className="toolButton" onClick={() => jumpToPdfPage(pdfCurrentPage - 1)} title="Previous page">
              <ChevronLeft size={18} />
            </button>
            <label className="pageControl">
              <input
                value={pdfCurrentPage}
                onChange={(event) => jumpToPdfPage(Number(event.target.value) || 1)}
                aria-label="Page number"
              />
              <span>/ {pdfTotalPages || "-"}</span>
            </label>
            <button className="toolButton" onClick={() => jumpToPdfPage(pdfCurrentPage + 1)} title="Next page">
              <ChevronRight size={18} />
            </button>
            <button className="toolButton" onClick={() => setPdfScale((value) => Math.max(0.55, value - 0.15))} title="Zoom out">
              <ZoomOut size={18} />
            </button>
            <button className="toolButton" onClick={() => setPdfScale((value) => Math.min(2.4, value + 0.15))} title="Zoom in">
              <ZoomIn size={18} />
            </button>
          </>
        )}

        <div className="searchBox">
          <Search size={16} />
          <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search" />
        </div>
        <button className="toolButton" onClick={() => setTheme(theme === "light" ? "dark" : "light")} title="Toggle theme">
          {theme === "light" ? <Moon size={18} /> : <Sun size={18} />}
        </button>
      </header>

      <main className="workspace">
        {sidebarOpen && (
          <aside className="sidebar">
            <div className="sidebarTabs">
              <button className={sidebarMode === "recent" ? "active" : ""} onClick={() => setSidebarMode("recent")}>
                Recent
              </button>
              <button className={sidebarMode === "toc" ? "active" : ""} onClick={() => setSidebarMode("toc")}>
                Contents
              </button>
              <button className={sidebarMode === "thumbnails" ? "active" : ""} onClick={() => setSidebarMode("thumbnails")}>
                Pages
              </button>
            </div>
            <Sidebar
              mode={sidebarMode}
              recentFiles={recentFiles}
              headings={markdownHeadings}
              pdfPages={pdfPages}
              query={query}
              pdfSearchMatches={pdfSearchMatches}
              onPdfPage={jumpToPdfPage}
            />
          </aside>
        )}

        <section className="documentArea">
          <div className="documentStatus">
            <span>{doc ? doc.name : "No file open"}</span>
            {markdownUnsaved && <strong>Unsaved changes</strong>}
            {pdfLoading && <strong>Loading PDF</strong>}
            {message && <em>{message}</em>}
          </div>
          {!doc && <EmptyState onOpen={openWithPicker} />}
          {doc?.kind === "markdown" && (
            <MarkdownWorkspace
              doc={doc}
              mode={markdownMode}
              query={query}
              scrollRef={markdownScrollRef}
              onChange={(text) => setDoc({ ...doc, text })}
            />
          )}
          {doc?.kind === "pdf" && (
            <PdfWorkspace
              pages={pdfPages}
              query={query}
              scrollRef={pdfScrollRef}
              onPageVisible={setPdfCurrentPage}
            />
          )}
        </section>
      </main>
    </div>
  );
}

function EmptyState({ onOpen }: { onOpen: () => void }) {
  return (
    <div className="emptyState">
      <FileText size={42} />
      <h1>Open a Markdown or PDF file</h1>
      <p>Drag a file here, or choose one from your computer.</p>
      <button className="primaryButton" onClick={onOpen}>
        <FolderOpen size={18} />
        Open file
      </button>
    </div>
  );
}

function Sidebar({
  mode,
  recentFiles,
  headings,
  pdfPages,
  query,
  pdfSearchMatches,
  onPdfPage,
}: {
  mode: SidebarMode;
  recentFiles: RecentFile[];
  headings: Heading[];
  pdfPages: PdfPageView[];
  query: string;
  pdfSearchMatches: number[];
  onPdfPage: (page: number) => void;
}) {
  if (mode === "recent") {
    return (
      <div className="sideList">
        {recentFiles.length === 0 && <p className="muted">Recent files will appear here.</p>}
        {recentFiles.map((file) => (
          <div className="recentItem" key={file.key}>
            <FileText size={16} />
            <div>
              <strong>{file.name}</strong>
              <span>{file.kind.toUpperCase()}</span>
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (mode === "toc") {
    return (
      <div className="sideList">
        {headings.length === 0 && <p className="muted">Headings will appear here for Markdown files.</p>}
        {headings.map((heading) => (
          <a className="tocItem" href={`#${heading.id}`} style={{ paddingLeft: 10 + (heading.level - 1) * 12 }} key={heading.id}>
            {heading.text}
          </a>
        ))}
      </div>
    );
  }

  return (
    <div className="thumbnailList">
      {pdfPages.length === 0 && <p className="muted">PDF pages will appear here.</p>}
      {query.trim() && <p className="muted">{pdfSearchMatches.length} matching pages</p>}
      {pdfPages.map((page) => (
        <button className="thumbnailButton" key={page.pageNumber} onClick={() => onPdfPage(page.pageNumber)}>
          <img src={page.canvasUrl} alt={`Page ${page.pageNumber}`} />
          <span>Page {page.pageNumber}</span>
        </button>
      ))}
    </div>
  );
}

function MarkdownWorkspace({
  doc,
  mode,
  query,
  scrollRef,
  onChange,
}: {
  doc: Extract<OpenDocument, { kind: "markdown" }>;
  mode: MarkdownMode;
  query: string;
  scrollRef: React.RefObject<HTMLDivElement | null>;
  onChange: (text: string) => void;
}) {
  const preview = (
    <div className="markdownPreview">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[rehypeHighlight]}
        components={{
          h1: headingComponent("h1"),
          h2: headingComponent("h2"),
          h3: headingComponent("h3"),
          h4: headingComponent("h4"),
          code(props) {
            const { children, className } = props;
            const inline = !className;
            if (inline) return <code>{children}</code>;
            return (
              <div className="codeBlock">
                <button onClick={() => navigator.clipboard.writeText(String(children))}>Copy</button>
                <code className={className}>{children}</code>
              </div>
            );
          },
        }}
      >
        {query.trim() ? markText(doc.text, query) : doc.text}
      </ReactMarkdown>
    </div>
  );

  return (
    <div className={`markdownWorkspace mode-${mode}`} ref={scrollRef}>
      {(mode === "source" || mode === "split") && (
        <textarea
          className="markdownEditor"
          spellCheck={false}
          value={doc.text}
          onChange={(event) => onChange(event.target.value)}
          aria-label="Markdown source"
        />
      )}
      {(mode === "preview" || mode === "split") && preview}
    </div>
  );
}

function PdfWorkspace({
  pages,
  query,
  scrollRef,
  onPageVisible,
}: {
  pages: PdfPageView[];
  query: string;
  scrollRef: React.RefObject<HTMLDivElement | null>;
  onPageVisible: (page: number) => void;
}) {
  return (
    <div className="pdfWorkspace" ref={scrollRef}>
      {pages.map((page) => {
        const matches = query.trim() && page.text.toLowerCase().includes(query.toLowerCase());
        return (
          <article
            className={matches ? "pdfPage hasMatch" : "pdfPage"}
            id={`pdf-page-${page.pageNumber}`}
            key={page.pageNumber}
            onMouseEnter={() => onPageVisible(page.pageNumber)}
          >
            <img src={page.canvasUrl} alt={`PDF page ${page.pageNumber}`} />
            <footer>Page {page.pageNumber}</footer>
          </article>
        );
      })}
    </div>
  );
}

function headingComponent(Tag: "h1" | "h2" | "h3" | "h4") {
  return function HeadingRenderer(props: React.HTMLAttributes<HTMLHeadingElement>) {
    const text = String(props.children ?? "");
    const id = slugify(text);
    return React.createElement(Tag, { ...props, id });
  };
}

function detectFileKind(file: File): FileKind | null {
  const name = file.name.toLowerCase();
  if (name.endsWith(".md") || name.endsWith(".markdown")) return "markdown";
  if (name.endsWith(".pdf") || file.type === "application/pdf") return "pdf";
  return null;
}

function extractHeadings(text: string): Heading[] {
  return text
    .split("\n")
    .map((line) => /^(#{1,6})\s+(.+)$/.exec(line))
    .filter((match): match is RegExpExecArray => Boolean(match))
    .map((match) => ({
      id: slugify(match[2]),
      level: match[1].length,
      text: match[2].replace(/[#*_`]/g, "").trim(),
    }));
}

function slugify(value: string) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

function downloadText(text: string, name: string) {
  const blob = new Blob([text], { type: "text/markdown;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  URL.revokeObjectURL(url);
}

function markText(text: string, query: string) {
  if (!query.trim()) return text;
  return text.split(query).join(`==${query}==`);
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
