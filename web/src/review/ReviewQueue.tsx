import { useEffect, useMemo, useState } from "react";
import type { ReviewRating, Workspace } from "../domain/types.js";
import { cardIdentity, parseFlashcards, reviewCard } from "../domain/flashcards.js";
import { buildReviewQueue, type QueueCardInput } from "../features/estudar/study.js";
import "./review.css";

export interface ReviewQueueProps {
  workspace: Workspace;
  onChange: (next: Workspace) => void;
  onClose: () => void;
}

const RATING_LABELS: Record<ReviewRating, string> = {
  hard: "Difícil",
  good: "Bom",
  easy: "Fácil",
};

export default function ReviewQueue({ workspace, onChange, onClose }: ReviewQueueProps) {
  const artifacts = workspace.studyArtifacts ?? [];
  const decks = artifacts.filter((artifact) => artifact.kind === "flashcards");

  const cards = useMemo(() => {
    const list: QueueCardInput[] = [];
    for (const deck of decks) {
      const parsed = parseFlashcards(deck.body);
      if (parsed === null) continue;
      parsed.forEach((card, index) => {
        list.push({
          sourceKey: `${deck.id}:${index}`,
          deckID: deck.id,
          sourceNodeID: deck.sourceNodeID ?? null,
          front: card.front,
          back: card.back,
        });
      });
    }
    return list;
  }, [decks]);

  const [identityMap, setIdentityMap] = useState<Map<string, string>>(new Map());
  const [identitiesReady, setIdentitiesReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const next = new Map<string, string>();
      for (const card of cards) {
        next.set(card.sourceKey, await cardIdentity(card.front, card.back));
      }
      if (!cancelled) {
        setIdentityMap(next);
        setIdentitiesReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [cards]);

  const now = new Date();
  const queue = useMemo(
    () =>
      buildReviewQueue(cards, workspace.flashcardReviews ?? [], identityMap, now),
    [cards, identityMap, workspace.flashcardReviews],
  );

  const current = queue[0] ?? null;
  const [revealed, setRevealed] = useState(false);

  useEffect(() => {
    setRevealed(false);
  }, [current?.identity]);

  const rate = (card: QueueCardInput & { identity: string }, rating: ReviewRating) => {
    const reviews = workspace.flashcardReviews ?? [];
    const existing = reviews.find((review) => review.key === card.identity);
    const updated = reviewCard(existing, rating, now);
    const nextReviews = [
      ...reviews.filter((review) => review.key !== card.identity),
      { ...updated, key: card.identity, sourceNodeID: card.sourceNodeID ?? null, deckID: card.deckID ?? null },
    ];
    onChange({ ...workspace, flashcardReviews: nextReviews, updatedAt: now.toISOString() });
  };

  return (
    <div className="review">
      <header className="review__header">
        <button type="button" className="review__back" onClick={onClose}>
          ← Lousa
        </button>
        <h1>Revisar</h1>
        <span className="review__count">{queue.length} na fila</span>
      </header>

      <div className="review__body">
        {!identitiesReady && cards.length > 0 && <p className="review__hint">Carregando baralho…</p>}
        {cards.length === 0 && (
          <p className="review__hint">
            Nenhum flashcard ainda. Converta parágrafos no caderno ou peça ao tutor.
          </p>
        )}
        {identitiesReady && cards.length > 0 && current === null && (
          <p className="review__hint">Tudo revisado por hoje.</p>
        )}
        {current !== null && (
          <div className="review__session">
            <span className={`review__badge review__badge--${current.status}`}>
              {current.status === "due" ? "Para revisar" : "Novo"}
            </span>
            <article className="review__card">
              <p className="review__front">{current.front}</p>
              {revealed && <hr />}
              {revealed && <p className="review__back">{current.back}</p>}
            </article>
            <div className="review__actions">
              {!revealed ? (
                <button type="button" className="review__primary" onClick={() => setRevealed(true)}>
                  Virar
                </button>
              ) : (
                (["hard", "good", "easy"] as const).map((rating) => (
                  <button
                    key={rating}
                    type="button"
                    className={`review__rate review__rate--${rating}`}
                    onClick={() => rate(current, rating)}
                  >
                    {RATING_LABELS[rating]}
                  </button>
                ))
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
