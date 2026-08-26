import type { PointerEvent } from "react";
import type { CanvasNode } from "../domain/types.js";
import PdfThumbnail from "./PdfThumbnail.js";
import { epubCoverDataUrl } from "./nodeListMeta.js";
import "./pdfThumbnail.css";

const KIND_LABELS: Record<CanvasNode["kind"], string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const READER_KINDS = new Set<CanvasNode["kind"]>(["pdf", "epub", "web", "slides"]);

export interface BoardCardProps {
  node: CanvasNode;
  selected: boolean;
  onPointerDownHeader: (event: PointerEvent<HTMLElement>) => void;
  onPointerMoveHeader: (event: PointerEvent<HTMLElement>) => void;
  onPointerUpHeader: (event: PointerEvent<HTMLElement>) => void;
  onSelect: () => void;
  onPatch: (patch: Partial<CanvasNode>) => void;
  onOpenReader: () => void;
  onLoadAttachment?: (id: string) => Promise<Blob | null>;
  attachmentBlob?: Blob | null;
}

export default function BoardCard({
  node,
  selected,
  onPointerDownHeader,
  onPointerMoveHeader,
  onPointerUpHeader,
  onSelect,
  onPatch,
  onOpenReader,
  onLoadAttachment,
  attachmentBlob,
}: BoardCardProps) {
  const isEditable = node.kind === "note" || node.kind === "calc";
  const bodyValue = node.kind === "calc" ? node.calcBody : node.noteBody;
  const epubCover = epubCoverDataUrl(node);

  return (
    <article
      className={`board-card${selected ? " is-selected" : ""}`}
      style={{
        left: node.frame.x,
        top: node.frame.y,
        width: node.frame.width,
        height: node.frame.height,
      }}
      onPointerDown={(event) => event.stopPropagation()}
      onClick={(event) => {
        event.stopPropagation();
        onSelect();
      }}
    >
      <header
        className="board-card__header"
        onPointerDown={onPointerDownHeader}
        onPointerMove={onPointerMoveHeader}
        onPointerUp={onPointerUpHeader}
        onPointerCancel={onPointerUpHeader}
      >
        <span className="board-card__kind">{KIND_LABELS[node.kind]}</span>
        <h3 className="board-card__title">{node.title}</h3>
        {READER_KINDS.has(node.kind) && (
          <button
            type="button"
            className="board-card__open"
            onClick={(event) => {
              event.stopPropagation();
              onOpenReader();
            }}
          >
            Abrir
          </button>
        )}
      </header>

      {node.kind === "pdf" && onLoadAttachment !== undefined ? (
        <PdfThumbnail
          nodeId={node.id}
          pageCount={node.pdfPageCount}
          blob={attachmentBlob}
          onLoadAttachment={onLoadAttachment}
        />
      ) : node.kind === "epub" ? (
        <div className="board-card__epub">
          {epubCover !== null ? (
            <img className="board-card__epub-cover-image" src={epubCover} alt="" />
          ) : (
            <div className="board-card__epub-cover">
              <span className="board-card__epub-label">EPUB</span>
              <p className="board-card__epub-title">{node.title}</p>
              <span className="board-card__epub-meta">
                {node.epubPageCount ?? "?"} capítulo{(node.epubPageCount ?? 0) === 1 ? "" : "s"}
              </span>
            </div>
          )}
        </div>
      ) : isEditable ? (
        <textarea
          className="board-card__editor"
          value={bodyValue}
          placeholder="Escreva aqui…"
          onChange={(event) => {
            const value = event.target.value;
            onPatch(node.kind === "calc" ? { calcBody: value } : { noteBody: value });
          }}
          onPointerDown={(event) => event.stopPropagation()}
        />
      ) : (
        <p className="board-card__preview">Use Abrir para ler o material.</p>
      )}
    </article>
  );
}
