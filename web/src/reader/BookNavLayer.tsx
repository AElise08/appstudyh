export interface BookNavLayerProps {
  pageIndex: number;
  pageCount: number;
  onPrev: () => void;
  onNext: () => void;
}

/** Zonas laterais clicáveis para virar página (não bloqueia seleção no centro). */
export default function BookNavLayer({ pageIndex, pageCount, onPrev, onNext }: BookNavLayerProps) {
  if (pageCount <= 1) return null;

  return (
    <div className="book-nav" aria-hidden="true">
      <button
        type="button"
        className="book-nav__zone book-nav__zone--left"
        disabled={pageIndex <= 0}
        onClick={onPrev}
        aria-label="Página anterior"
        tabIndex={-1}
      />
      <button
        type="button"
        className="book-nav__zone book-nav__zone--right"
        disabled={pageIndex >= pageCount - 1}
        onClick={onNext}
        aria-label="Próxima página"
        tabIndex={-1}
      />
    </div>
  );
}
