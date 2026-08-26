import { useEffect, useRef, type KeyboardEvent as ReactKeyboardEvent, type TouchEvent } from "react";

interface TouchPoint {
  x: number;
  y: number;
  t: number;
}

export interface BookNavigationHandlers {
  onTouchStart: (event: TouchEvent<HTMLElement>) => void;
  onTouchEnd: (event: TouchEvent<HTMLElement>) => void;
  onPointerDown: (event: React.PointerEvent<HTMLElement>) => void;
  onPointerUp: (event: React.PointerEvent<HTMLElement>) => void;
}

function hasTextSelection(): boolean {
  return (window.getSelection()?.toString().trim() ?? "").length > 0;
}

function touchPoint(event: TouchEvent<HTMLElement>, phase: "start" | "end") {
  if (phase === "start") {
    return event.touches[0] ?? event.changedTouches[0];
  }
  return event.changedTouches[0] ?? event.touches[0];
}

/** Deslize, toque nas bordas ou setas do teclado para virar página. */
export function useBookNavigation(
  pageIndex: number,
  pageCount: number,
  onPageChange: (index: number) => void,
  enabled = true,
): BookNavigationHandlers {
  const touchRef = useRef<TouchPoint | null>(null);
  const pointerRef = useRef<TouchPoint | null>(null);
  const pageIndexRef = useRef(pageIndex);
  const pageCountRef = useRef(pageCount);

  pageIndexRef.current = pageIndex;
  pageCountRef.current = pageCount;

  const go = (next: number) => {
    const count = pageCountRef.current;
    if (count <= 0) return;
    onPageChange(Math.max(0, Math.min(next, count - 1)));
  };

  const tapZone = (clientX: number, rect: DOMRect) => {
    const relX = (clientX - rect.left) / rect.width;
    if (relX < 0.3) go(pageIndexRef.current - 1);
    else if (relX > 0.7) go(pageIndexRef.current + 1);
  };

  const onTouchStart = (event: TouchEvent<HTMLElement>) => {
    if (!enabled) return;
    const touch = touchPoint(event, "start");
    if (touch === undefined) return;
    touchRef.current = { x: touch.clientX, y: touch.clientY, t: Date.now() };
  };

  const onTouchEnd = (event: TouchEvent<HTMLElement>) => {
    if (!enabled || touchRef.current === null) return;
    const touch = touchPoint(event, "end");
    if (touch === undefined) return;

    const dx = touch.clientX - touchRef.current.x;
    const dy = touch.clientY - touchRef.current.y;
    const dt = Date.now() - touchRef.current.t;
    touchRef.current = null;

    if (hasTextSelection()) return;

    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.1) {
      go(dx < 0 ? pageIndexRef.current + 1 : pageIndexRef.current - 1);
      return;
    }

    if (dt < 450 && Math.hypot(dx, dy) < 20) {
      tapZone(touch.clientX, event.currentTarget.getBoundingClientRect());
    }
  };

  const onPointerDown = (event: React.PointerEvent<HTMLElement>) => {
    if (!enabled || event.pointerType === "touch") return;
    pointerRef.current = { x: event.clientX, y: event.clientY, t: Date.now() };
  };

  const onPointerUp = (event: React.PointerEvent<HTMLElement>) => {
    if (!enabled || event.pointerType === "touch" || pointerRef.current === null) return;
    const dx = event.clientX - pointerRef.current.x;
    const dy = event.clientY - pointerRef.current.y;
    const dt = Date.now() - pointerRef.current.t;
    pointerRef.current = null;

    if (hasTextSelection()) return;

    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.1) {
      go(dx < 0 ? pageIndexRef.current + 1 : pageIndexRef.current - 1);
      return;
    }

    if (dt < 450 && Math.hypot(dx, dy) < 12) {
      tapZone(event.clientX, event.currentTarget.getBoundingClientRect());
    }
  };

  return { onTouchStart, onTouchEnd, onPointerDown, onPointerUp };
}

/** Setas ← → e PageUp/PageDown no leitor. */
export function useBookKeyboard(
  pageIndex: number,
  pageCount: number,
  onPageChange: (index: number) => void,
  enabled = true,
) {
  useEffect(() => {
    if (!enabled || pageCount <= 0) return;

    const onKeyDown = (event: KeyboardEvent) => {
      const tag = (event.target as HTMLElement | null)?.tagName ?? "";
      if (tag === "TEXTAREA" || tag === "INPUT" || tag === "SELECT") return;

      if (event.key === "ArrowLeft" || event.key === "PageUp") {
        event.preventDefault();
        onPageChange(Math.max(0, pageIndex - 1));
      }
      if (event.key === "ArrowRight" || event.key === "PageDown") {
        event.preventDefault();
        onPageChange(Math.min(pageCount - 1, pageIndex + 1));
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [enabled, onPageChange, pageCount, pageIndex]);
}

/** Impede que setas rolem a página quando o foco está no leitor. */
export function blockArrowScroll(event: ReactKeyboardEvent<HTMLElement>) {
  if (
    event.key === "ArrowLeft" ||
    event.key === "ArrowRight" ||
    event.key === "PageUp" ||
    event.key === "PageDown"
  ) {
    event.preventDefault();
  }
}
