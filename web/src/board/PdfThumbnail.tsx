import { useEffect, useRef, useState } from "react";
import { pdfjsLib } from "../features/files/pdf.js";
import { renderPdfPageToCanvas } from "../features/files/pdfRender.js";
import "./pdfThumbnail.css";

export interface PdfThumbnailProps {
  nodeId: string;
  pageCount?: number | null;
  blob?: Blob | null;
  onLoadAttachment: (id: string) => Promise<Blob | null>;
  /** card = preview na lousa; row = miniatura na lista mobile */
  variant?: "card" | "row";
}

export default function PdfThumbnail({
  nodeId,
  pageCount,
  blob: blobProp,
  onLoadAttachment,
  variant = "card",
}: PdfThumbnailProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const renderGenRef = useRef(0);
  const [status, setStatus] = useState<"loading" | "ready" | "missing" | "error">("loading");
  const [errorHint, setErrorHint] = useState<string | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (canvas === null) return;

    const generation = ++renderGenRef.current;
    let cancelled = false;

    void (async () => {
      setStatus("loading");
      setErrorHint(null);
      try {
        const blob = blobProp ?? (await onLoadAttachment(nodeId));
        if (cancelled || generation !== renderGenRef.current) return;
        if (blob === null) {
          setStatus("missing");
          return;
        }

        const data = new Uint8Array(await blob.arrayBuffer());
        const loadingTask = pdfjsLib.getDocument({
          data,
          disableStream: true,
          disableAutoFetch: true,
        });
        const doc = await loadingTask.promise;
        if (cancelled || generation !== renderGenRef.current) return;

        const page = await doc.getPage(1);
        if (cancelled || generation !== renderGenRef.current) return;

        const maxWidth = variant === "row" ? 72 : 220;
        await renderPdfPageToCanvas(page, canvas, maxWidth, 1, false);
        page.cleanup();
        void loadingTask.destroy();

        if (!cancelled && generation === renderGenRef.current) setStatus("ready");
      } catch (err) {
        if (cancelled || generation !== renderGenRef.current) return;
        setStatus("error");
        setErrorHint(err instanceof Error ? err.message : "Não foi possível renderizar");
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [blobProp, nodeId, onLoadAttachment, variant]);

  const label =
    pageCount !== null && pageCount !== undefined && pageCount > 0
      ? `${pageCount} página${pageCount === 1 ? "" : "s"}`
      : "PDF";

  return (
    <div className={`pdf-thumb${variant === "row" ? " pdf-thumb--row" : ""}`}>
      <canvas
        ref={canvasRef}
        className={`pdf-thumb__canvas${status === "ready" ? " is-ready" : ""}`}
        aria-hidden="true"
      />
      {status === "loading" && <span className="pdf-thumb__status">Carregando…</span>}
      {status === "missing" && (
        <span className="pdf-thumb__status pdf-thumb__status--warn">PDF não salvo neste navegador</span>
      )}
      {status === "error" && (
        <span className="pdf-thumb__status pdf-thumb__status--warn">
          {errorHint ?? "Erro ao abrir PDF"}
        </span>
      )}
      <span className="pdf-thumb__label">{label}</span>
    </div>
  );
}
