import { pdfjsLib } from "./pdf.js";

export interface PdfProbe {
  pageCount: number;
}

/** Lê só metadados do PDF (número de páginas), sem extrair texto. */
export async function probePdfFile(file: File): Promise<PdfProbe> {
  const data = new Uint8Array(await file.arrayBuffer());
  const loadingTask = pdfjsLib.getDocument({
    data,
    disableStream: true,
    disableAutoFetch: true,
  });
  try {
    const doc = await loadingTask.promise;
    const pageCount = doc.numPages;
    return { pageCount };
  } finally {
    void loadingTask.destroy();
  }
}
