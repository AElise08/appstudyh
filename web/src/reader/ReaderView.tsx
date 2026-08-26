import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Artifact, CanvasNode, Workspace } from "../domain/types.js";
import { newUUID } from "../domain/create.js";
import { importMaterialFile, splitPages, epubChaptersNeedImageInlining } from "../features/files/extract.js";
import { pagesFromText } from "../features/estudar/study.js";
import PdfReader from "../features/files/PdfReader.js";
import EpubReader from "../features/files/EpubReader.js";
import type { EpubReadingProgress } from "./EpubBookReader.js";
import { useIsMobile } from "../board/MobileHome.js";
import { useReaderSelection } from "./useReaderSelection.js";
import { blockArrowScroll, useBookKeyboard } from "./useBookNavigation.js";
import "./reader.css";

export interface ReaderViewProps {
  workspace: Workspace;
  node: CanvasNode;
  onClose: () => void;
  onChange: (next: Workspace) => void;
  onLoadAttachment?: (id: string) => Promise<Blob | null>;
  onCreateCardFromQuote?: (quote: string, pageIndex: number, body: string) => void;
}

interface QuoteDraft {
  quote: string;
  pageIndex: number;
  body: string;
}

export default function ReaderView({
  workspace,
  node,
  onClose,
  onChange,
  onLoadAttachment,
  onCreateCardFromQuote,
}: ReaderViewProps) {
  const isMobile = useIsMobile();
  const bodyRef = useRef<HTMLDivElement | null>(null);

  const [pageIndex, setPageIndex] = useState(
    node.kind === "pdf"
      ? node.pdfPageIndex
      : node.kind === "epub"
        ? (node.epubPageIndex ?? 0)
        : 0,
  );
  const [pdfBlob, setPdfBlob] = useState<Blob | null>(null);
  const [pdfStatus, setPdfStatus] = useState<"loading" | "ready" | "missing">("loading");
  const [pdfPageCount, setPdfPageCount] = useState(node.pdfPageCount ?? 0);
  const [epubChapters, setEpubChapters] = useState<string[]>(() =>
    splitPages(node.epubText ?? "").filter((part) => part.trim().length > 0),
  );
  const [epubLoading, setEpubLoading] = useState(false);
  const [epubProgress, setEpubProgress] = useState<EpubReadingProgress | null>(null);
  const [quoteDraft, setQuoteDraft] = useState<QuoteDraft | null>(null);
  const [noteBody, setNoteBody] = useState(node.kind === "note" ? node.noteBody : node.calcBody);
  const [epubSettingsOpen, setEpubSettingsOpen] = useState(false);

  const { quote: selectionQuote, clearSelection } = useReaderSelection(bodyRef);

  const touchWorkspace = (patch: Partial<Pick<Workspace, "nodes" | "studyArtifacts">>) => {
    onChange({ ...workspace, ...patch, updatedAt: new Date().toISOString() });
  };

  const patchNode = useCallback(
    (patch: Partial<CanvasNode>) => {
      touchWorkspace({
        nodes: workspace.nodes.map((item) => (item.id === node.id ? { ...item, ...patch } : item)),
      });
    },
    [node.id, workspace, onChange],
  );

  useEffect(() => {
    if (node.kind !== "pdf" || onLoadAttachment === undefined) {
      setPdfBlob(null);
      setPdfStatus("missing");
      return;
    }
    let cancelled = false;
    setPdfStatus("loading");
    void (async () => {
      const blob = await onLoadAttachment(node.id);
      if (cancelled) return;
      if (blob === null) {
        setPdfBlob(null);
        setPdfStatus("missing");
        return;
      }
      setPdfBlob(blob);
      setPdfStatus("ready");
    })();
    return () => {
      cancelled = true;
    };
  }, [node.id, node.kind, onLoadAttachment]);

  useEffect(() => {
    if (node.kind !== "epub") return;
    const fromNode = splitPages(node.epubText ?? "").filter((part) => part.trim().length > 0);
    if (fromNode.length > 0) {
      setEpubChapters(fromNode);
      setEpubLoading(false);

      if (!epubChaptersNeedImageInlining(fromNode) || onLoadAttachment === undefined) return;

      let cancelled = false;
      void (async () => {
        try {
          const blob = await onLoadAttachment(node.id);
          if (cancelled || blob === null) return;
          const extracted = await importMaterialFile(new File([blob], `${node.title}.epub`));
          if (cancelled || extracted.kind !== "epub") return;
          const joined = extracted.pages.join("\n---\n");
          setEpubChapters(extracted.pages);
          patchNode({ epubText: joined, epubPageCount: extracted.pageCount, epubCoverDataUrl: extracted.coverDataUrl ?? null });
        } catch {
          // mantém capítulos sem imagens embutidas
        }
      })();

      return () => {
        cancelled = true;
      };
    }
    if (onLoadAttachment === undefined) return;

    let cancelled = false;
    setEpubLoading(true);
    void (async () => {
      try {
        const blob = await onLoadAttachment(node.id);
        if (cancelled || blob === null) return;
        const extracted = await importMaterialFile(new File([blob], `${node.title}.epub`));
        if (cancelled || extracted.kind !== "epub") return;
        const joined = extracted.pages.join("\n---\n");
        setEpubChapters(extracted.pages);
        patchNode({ epubText: joined, epubPageCount: extracted.pageCount, epubCoverDataUrl: extracted.coverDataUrl ?? null });
      } catch {
        if (!cancelled) setEpubChapters([]);
      } finally {
        if (!cancelled) setEpubLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [node.epubText, node.id, node.kind, node.title, onLoadAttachment, patchNode]);

  const notePages = useMemo(
    () => (node.kind === "note" ? pagesFromText(node.noteBody) : []),
    [node.kind, node.noteBody],
  );
  const epubPages = useMemo(() => epubChapters, [epubChapters]);

  const pageTotal =
    node.kind === "pdf"
      ? pdfPageCount
      : node.kind === "epub"
        ? epubPages.length
        : node.kind === "note"
          ? notePages.length
          : 0;

  const canPaginate =
    node.kind === "pdf" || node.kind === "epub" || (node.kind === "note" && notePages.length > 1);

  const goToPage = useCallback(
    (index: number) => {
      const max = Math.max(0, pageTotal - 1);
      const next = Math.max(0, Math.min(index, max));
      setPageIndex(next);
      if (node.kind === "pdf") patchNode({ pdfPageIndex: next });
      if (node.kind === "epub") patchNode({ epubPageIndex: next });
    },
    [node.kind, pageTotal, patchNode],
  );

  const keyboardEnabled =
    quoteDraft === null && (node.kind === "pdf" || (node.kind === "note" && notePages.length > 1));
  useBookKeyboard(pageIndex, pageTotal, goToPage, keyboardEnabled);

  const progressLabel = useMemo(() => {
    if (node.kind === "epub" && epubProgress !== null) {
      return `Cap. ${epubProgress.chapter + 1}/${epubProgress.chapters} · Pág. ${epubProgress.page + 1}/${epubProgress.pages}`;
    }
    if (canPaginate && pageTotal > 0) {
      return `Página ${pageIndex + 1} de ${pageTotal}`;
    }
    return null;
  }, [canPaginate, epubProgress, node.kind, pageIndex, pageTotal]);

  const progressFill = useMemo(() => {
    if (node.kind === "epub" && epubProgress !== null && epubProgress.chapters > 0) {
      const unit = (epubProgress.chapter + epubProgress.page / Math.max(1, epubProgress.pages)) / epubProgress.chapters;
      return unit * 100;
    }
    if (pageTotal > 0) return ((pageIndex + 1) / pageTotal) * 100;
    return 0;
  }, [epubProgress, node.kind, pageIndex, pageTotal]);

  const openQuoteDraft = useCallback(
    (quote: string) => {
      if (quote.trim().length === 0) return;
      setQuoteDraft({ quote: quote.trim(), pageIndex, body: "" });
      clearSelection();
    },
    [clearSelection, pageIndex],
  );

  const saveQuoteAsNote = () => {
    if (quoteDraft === null || quoteDraft.body.trim().length === 0) return;
    const artifact: Artifact = {
      id: newUUID(),
      kind: "note",
      body: quoteDraft.body.trim(),
      sourceNodeID: node.id,
      sourcePageIndex: quoteDraft.pageIndex,
      sourceQuote: quoteDraft.quote.length > 0 ? quoteDraft.quote : null,
      createdAt: new Date().toISOString(),
    };
    touchWorkspace({ studyArtifacts: [...(workspace.studyArtifacts ?? []), artifact] });
    onCreateCardFromQuote?.(quoteDraft.quote, quoteDraft.pageIndex, quoteDraft.body.trim());
    setQuoteDraft(null);
  };

  const saveNoteBody = () => {
    if (node.kind === "note") patchNode({ noteBody });
    if (node.kind === "calc") patchNode({ calcBody: noteBody });
  };

  const epubTheme = node.epubTheme ?? (isMobile ? "light" : "automatic");
  const epubFontSize = node.epubFontSize ?? (isMobile ? 19 : 17);
  const showReadingSettings = isMobile && (node.kind === "epub" || node.kind === "pdf");

  return (
    <div className={`reader${isMobile ? " reader--mobile" : ""}`}>
      <header className="reader__header">
        <button type="button" className="reader__back" onClick={onClose} aria-label="Voltar à lousa">
          ←
        </button>
        <div className="reader__heading">
          <h1 className="reader__title">{node.title}</h1>
          {progressLabel !== null && <p className="reader__progress">{progressLabel}</p>}
        </div>
        {showReadingSettings && node.kind === "epub" && (
          <button
            type="button"
            className="reader__icon-btn"
            onClick={() => setEpubSettingsOpen((open) => !open)}
            aria-label="Ajustes de leitura"
          >
            Aa
          </button>
        )}
        {!isMobile && selectionQuote.length > 0 && (
          <button type="button" className="reader__quote-btn" onClick={() => openQuoteDraft(selectionQuote)}>
            Trecho → nota
          </button>
        )}
      </header>

      {node.kind === "epub" && epubSettingsOpen && (
        <div className="reader__epub-settings">
          <button
            type="button"
            onClick={() =>
              patchNode({ epubFontSize: Math.max(14, (node.epubFontSize ?? epubFontSize) - 1) })
            }
          >
            A−
          </button>
          <select
            value={epubTheme}
            onChange={(event) => patchNode({ epubTheme: event.target.value as CanvasNode["epubTheme"] })}
          >
            <option value="light">Claro</option>
            <option value="dark">Escuro</option>
            <option value="automatic">Automático</option>
          </select>
          <button
            type="button"
            onClick={() =>
              patchNode({ epubFontSize: Math.min(28, (node.epubFontSize ?? epubFontSize) + 1) })
            }
          >
            A+
          </button>
        </div>
      )}

      <div
        ref={bodyRef}
        className="reader__body"
        tabIndex={-1}
        onKeyDown={blockArrowScroll}
      >
        {node.kind === "note" && (
          <div className="reader__note">
            {notePages.length > 1 ? (
              <pre className="reader__text reader__text--prose">{notePages[pageIndex] ?? ""}</pre>
            ) : (
              <textarea
                className="reader__editor"
                value={noteBody}
                onChange={(event) => setNoteBody(event.target.value)}
                onBlur={saveNoteBody}
                placeholder="Escreva sua nota…"
              />
            )}
          </div>
        )}

        {node.kind === "calc" && (
          <textarea
            className="reader__editor"
            value={noteBody}
            onChange={(event) => setNoteBody(event.target.value)}
            onBlur={saveNoteBody}
            placeholder="Resolução passo a passo…"
          />
        )}

        {node.kind === "pdf" && pdfStatus === "ready" && pdfBlob !== null && (
          <PdfReader
            variant={isMobile ? "embedded" : "standalone"}
            file={pdfBlob}
            pageIndex={pageIndex}
            onPageChange={goToPage}
            onPageCount={(count) => {
              setPdfPageCount(count);
              patchNode({ pdfPageCount: count });
            }}
          />
        )}

        {node.kind === "pdf" && pdfStatus === "loading" && (
          <p className="reader__hint">Carregando PDF…</p>
        )}

        {node.kind === "pdf" && pdfStatus === "missing" && (
          <p className="reader__hint reader__hint--error">
            Arquivo do PDF não encontrado. Exclua este card e importe o PDF de novo.
          </p>
        )}

        {node.kind === "epub" && epubLoading && (
          <p className="reader__hint">Carregando livro…</p>
        )}

        {node.kind === "epub" && !epubLoading && epubPages.length > 0 && (
          <EpubReader
            variant={isMobile ? "embedded" : "standalone"}
            pages={epubPages}
            pageIndex={pageIndex}
            onPageChange={goToPage}
            onReadingProgress={setEpubProgress}
            fontSize={epubFontSize}
            theme={epubTheme}
            onFontSizeChange={(size) => patchNode({ epubFontSize: size })}
            onThemeChange={(theme) => patchNode({ epubTheme: theme })}
          />
        )}

        {node.kind === "epub" && !epubLoading && epubPages.length === 0 && (
          <p className="reader__hint reader__hint--error">
            Não foi possível ler este EPUB. Tente importar de novo.
          </p>
        )}

        {node.kind === "web" && (
          <div className="reader__web">
            <a href={node.webURL} target="_blank" rel="noreferrer">
              Abrir {node.webURL}
            </a>
            {node.webVisibleText !== undefined && node.webVisibleText !== null && (
              <pre className="reader__text reader__text--prose">{node.webVisibleText}</pre>
            )}
          </div>
        )}

        {node.kind === "slides" && (
          <pre className="reader__text reader__text--prose">{node.slidesSelectedText ?? "Slides importados."}</pre>
        )}
      </div>

      {isMobile && selectionQuote.length > 0 && quoteDraft === null && (
        <div className="reader__selection-bar">
          <p className="reader__selection-preview">
            “{selectionQuote.slice(0, 72)}
            {selectionQuote.length > 72 ? "…" : ""}”
          </p>
          <button type="button" className="reader__selection-btn" onClick={() => openQuoteDraft(selectionQuote)}>
            Anotar
          </button>
        </div>
      )}

      {isMobile && canPaginate && progressFill > 0 && (
        <footer className="reader__footer reader__footer--minimal" aria-label="Progresso de leitura">
          <div className="reader__footer-progress">
            <div className="reader__footer-fill" style={{ width: `${progressFill}%` }} />
          </div>
        </footer>
      )}

      {quoteDraft !== null && (
        <>
          <div className="reader__overlay" onClick={() => setQuoteDraft(null)} />
          <div
            className={`reader__modal${isMobile ? " reader__modal--sheet" : ""}`}
            role="dialog"
            aria-label="Nova nota do trecho"
          >
            {quoteDraft.quote.length > 0 && (
              <blockquote className="reader__quote">{quoteDraft.quote}</blockquote>
            )}
            <textarea
              autoFocus
              value={quoteDraft.body}
              onChange={(event) => setQuoteDraft({ ...quoteDraft, body: event.target.value })}
              placeholder="Sua anotação sobre este trecho…"
              rows={isMobile ? 4 : 5}
            />
            <div className="reader__modal-actions">
              <button type="button" onClick={() => setQuoteDraft(null)}>
                Cancelar
              </button>
              <button
                type="button"
                className="reader__primary"
                disabled={quoteDraft.body.trim().length === 0}
                onClick={saveQuoteAsNote}
              >
                Salvar na lousa
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
