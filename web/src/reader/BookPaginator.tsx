import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { EPUBReaderTheme } from "../domain/types.js";
import BookNavLayer from "./BookNavLayer.js";
import "./bookPaginator.css";

/** Espaço reservado no fim da coluna para não cortar descendentes da última linha. */
const PAGE_BOTTOM_GUTTER = 44;

export interface BookPaginatorProps {
  html: string;
  pageIndex: number;
  onPageChange: (index: number) => void;
  onPageCount: (count: number) => void;
  fontSize: number;
  theme?: EPUBReaderTheme | null;
  /** Sem gestos/nav internos — o pai controla (EpubBookReader). */
  hideChrome?: boolean;
}

export default function BookPaginator({
  html,
  pageIndex,
  onPageChange,
  onPageCount,
  fontSize,
  theme = "light",
  hideChrome = false,
}: BookPaginatorProps) {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const sheetRef = useRef<HTMLDivElement | null>(null);
  const onPageCountRef = useRef(onPageCount);
  const [layout, setLayout] = useState({ width: 0, height: 0, pages: 1 });

  onPageCountRef.current = onPageCount;

  useLayoutEffect(() => {
    const viewport = viewportRef.current;
    const sheet = sheetRef.current;
    if (viewport === null || sheet === null) return;

    let frame = 0;
    const measure = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        const width = Math.floor(viewport.clientWidth);
        const height = Math.floor(viewport.clientHeight);
        if (width <= 0 || height <= 0) return;

        const columnHeight = Math.max(120, height - PAGE_BOTTOM_GUTTER);

        sheet.style.height = `${columnHeight}px`;
        sheet.style.columnWidth = `${width}px`;
        sheet.style.width = "auto";
        sheet.style.fontSize = `${fontSize}px`;
        sheet.style.transform = "translateX(0)";

        const pages = Math.max(1, Math.ceil(sheet.scrollWidth / width));
        setLayout({ width, height: columnHeight, pages });
        onPageCountRef.current(pages);
      });
    };

    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(viewport);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [fontSize, html]);

  const clampedIndex = Math.max(0, Math.min(pageIndex, layout.pages - 1));

  useEffect(() => {
    if (clampedIndex !== pageIndex) onPageChange(clampedIndex);
  }, [clampedIndex, onPageChange, pageIndex]);

  const pageWidth = layout.width;
  const pageShift = pageWidth > 0 ? clampedIndex * pageWidth : 0;

  return (
    <div className="book-paginator" ref={viewportRef} data-theme={theme ?? "light"}>
      <div className="book-paginator__frame">
        <div
          ref={sheetRef}
          className="book-paginator__sheet"
          style={{
            transform: `translateX(-${pageShift}px)`,
            width: pageWidth > 0 ? pageWidth * layout.pages : undefined,
            height: layout.height,
            columnWidth: pageWidth,
            fontSize,
          }}
          dangerouslySetInnerHTML={{ __html: html }}
        />
      </div>
      {!hideChrome && (
        <BookNavLayer
          pageIndex={clampedIndex}
          pageCount={layout.pages}
          onPrev={() => onPageChange(clampedIndex - 1)}
          onNext={() => onPageChange(clampedIndex + 1)}
        />
      )}
    </div>
  );
}
