import { useMemo } from "react";
import type { EPUBReaderTheme } from "../../domain/types.js";
import { sanitizeChapterHtml } from "./extract.js";
import EpubBookReader, { type EpubReadingProgress } from "../../reader/EpubBookReader.js";
import "./files.css";

const THEME_OPTIONS: readonly { value: EPUBReaderTheme; label: string }[] = [
  { value: "automatic", label: "Automático" },
  { value: "light", label: "Claro" },
  { value: "dark", label: "Escuro" },
];

const MIN_FONT_SIZE = 14;
const MAX_FONT_SIZE = 28;
const DEFAULT_FONT_SIZE = 17;

export interface EpubReaderProps {
  pages: string[];
  pageIndex: number;
  onPageChange: (index: number) => void;
  onReadingProgress?: (progress: EpubReadingProgress) => void;
  fontSize?: number | null;
  onFontSizeChange?: (size: number) => void;
  theme?: EPUBReaderTheme | null;
  onThemeChange?: (theme: EPUBReaderTheme) => void;
  variant?: "standalone" | "embedded";
}

export default function EpubReader({
  pages,
  pageIndex,
  onPageChange,
  onReadingProgress,
  fontSize,
  onFontSizeChange,
  theme,
  onThemeChange,
  variant = "standalone",
}: EpubReaderProps) {
  const clampedIndex =
    pages.length === 0 ? 0 : Math.max(0, Math.min(pageIndex, pages.length - 1));
  const chapter = pages[clampedIndex] ?? "";
  const safeHtml = useMemo(() => sanitizeChapterHtml(chapter), [chapter]);
  const effectiveFontSize = Math.max(
    MIN_FONT_SIZE,
    Math.min(MAX_FONT_SIZE, fontSize ?? DEFAULT_FONT_SIZE),
  );
  const activeTheme: EPUBReaderTheme = theme ?? "automatic";

  const changeFontSize = (delta: number) => {
    onFontSizeChange?.(Math.max(MIN_FONT_SIZE, Math.min(MAX_FONT_SIZE, effectiveFontSize + delta)));
  };

  if (variant === "embedded") {
    return (
      <div className="epub-reader epub-reader--embedded epub-reader--book" data-theme={activeTheme}>
        <EpubBookReader
          pages={pages}
          chapterIndex={clampedIndex}
          onChapterChange={onPageChange}
          onProgress={onReadingProgress}
          fontSize={effectiveFontSize}
          theme={activeTheme}
        />
      </div>
    );
  }

  return (
    <div className="epub-reader" data-theme={activeTheme}>
      <div className="files-bar">
        <button
          type="button"
          className="files-btn"
          onClick={() => onPageChange(clampedIndex - 1)}
          disabled={clampedIndex <= 0}
        >
          ← Anterior
        </button>
        <span className="files-pos">
          cap. {clampedIndex + 1} de {pages.length}
        </span>
        <button
          type="button"
          className="files-btn"
          onClick={() => onPageChange(clampedIndex + 1)}
          disabled={clampedIndex >= pages.length - 1}
        >
          Próxima →
        </button>
      </div>

      <article
        className="epub-reader__content"
        style={{ ["--epub-font-size" as string]: `${effectiveFontSize}px` }}
      >
        {pages.length === 0 ? (
          <p className="files-empty">Nenhum capítulo disponível.</p>
        ) : (
          <div className="epub-reader__chapter" dangerouslySetInnerHTML={{ __html: safeHtml }} />
        )}
      </article>

      <div className="files-bar epub-reader__controls">
        <button type="button" className="files-btn" onClick={() => changeFontSize(-1)} aria-label="Diminuir fonte">
          A−
        </button>
        <label className="epub-reader__theme">
          Tema
          <select
            value={activeTheme}
            onChange={(event) => onThemeChange?.(event.target.value as EPUBReaderTheme)}
          >
            {THEME_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <button type="button" className="files-btn" onClick={() => changeFontSize(1)} aria-label="Aumentar fonte">
          A+
        </button>
      </div>
    </div>
  );
}
