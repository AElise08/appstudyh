import { useCallback, useEffect, useState } from "react";
import type { CanvasNode, Workspace } from "../domain/types.js";
import { epubCoverDataUrl, nodeListSubtitle } from "./nodeListMeta.js";
import PdfThumbnail from "./PdfThumbnail.js";
import "./mobile.css";

const KIND_LABELS: Record<CanvasNode["kind"], string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const KIND_ICONS: Record<CanvasNode["kind"], string> = {
  note: "✎",
  pdf: "PDF",
  epub: "EP",
  web: "⌁",
  calc: "∑",
  slides: "▦",
};

function EpubCover({ node }: { node: CanvasNode }) {
  const src = epubCoverDataUrl(node);
  if (src !== null) {
    return <img className="mobile-home__epub-cover-image" src={src} alt="" />;
  }
  return (
    <div className="mobile-home__epub-cover" aria-hidden="true">
      <span className="mobile-home__epub-label">EPUB</span>
    </div>
  );
}

export interface MobileHomeProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
  onOpenReader: (nodeId: string) => void;
  onAddNote: () => void;
  onAddMaterial?: () => void;
  onLoadAttachment?: (id: string) => Promise<Blob | null>;
  getAttachmentBlob?: (id: string) => Blob | null;
}

export default function MobileHome({
  workspace,
  onChange,
  onOpenReader,
  onAddNote,
  onAddMaterial,
  onLoadAttachment,
  getAttachmentBlob,
}: MobileHomeProps) {
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draft, setDraft] = useState("");

  const editingNode = workspace.nodes.find((node) => node.id === editingId) ?? null;
  const itemCount = workspace.nodes.length;

  const startEdit = useCallback(
    (node: CanvasNode) => {
      if (node.kind !== "note" && node.kind !== "calc") {
        onOpenReader(node.id);
        return;
      }
      setEditingId(node.id);
      setDraft(node.kind === "calc" ? node.calcBody : node.noteBody);
    },
    [onOpenReader],
  );

  const saveDraft = useCallback(() => {
    if (editingNode === null) return;
    onChange({
      ...workspace,
      nodes: workspace.nodes.map((node) =>
        node.id === editingNode.id
          ? {
              ...node,
              ...(editingNode.kind === "calc" ? { calcBody: draft } : { noteBody: draft }),
            }
          : node,
      ),
      updatedAt: new Date().toISOString(),
    });
    setEditingId(null);
  }, [draft, editingNode, onChange, workspace]);

  return (
    <div className="mobile-home">
      <header className="mobile-home__header">
        <div className="mobile-home__intro">
          <h2 className="mobile-home__heading">Lousa</h2>
          <p className="mobile-home__count">
            {itemCount === 0
              ? "Nenhum material ainda"
              : `${itemCount} ${itemCount === 1 ? "item" : "itens"}`}
          </p>
        </div>
        <div className="mobile-home__actions">
          <button type="button" className="mobile-home__btn mobile-home__btn--primary" onClick={onAddNote}>
            + Nota
          </button>
          {onAddMaterial !== undefined && (
            <button type="button" className="mobile-home__btn" onClick={onAddMaterial}>
              + Material
            </button>
          )}
        </div>
      </header>

      {itemCount === 0 ? (
        <div className="mobile-home__empty">
          <div className="mobile-home__empty-icon" aria-hidden="true">
            ◫
          </div>
          <strong>Sua mesa está vazia</strong>
          <p>Importe um PDF ou crie uma nota para começar a estudar.</p>
        </div>
      ) : (
        <ul className="mobile-home__list">
          {workspace.nodes.map((node) => (
            <li key={node.id}>
              <button type="button" className="mobile-home__card" onClick={() => startEdit(node)}>
                <div className="mobile-home__thumb" data-kind={node.kind}>
                  {node.kind === "pdf" && onLoadAttachment !== undefined ? (
                    <PdfThumbnail
                      variant="row"
                      nodeId={node.id}
                      pageCount={node.pdfPageCount}
                      blob={getAttachmentBlob?.(node.id) ?? null}
                      onLoadAttachment={onLoadAttachment}
                    />
                  ) : node.kind === "epub" ? (
                    <EpubCover node={node} />
                  ) : (
                    <span className="mobile-home__thumb-icon" aria-hidden="true">
                      {KIND_ICONS[node.kind]}
                    </span>
                  )}
                </div>
                <div className="mobile-home__body">
                  <span className="mobile-home__kind" data-kind={node.kind}>
                    {KIND_LABELS[node.kind]}
                  </span>
                  <strong className="mobile-home__title">{node.title}</strong>
                  <span className="mobile-home__meta">{nodeListSubtitle(node)}</span>
                </div>
                <span className="mobile-home__chevron" aria-hidden="true">
                  ›
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {editingId !== null && (
        <>
          <div className="mobile-home__overlay" onClick={() => setEditingId(null)} />
          <div className="mobile-home__sheet" role="dialog" aria-label="Editar nota">
            <textarea
              autoFocus
              value={draft}
              onChange={(event) => setDraft(event.target.value)}
              placeholder="Escreva sua nota…"
            />
            <div className="mobile-home__sheet-actions">
              <button type="button" onClick={() => setEditingId(null)}>
                Cancelar
              </button>
              <button type="button" className="mobile-home__btn mobile-home__btn--primary" onClick={saveDraft}>
                Salvar
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

/** Hook to detect mobile layout — canvas is desktop-only. */
export function useIsMobile(breakpoint = 720): boolean {
  const [mobile, setMobile] = useState(
    () => typeof window !== "undefined" && window.matchMedia(`(max-width: ${breakpoint}px)`).matches,
  );

  useEffect(() => {
    const mq = window.matchMedia(`(max-width: ${breakpoint}px)`);
    const onChange = () => setMobile(mq.matches);
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [breakpoint]);

  return mobile;
}
