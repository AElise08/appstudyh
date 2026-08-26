import { useEffect, useState, type RefObject } from "react";

/** Observa seleção de texto dentro de um container (funciona em touch + desktop). */
export function useReaderSelection(containerRef: RefObject<HTMLElement | null>) {
  const [quote, setQuote] = useState("");

  useEffect(() => {
    const onSelectionChange = () => {
      const container = containerRef.current;
      const selection = window.getSelection();
      if (container === null || selection === null || selection.isCollapsed) {
        setQuote("");
        return;
      }

      const anchor = selection.anchorNode;
      const focus = selection.focusNode;
      if (
        anchor === null ||
        focus === null ||
        !container.contains(anchor) ||
        !container.contains(focus)
      ) {
        setQuote("");
        return;
      }

      const text = selection.toString().trim();
      setQuote(text.length > 0 ? text : "");
    };

    document.addEventListener("selectionchange", onSelectionChange);
    return () => document.removeEventListener("selectionchange", onSelectionChange);
  }, [containerRef]);

  const clearSelection = () => {
    window.getSelection()?.removeAllRanges();
    setQuote("");
  };

  return { quote, clearSelection };
}
