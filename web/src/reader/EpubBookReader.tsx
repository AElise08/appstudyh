import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { EPUBReaderTheme } from "../domain/types.js";
import { sanitizeChapterHtml } from "../features/files/extract.js";
import BookPaginator from "./BookPaginator.js";
import { useBookNavigation } from "./useBookNavigation.js";

export interface EpubReadingProgress {
  chapter: number;
  chapters: number;
  page: number;
  pages: number;
}

export interface EpubBookReaderProps {
  pages: string[];
  chapterIndex: number;
  onChapterChange: (index: number) => void;
  onProgress?: (progress: EpubReadingProgress) => void;
  fontSize: number;
  theme?: EPUBReaderTheme | null;
}

/** Leitor Kindle: pagina um capítulo por vez (rápido no mobile). */
export default function EpubBookReader({
  pages,
  chapterIndex,
  onChapterChange,
  onProgress,
  fontSize,
  theme = "light",
}: EpubBookReaderProps) {
  const [pageInChapter, setPageInChapter] = useState(0);
  const [pagesInChapter, setPagesInChapter] = useState(1);
  const jumpToLastRef = useRef(false);

  const chapter = pages.length === 0 ? 0 : Math.max(0, Math.min(chapterIndex, pages.length - 1));
  const html = useMemo(() => sanitizeChapterHtml(pages[chapter] ?? ""), [pages, chapter]);

  useEffect(() => {
    setPageInChapter(0);
    jumpToLastRef.current = false;
  }, [chapter]);

  useEffect(() => {
    if (jumpToLastRef.current) {
      setPageInChapter(Math.max(0, pagesInChapter - 1));
      jumpToLastRef.current = false;
    }
  }, [pagesInChapter, chapter]);

  const goToPage = useCallback(
    (index: number) => {
      if (index < 0) {
        if (chapter > 0) {
          jumpToLastRef.current = true;
          onChapterChange(chapter - 1);
        }
        return;
      }
      if (index >= pagesInChapter) {
        if (chapter < pages.length - 1) {
          onChapterChange(chapter + 1);
          setPageInChapter(0);
        }
        return;
      }
      setPageInChapter(index);
    },
    [chapter, onChapterChange, pages.length, pagesInChapter],
  );

  useEffect(() => {
    onProgress?.({
      chapter,
      chapters: pages.length,
      page: pageInChapter,
      pages: pagesInChapter,
    });
  }, [chapter, onProgress, pageInChapter, pages.length, pagesInChapter]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const tag = (event.target as HTMLElement | null)?.tagName ?? "";
      if (tag === "TEXTAREA" || tag === "INPUT" || tag === "SELECT") return;
      if (event.key === "ArrowLeft" || event.key === "PageUp") {
        event.preventDefault();
        goToPage(pageInChapter - 1);
      }
      if (event.key === "ArrowRight" || event.key === "PageDown") {
        event.preventDefault();
        goToPage(pageInChapter + 1);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [goToPage, pageInChapter]);

  const nav = useBookNavigation(pageInChapter, pagesInChapter, goToPage, html.length > 0);

  if (pages.length === 0) {
    return <p className="files-empty">Nenhum capítulo disponível.</p>;
  }

  return (
    <div
      className="epub-book-reader"
      data-theme={theme ?? "light"}
      onTouchStart={nav.onTouchStart}
      onTouchEnd={nav.onTouchEnd}
      onPointerDown={nav.onPointerDown}
      onPointerUp={nav.onPointerUp}
    >
      <BookPaginator
        html={html}
        pageIndex={pageInChapter}
        onPageChange={goToPage}
        onPageCount={setPagesInChapter}
        fontSize={fontSize}
        theme={theme}
        hideChrome
      />
    </div>
  );
}
