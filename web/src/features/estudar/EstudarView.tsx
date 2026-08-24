import { useEffect, useMemo, useState } from "react";
import type {
  Artifact,
  CanvasNode,
  EPUBReaderTheme,
  NodeKind,
  Review,
  ReviewRating,
  Workspace,
} from "../../domain/types";
import { createCanvasNode, newUUID } from "../../domain/create";
import { cardIdentity, parseFlashcards, reviewCard } from "../../domain/flashcards";
import {
  buildReviewQueue,
  countPracticedToday,
  pagesFromText,
  splitQuestionBody,
  type QueueCardInput,
} from "./study";
import PdfReader from "../files/PdfReader.js";
import EpubReader from "../files/EpubReader.js";
import { splitPages } from "../files/extract";
import "./estudar.css";

export interface ViewProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
  onAddMaterial?: () => void;
  onSaveAttachment?: (id: string, blob: Blob) => void;
  onLoadAttachment?: (id: string) => Promise<Blob | null>;
}

const KIND_LABELS: Record<NodeKind, string> = {
  note: "Nota",
  pdf: "PDF",
  epub: "EPUB",
  web: "Pesquisa",
  calc: "Resolução",
  slides: "Slides",
};

const RATING_LABELS: Record<ReviewRating, string> = {
  hard: "Difícil",
  good: "Bom",
  easy: "Fácil",
};

type PanelTab = "notas" | "flashcards" | "questoes";

const PANEL_TABS: readonly { id: PanelTab; label: string }[] = [
  { id: "notas", label: "Notas" },
  { id: "flashcards", label: "Flashcards" },
  { id: "questoes", label: "Questões" },
];

interface NoteDraft {
  quote: string;
  pageIndex: number;
  body: string;
}

function artifactsOf(workspace: Workspace): Artifact[] {
  return workspace.studyArtifacts ?? [];
}

function deckTitle(artifact: Artifact, nodes: readonly CanvasNode[]): string {
  const source = nodes.find((node) => node.id === artifact.sourceNodeID);
  return source?.title ?? "Baralho";
}

export default function EstudarView({
  workspace,
  onChange,
  onAddMaterial,
  onSaveAttachment,
  onLoadAttachment,
}: ViewProps) {
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(workspace.nodes[0]?.id ?? null);
  const selectedNode =
    workspace.nodes.find((node) => node.id === selectedNodeId) ?? workspace.nodes[0] ?? null;

  const [pageIndex, setPageIndex] = useState(0);
  const nodeKey = selectedNode?.id ?? "";
  useEffect(() => {
    setPageIndex(0);
  }, [nodeKey]);

  const touchWorkspace = (patch: Partial<Pick<Workspace, "nodes" | "studyArtifacts" | "flashcardReviews">>) => {
    onChange({ ...workspace, ...patch, updatedAt: new Date().toISOString() });
  };

  const patchNode = (id: string, patch: Partial<CanvasNode>) => {
    touchWorkspace({
      nodes: workspace.nodes.map((node) => (node.id === id ? { ...node, ...patch } : node)),
    });
  };

  const pages = useMemo(
    () => (selectedNode?.kind === "note" ? pagesFromText(selectedNode.noteBody) : []),
    [selectedNode],
  );
  const pdfTextPages = useMemo(
    () => (selectedNode?.kind === "pdf" ? splitPages(selectedNode.pdfText ?? "") : []),
    [selectedNode],
  );
  const epubPages = useMemo(
    () => (selectedNode?.kind === "epub" ? splitPages(selectedNode.epubText ?? "") : []),
    [selectedNode],
  );
  const clampedPage = Math.min(pageIndex, Math.max(0, pages.length - 1));

  const maxPageIndex =
    selectedNode?.kind === "pdf"
      ? Math.max(0, (selectedNode.pdfPageCount ?? pdfTextPages.length) - 1)
      : selectedNode?.kind === "epub"
        ? Math.max(0, epubPages.length - 1)
        : Math.max(0, pages.length - 1);
  const activePageIndex =
    selectedNode === null
      ? 0
      : selectedNode.kind === "pdf"
        ? Math.min(Math.max(0, selectedNode.pdfPageIndex), maxPageIndex)
        : selectedNode.kind === "epub"
          ? Math.min(Math.max(0, selectedNode.epubPageIndex ?? 0), maxPageIndex)
          : clampedPage;

  const gotoPage = (index: number) => {
    if (!selectedNode) return;
    if (selectedNode.kind === "note") {
      setPageIndex(index);
      return;
    }
    if (selectedNode.kind === "pdf") patchNode(selectedNode.id, { pdfPageIndex: index });
    else if (selectedNode.kind === "epub") patchNode(selectedNode.id, { epubPageIndex: index });
  };

  const [pdfBlob, setPdfBlob] = useState<Blob | null>(null);
  useEffect(() => {
    setPdfBlob(null);
    if (!onLoadAttachment || selectedNode?.kind !== "pdf") return;
    let cancelled = false;
    void onLoadAttachment(selectedNode.id)
      .then((blob) => {
        if (!cancelled && blob !== null) setPdfBlob(blob);
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nodeKey, selectedNode?.kind]);

  const recordVisitedPage = () => {
    if (!selectedNode) return;
    const visited = selectedNode.visitedUnitIndices ?? [];
    if (visited.includes(activePageIndex)) return;
    touchWorkspace({
      nodes: workspace.nodes.map((node) =>
        node.id === selectedNode.id
          ? { ...node, visitedUnitIndices: [...visited, activePageIndex] }
          : node,
      ),
    });
  };
  useEffect(recordVisitedPage); // eslint-disable-line react-hooks/exhaustive-deps

  const notes = artifactsOf(workspace).filter(
    (artifact) => artifact.kind === "note" && artifact.sourceNodeID === selectedNode?.id,
  );

  const [noteDraft, setNoteDraft] = useState<NoteDraft | null>(null);

  const openQuoteNote = () => {
    if (!selectedNode) return;
    const quote = window.getSelection()?.toString().trim() ?? "";
    setNoteDraft({ quote, pageIndex: activePageIndex, body: "" });
  };

  const saveNoteDraft = () => {
    if (!noteDraft || !selectedNode || noteDraft.body.trim().length === 0) return;
    const artifact: Artifact = {
      id: newUUID(),
      kind: "note",
      body: noteDraft.body.trim(),
      sourceNodeID: selectedNode.id,
      sourcePageIndex: noteDraft.pageIndex,
      sourceQuote: noteDraft.quote.length > 0 ? noteDraft.quote : null,
      createdAt: new Date().toISOString(),
    };
    touchWorkspace({ studyArtifacts: [...artifactsOf(workspace), artifact] });
    setNoteDraft(null);
  };

  const deleteNote = (artifactID: string) => {
    touchWorkspace({
      studyArtifacts: artifactsOf(workspace).filter((artifact) => artifact.id !== artifactID),
    });
  };

  const decks = artifactsOf(workspace).filter((artifact) => artifact.kind === "flashcards");
  const questions = artifactsOf(workspace).filter((artifact) => artifact.kind === "question");

  const reviews = workspace.flashcardReviews ?? [];
  const cards = useMemo<QueueCardInput[]>(
    () =>
      decks.flatMap((deck) =>
        (parseFlashcards(deck.body) ?? []).map((card, index) => ({
          sourceKey: `${deck.id}:${index}`,
          deckID: deck.id,
          sourceNodeID: deck.sourceNodeID ?? null,
          front: card.front,
          back: card.back,
        })),
      ),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [decks.map((deck) => `${deck.id}:${deck.body}`).join("\u0000")],
  );

  const [identities, setIdentities] = useState<Map<string, string>>(new Map());
  const identitySource = decks.map((deck) => `${deck.id}:${deck.body}`).join("\u0000");
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const entries: [string, string][] = [];
      for (const deck of decks) {
        const parsed = parseFlashcards(deck.body);
        if (!parsed) continue;
        for (let index = 0; index < parsed.length; index += 1) {
          const parsedCard = parsed[index];
          if (!parsedCard) continue;
          entries.push([`${deck.id}:${index}`, await cardIdentity(parsedCard.front, parsedCard.back)]);
        }
      }
      if (!cancelled) setIdentities(new Map(entries));
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identitySource]);

  const [panelTab, setPanelTab] = useState<PanelTab>("notas");

  const now = new Date();
  const queue = buildReviewQueue(cards, reviews, identities, now);
  const practicedToday = countPracticedToday(reviews, now);

  const rateCard = (card: QueueCardInput & { identity: string }, rating: ReviewRating) => {
    const existing = reviews.find((review) => review.key === card.identity);
    const nextReview = reviewCard(existing, rating, new Date());
    const entry: Review = {
      ...nextReview,
      key: card.identity,
      sourceNodeID: card.sourceNodeID ?? null,
      deckID: card.deckID ?? null,
    };
    touchWorkspace({
      flashcardReviews: [...reviews.filter((review) => review.key !== card.identity), entry],
    });
  };

  const [revisarDepois, setRevisarDepois] = useState<Set<string>>(new Set());
  const toggleRevisarDepois = (artifactID: string) => {
    setRevisarDepois((current) => {
      const next = new Set(current);
      if (next.has(artifactID)) next.delete(artifactID);
      else next.add(artifactID);
      return next;
    });
  };

  const [addOpen, setAddOpen] = useState(false);
  const [addTitle, setAddTitle] = useState("");
  const submitAddMaterial = () => {
    const title = addTitle.trim();
    if (title.length === 0) return;
    const node = createCanvasNode({ kind: "note", title });
    touchWorkspace({ nodes: [...workspace.nodes, node] });
    setSelectedNodeId(node.id);
    setAddOpen(false);
    setAddTitle("");
  };

  return (
    <div className="estudar">
      <header className="estudar__tabs">
        {workspace.nodes.map((node) => (
          <button
            key={node.id}
            type="button"
            className={`estudar__tab${node.id === selectedNode?.id ? " is-active" : ""}`}
            onClick={() => setSelectedNodeId(node.id)}
          >
            {node.title}
          </button>
        ))}
        {onAddMaterial ? (
          <button type="button" className="estudar__tab estudar__tab--add" onClick={onAddMaterial}>
            + Adicionar
          </button>
        ) : (
          <button type="button" className="estudar__tab estudar__tab--add" onClick={() => setAddOpen(true)}>
            + Adicionar
          </button>
        )}
      </header>

      <div className="estudar__layout">
        <main className="estudar__reader">
          {!selectedNode && (
            <div className="estudar__empty">
              Nenhum material ainda.
              <small>Use “+ Adicionar” para criar o primeiro material.</small>
            </div>
          )}

          {selectedNode?.kind === "note" && (
            <>
              <article className="estudar__page" data-testid="reader-page">
                {pages[clampedPage]}
              </article>
              <footer className="estudar__pager">
                <button
                  type="button"
                  className="estudar__btn"
                  onClick={() => setPageIndex(Math.max(0, clampedPage - 1))}
                  disabled={clampedPage === 0}
                >
                  ← Anterior
                </button>
                <span className="estudar__pager-label">
                  pág. {clampedPage + 1} de {pages.length}
                </span>
                <button
                  type="button"
                  className="estudar__btn"
                  onClick={() => setPageIndex(Math.min(pages.length - 1, clampedPage + 1))}
                  disabled={clampedPage >= pages.length - 1}
                >
                  Próxima →
                </button>
              </footer>
              <button type="button" className="estudar__btn estudar__btn--quote" onClick={openQuoteNote}>
                Nota do trecho
              </button>
            </>
          )}

          {selectedNode?.kind === "pdf" && pdfBlob !== null && (
            <>
              <PdfReader
                file={pdfBlob}
                pageIndex={activePageIndex}
                onPageChange={gotoPage}
                onPageCount={(count) => {
                  if (selectedNode.pdfPageCount !== count) {
                    patchNode(selectedNode.id, { pdfPageCount: count });
                  }
                }}
              />
              <button type="button" className="estudar__btn estudar__btn--quote" onClick={openQuoteNote}>
                Nota do trecho
              </button>
            </>
          )}

          {selectedNode?.kind === "pdf" &&
            pdfBlob === null &&
            (pdfTextPages.length > 0 ? (
              <>
                <article className="estudar__page" data-testid="reader-page">
                  {pdfTextPages[activePageIndex]}
                </article>
                <footer className="estudar__pager">
                  <button
                    type="button"
                    className="estudar__btn"
                    onClick={() => gotoPage(Math.max(0, activePageIndex - 1))}
                    disabled={activePageIndex === 0}
                  >
                    ← Anterior
                  </button>
                  <span className="estudar__pager-label">
                    pág. {activePageIndex + 1} de {pdfTextPages.length}
                  </span>
                  <button
                    type="button"
                    className="estudar__btn"
                    onClick={() => gotoPage(Math.min(pdfTextPages.length - 1, activePageIndex + 1))}
                    disabled={activePageIndex >= pdfTextPages.length - 1}
                  >
                    Próxima →
                  </button>
                </footer>
                <button type="button" className="estudar__btn estudar__btn--quote" onClick={openQuoteNote}>
                  Nota do trecho
                </button>
              </>
            ) : (
              <div className="estudar__fallback">
                <span className="estudar__fallback-kind">{KIND_LABELS[selectedNode.kind]}</span>
                <h2>{selectedNode.title}</h2>
                <p>{selectedNode.noteBody.slice(0, 280) || "Sem texto disponível."}</p>
              </div>
            ))}

          {selectedNode?.kind === "epub" &&
            (epubPages.length > 0 ? (
              <>
                <EpubReader
                  pages={epubPages}
                  pageIndex={activePageIndex}
                  onPageChange={gotoPage}
                  fontSize={selectedNode.epubFontSize}
                  onFontSizeChange={(size: number) =>
                    patchNode(selectedNode.id, { epubFontSize: size })
                  }
                  theme={selectedNode.epubTheme ?? null}
                  onThemeChange={(theme: EPUBReaderTheme) =>
                    patchNode(selectedNode.id, { epubTheme: theme })
                  }
                />
                <button type="button" className="estudar__btn estudar__btn--quote" onClick={openQuoteNote}>
                  Nota do trecho
                </button>
              </>
            ) : (
              <div className="estudar__fallback">
                <span className="estudar__fallback-kind">{KIND_LABELS[selectedNode.kind]}</span>
                <h2>{selectedNode.title}</h2>
                <p>{selectedNode.noteBody.slice(0, 280) || "Sem texto disponível."}</p>
              </div>
            ))}

          {selectedNode !== null &&
            selectedNode.kind !== "note" &&
            selectedNode.kind !== "pdf" &&
            selectedNode.kind !== "epub" && (
              <div className="estudar__fallback">
                <span className="estudar__fallback-kind">{KIND_LABELS[selectedNode.kind]}</span>
                <h2>{selectedNode.title}</h2>
                <p>{selectedNode.noteBody.slice(0, 280) || "Sem texto disponível."}</p>
              </div>
            )}
        </main>

        <aside className="estudar__panel">
          <nav className="estudar__panel-tabs" role="tablist">
            {PANEL_TABS.map((tab) => (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={panelTab === tab.id}
                className={`estudar__panel-tab${panelTab === tab.id ? " is-active" : ""}`}
                onClick={() => setPanelTab(tab.id)}
              >
                {tab.label}
              </button>
            ))}
          </nav>

          {panelTab === "notas" && (
            <section className="estudar__panel-body">
              <div className="estudar__actions">
                <button
                  type="button"
                  className="estudar__btn estudar__btn--primary"
                  onPointerDown={openQuoteNote}
                  disabled={!selectedNode}
                >
                  Nota do trecho
                </button>
                <button
                  type="button"
                  className="estudar__btn"
                  onClick={() => setNoteDraft({ quote: "", pageIndex: activePageIndex, body: "" })}
                  disabled={!selectedNode}
                >
                  Nova nota
                </button>
              </div>
              {notes.length === 0 && (
                <p className="estudar__hint">Nenhuma nota neste material.</p>
              )}
              {notes.map((note) => (
                <article key={note.id} className="estudar__note">
                  {note.sourceQuote && <blockquote className="estudar__note-quote">{note.sourceQuote}</blockquote>}
                  <p className="estudar__note-body">{note.body}</p>
                  <div className="estudar__note-actions">
                    {note.sourcePageIndex != null && (
                      <button
                        type="button"
                        className="estudar__btn"
                        onClick={() => gotoPage(note.sourcePageIndex as number)}
                      >
                        Ir para o trecho
                      </button>
                    )}
                    <button
                      type="button"
                      className="estudar__btn estudar__btn--danger"
                      onClick={() => deleteNote(note.id)}
                    >
                      Excluir
                    </button>
                  </div>
                </article>
              ))}
            </section>
          )}

          {panelTab === "flashcards" && (
            <section className="estudar__panel-body">
              <div className="estudar__progress">
                <span className="estudar__progress-label">
                  {practicedToday} de {practicedToday + queue.length} hoje
                </span>
                <div className="estudar__bar">
                  <div
                    className="estudar__bar-fill"
                    style={{
                      width:
                        practicedToday + queue.length === 0
                          ? "0%"
                          : `${(practicedToday / (practicedToday + queue.length)) * 100}%`,
                    }}
                  />
                </div>
              </div>

              {decks.map((deck) => {
                const count = parseFlashcards(deck.body)?.length ?? 0;
                return (
                  <p key={deck.id} className="estudar__deck">
                    {deckTitle(deck, workspace.nodes)} · {count} cartões
                  </p>
                );
              })}

              {decks.length > 0 && cards.length === 0 && (
                <p className="estudar__hint">Nenhum cartão válido nos baralhos.</p>
              )}

              <FlashcardSession queue={queue} identitiesReady={identities.size > 0} onRate={rateCard} />
            </section>
          )}

          {panelTab === "questoes" && (
            <section className="estudar__panel-body">
              {questions.length === 0 && <p className="estudar__hint">Nenhuma questão disponível.</p>}
              {questions.map((question) => {
                const split = splitQuestionBody(question.body);
                const marked = revisarDepois.has(question.id);
                return (
                  <article key={question.id} className={`estudar__question${marked ? " is-marked" : ""}`}>
                    <p className="estudar__question-prompt">{split.prompt}</p>
                    {split.answer !== null && (
                      <details className="estudar__answer">
                        <summary>Ver gabarito</summary>
                        <p>{split.answer}</p>
                      </details>
                    )}
                    <button
                      type="button"
                      className="estudar__btn"
                      aria-pressed={marked}
                      onClick={() => toggleRevisarDepois(question.id)}
                    >
                      {marked ? "✓ Revisar depois" : "Revisar depois"}
                    </button>
                  </article>
                );
              })}
            </section>
          )}
        </aside>
      </div>

      {(addOpen || noteDraft !== null) && <div className="estudar__overlay" />}

      {addOpen && (
        <div className="estudar__modal" role="dialog" aria-label="Adicionar material">
          <label className="estudar__modal-field">
            Título
            <input
              autoFocus
              value={addTitle}
              onChange={(event) => setAddTitle(event.target.value)}
              placeholder="Título do material"
            />
          </label>
          <div className="estudar__modal-actions">
            <button type="button" className="estudar__btn" onClick={() => setAddOpen(false)}>
              Cancelar
            </button>
            <button type="button" className="estudar__btn estudar__btn--primary" onClick={submitAddMaterial}>
              Criar
            </button>
          </div>
        </div>
      )}

      {noteDraft !== null && (
        <div className="estudar__modal" role="dialog" aria-label="Nova nota">
          {noteDraft.quote.length > 0 && (
            <blockquote className="estudar__note-quote">{noteDraft.quote}</blockquote>
          )}
          <textarea
            autoFocus
            value={noteDraft.body}
            onChange={(event) => setNoteDraft({ ...noteDraft, body: event.target.value })}
            placeholder="Sua anotação…"
            rows={5}
          />
          <div className="estudar__modal-actions">
            <button type="button" className="estudar__btn" onClick={() => setNoteDraft(null)}>
              Cancelar
            </button>
            <button
              type="button"
              className="estudar__btn estudar__btn--primary"
              onClick={saveNoteDraft}
              disabled={noteDraft.body.trim().length === 0}
            >
              Salvar
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

interface FlashcardSessionProps {
  queue: (QueueCardInput & { identity: string; status: "due" | "new" })[];
  identitiesReady: boolean;
  onRate: (card: QueueCardInput & { identity: string }, rating: ReviewRating) => void;
}

function FlashcardSession({ queue, identitiesReady, onRate }: FlashcardSessionProps) {
  const current = queue[0] ?? null;
  const [revealed, setRevealed] = useState(false);
  const currentIdentity = current?.identity ?? null;
  useEffect(() => {
    setRevealed(false);
  }, [currentIdentity]);

  if (!identitiesReady && queue.length === 0) {
    return <p className="estudar__hint">Carregando baralho…</p>;
  }
  if (!current) {
    return <p className="estudar__hint">Tudo revisado por hoje.</p>;
  }

  return (
    <div className="estudar__session">
      <span className={`estudar__badge estudar__badge--${current.status}`}>
        {current.status === "due" ? "Para revisar" : "Novo"}
      </span>
      <article className="estudar__card">
        <p className="estudar__card-front">{current.front}</p>
        {revealed && <hr className="estudar__card-divider" />}
        {revealed && <p className="estudar__card-back">{current.back}</p>}
      </article>
      <div className="estudar__session-actions">
        {!revealed ? (
          <button type="button" className="estudar__btn estudar__btn--primary" onClick={() => setRevealed(true)}>
            Virar
          </button>
        ) : (
          (["hard", "good", "easy"] as const).map((rating) => (
            <button
              key={rating}
              type="button"
              className={`estudar__btn estudar__btn--rate estudar__btn--${rating}`}
              onClick={() => onRate(current, rating)}
            >
              {RATING_LABELS[rating]}
            </button>
          ))
        )}
      </div>
    </div>
  );
}
