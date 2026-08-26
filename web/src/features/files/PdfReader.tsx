import { useEffect, useRef, useState } from "react";
import type { PDFDocumentProxy } from "pdfjs-dist";
import { pdfjsLib } from "./pdf.js";
import { renderPdfPageToCanvas, type TextSpan } from "./pdfRender.js";
import { useBookNavigation } from "../../reader/useBookNavigation.js";
import BookNavLayer from "../../reader/BookNavLayer.js";
import "./files.css";

export interface PdfReaderProps {
  file: Blob;
  pageIndex: number;
  onPageChange: (index: number) => void;
  onPageCount: (count: number) => void;
  zoom?: number;
  /** embedded = sem barra interna; o ReaderView controla a navegação */
  variant?: "standalone" | "embedded";
}

export default function PdfReader({
  file,
  pageIndex,
  onPageChange,
  onPageCount,
  zoom = 1,
  variant = "standalone",
}: PdfReaderProps) {
  const stageRef = useRef<HTMLDivElement | null>(null);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const taskRef = useRef<ReturnType<typeof pdfjsLib.getDocument> | null>(null);
  const renderGenRef = useRef(0);

  const [numPages, setNumPages] = useState(0);
  const [doc, setDoc] = useState<PDFDocumentProxy | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [spans, setSpans] = useState<TextSpan[]>([]);
  const [stageWidth, setStageWidth] = useState(0);

  const clampedIndex = Math.max(0, Math.min(pageIndex, Math.max(0, numPages - 1)));

  useEffect(() => {
    const el = stageRef.current;
    if (el === null) return;
    const update = () => setStageWidth(el.clientWidth - (variant === "embedded" ? 16 : 24));
    update();
    const observer = new ResizeObserver(update);
    observer.observe(el);
    return () => observer.disconnect();
  }, [variant]);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    setSpans([]);
    setDoc(null);
    void (async () => {
      try {
        const data = new Uint8Array(await file.arrayBuffer());
        const loadingTask = pdfjsLib.getDocument({
          data,
          disableStream: true,
          disableAutoFetch: true,
        });
        taskRef.current = loadingTask;
        const loaded = await loadingTask.promise;
        if (cancelled) {
          void loadingTask.destroy();
          return;
        }
        setDoc(loaded);
        setNumPages(loaded.numPages);
        onPageCount(loaded.numPages);
        setLoading(false);
      } catch (err) {
        if (cancelled) return;
        setError(
          err instanceof Error
            ? `Não foi possível carregar o PDF: ${err.message}`
            : "Não foi possível carregar o PDF.",
        );
        setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
      taskRef.current?.destroy();
      taskRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (doc === null || canvas === null || stageWidth <= 0) return;

    const generation = ++renderGenRef.current;
    let cancelled = false;

    void (async () => {
      try {
        setLoading(true);
        setSpans([]);
        setError(null);

        const page = await doc.getPage(clampedIndex + 1);
        if (cancelled || generation !== renderGenRef.current) return;

        const rendered = await renderPdfPageToCanvas(page, canvas, stageWidth, zoom, true);
        if (cancelled || generation !== renderGenRef.current) return;

        setSpans(rendered.spans);
        setLoading(false);
      } catch (err) {
        if (cancelled || generation !== renderGenRef.current) return;
        const name = (err as { name?: string } | null)?.name ?? "";
        if (name === "RenderingCancelledException") return;
        setError(
          err instanceof Error ? `Falha ao desenhar a página: ${err.message}` : "Falha ao desenhar a página.",
        );
        setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [doc, clampedIndex, numPages, zoom, stageWidth]);

  const bookNav = useBookNavigation(
    clampedIndex,
    numPages,
    onPageChange,
    variant === "embedded" && numPages > 0,
  );

  return (
    <div className={`pdf-reader${variant === "embedded" ? " pdf-reader--embedded" : ""}`}>
      {variant === "standalone" && (
        <div className="files-bar">
          <button
            type="button"
            className="files-btn"
            onClick={() => onPageChange(clampedIndex - 1)}
            disabled={loading || clampedIndex <= 0}
          >
            ← Anterior
          </button>
          <span className="files-pos">
            pág. {numPages === 0 ? "–" : clampedIndex + 1} de {numPages === 0 ? "–" : numPages}
          </span>
          <button
            type="button"
            className="files-btn"
            onClick={() => onPageChange(clampedIndex + 1)}
            disabled={loading || numPages === 0 || clampedIndex >= numPages - 1}
          >
            Próxima →
          </button>
        </div>
      )}

      <div
        className="pdf-reader__stage"
        ref={stageRef}
        onTouchStart={variant === "embedded" ? bookNav.onTouchStart : undefined}
        onTouchEnd={variant === "embedded" ? bookNav.onTouchEnd : undefined}
        onPointerDown={variant === "embedded" ? bookNav.onPointerDown : undefined}
        onPointerUp={variant === "embedded" ? bookNav.onPointerUp : undefined}
      >
        <div className="pdf-reader__page">
          <canvas ref={canvasRef} />
          <div className="pdf-reader__textlayer">
            {spans.map((span, index) => (
              <span
                key={index}
                style={{
                  left: `${span.left}px`,
                  top: `${span.top}px`,
                  width: `${span.width}px`,
                  height: `${span.height}px`,
                  fontSize: `${span.fontSize}px`,
                  transform: span.angle !== 0 ? `rotate(${span.angle}rad)` : undefined,
                }}
              >
                {span.text}
              </span>
            ))}
          </div>
        </div>
        {variant === "embedded" && (
          <BookNavLayer
            pageIndex={clampedIndex}
            pageCount={numPages}
            onPrev={() => onPageChange(clampedIndex - 1)}
            onNext={() => onPageChange(clampedIndex + 1)}
          />
        )}
        {loading && <div className="files-loading">Carregando…</div>}
        {error !== null && <div className="files-error">{error}</div>}
      </div>
    </div>
  );
}
