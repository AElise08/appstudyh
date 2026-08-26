import { findOpfPath, opfTitle, parseSpine } from "./extract.js";

export interface EpubProbe {
  pageCount: number;
  title: string;
}

/** Lê spine do EPUB sem extrair o texto dos capítulos. */
export async function probeEpubFile(file: File): Promise<EpubProbe> {
  const { default: JSZip } = await import("jszip");
  const zip = await JSZip.loadAsync(await file.arrayBuffer());

  const containerEntry = zip.file("META-INF/container.xml");
  if (containerEntry === null) {
    throw new Error("Arquivo EPUB inválido.");
  }
  const containerXml = await containerEntry.async("string");
  const opfPath = findOpfPath(containerXml);
  const opfEntry = zip.file(opfPath);
  if (opfEntry === null) {
    throw new Error("Arquivo EPUB inválido.");
  }
  const opfXml = await opfEntry.async("string");
  const spine = parseSpine(containerXml, opfXml).filter((item) => !item.isNav);

  return {
    pageCount: Math.max(1, spine.length),
    title: opfTitle(opfXml) ?? file.name.replace(/\.epub$/i, ""),
  };
}
