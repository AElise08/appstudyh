/**
 * Material import/extract pipeline: PDF, EPUB and plain text files are turned
 * into a uniform `{ kind, title, pageCount, pages }` shape. Heavy dependencies
 * (pdf.js, JSZip) are loaded lazily so pure helpers stay testable in Node.
 */

const MAX_PDF_PAGES = 300;
const MAX_EPUB_CHAPTERS = 200;
const MIN_EPUB_CHAPTER_CHARS = 40;

export interface ExtractedPdf {
  kind: "pdf";
  title: string;
  pageCount: number;
  pages: string[];
}

export interface ExtractedEpub {
  kind: "epub";
  title: string;
  pageCount: number;
  pages: string[];
}

export interface ExtractedNote {
  kind: "note";
  title: string;
  pageCount: number;
  pages: string[];
}

export type ExtractResult = ExtractedPdf | ExtractedEpub | ExtractedNote;

/** Splits extracted text into reader pages on `\n---\n` separators. */
export function splitPages(text: string): string[] {
  return text.split(/\n-{3,}\n/);
}

export function stripFileName(name: string): string {
  return name.replace(/\.(pdf|epub|txt|md|markdown)$/i, "");
}

export async function importMaterialFile(file: File): Promise<ExtractResult> {
  const lower = file.name.toLowerCase();
  if (lower.endsWith(".pdf")) return extractPDF(file);
  if (lower.endsWith(".epub")) return extractEPUB(file);
  if (lower.endsWith(".txt") || lower.endsWith(".md") || lower.endsWith(".markdown")) {
    return extractTextFile(file);
  }
  throw new Error("Formato não suportado. Envie um arquivo .pdf, .epub, .txt ou .md.");
}

export async function extractTextFile(file: File): Promise<ExtractedNote> {
  const text = await file.text();
  const pages = splitPages(text);
  return { kind: "note", title: stripFileName(file.name), pageCount: pages.length, pages };
}

export async function extractPDF(file: File): Promise<ExtractedPdf> {
  const { pdfjsLib } = await import("./pdf.js");
  const data = new Uint8Array(await file.arrayBuffer());
  let loadingTask;
  try {
    loadingTask = pdfjsLib.getDocument({ data });
  } catch {
    throw new Error("Não foi possível abrir o PDF. O arquivo pode estar corrompido.");
  }
  let doc;
  try {
    doc = await loadingTask.promise;
  } catch (err) {
    void loadingTask.destroy();
    const name = (err as { name?: string } | null)?.name ?? "";
    if (name.includes("Password")) {
      throw new Error("Este PDF é protegido por senha e não pode ser importado.");
    }
    throw new Error("Não foi possível abrir o PDF. O arquivo pode estar corrompido.");
  }
  try {
    const total = Math.min(doc.numPages, MAX_PDF_PAGES);
    const pages: string[] = [];
    for (let index = 1; index <= total; index += 1) {
      const page = await doc.getPage(index);
      const content = await page.getTextContent();
      const raw = content.items
        .map((item) => ("str" in item ? item.str : ""))
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
      pages.push(raw);
      page.cleanup();
    }
    return {
      kind: "pdf",
      title: stripFileName(file.name),
      pageCount: pages.length,
      pages,
    };
  } finally {
    await loadingTask.destroy();
  }
}

// ---------- EPUB ----------

export interface SpineItem {
  idref: string;
  /** Zip path resolved against the OPF directory. */
  href: string;
  /** True when the manifest item declares `properties` containing "nav". */
  isNav: boolean;
}

/** Extracts the OPF package path from META-INF/container.xml. */
export function findOpfPath(containerXml: string): string {
  const doc = parseXml(containerXml, "container.xml");
  const fullPath = doc.querySelector("rootfile")?.getAttribute("full-path") ?? "";
  if (fullPath.length === 0) {
    throw new Error("EPUB inválido: o pacote OPF não foi encontrado dentro do arquivo.");
  }
  return fullPath;
}

/** Pure spine parser: container.xml + OPF -> ordered chapter hrefs. */
export function parseSpine(containerXml: string, opfXml: string): SpineItem[] {
  const opfPath = findOpfPath(containerXml);
  const opfDoc = parseXml(opfXml, "package.opf");

  interface ManifestEntry {
    href: string;
    isNav: boolean;
  }
  const manifest = new Map<string, ManifestEntry>();
  for (const item of opfDoc.querySelectorAll("manifest > item")) {
    const id = item.getAttribute("id");
    const href = item.getAttribute("href");
    if (id === null || href === null) continue;
    const properties = (item.getAttribute("properties") ?? "").split(/\s+/);
    manifest.set(id, { href, isNav: properties.includes("nav") });
  }

  const base = opfPath.includes("/") ? opfPath.slice(0, opfPath.lastIndexOf("/") + 1) : "";
  const items: SpineItem[] = [];
  for (const ref of opfDoc.querySelectorAll("spine > itemref")) {
    const idref = ref.getAttribute("idref");
    if (idref === null) continue;
    const entry = manifest.get(idref);
    if (entry === undefined) continue;
    let decoded = entry.href;
    try {
      decoded = decodeURI(entry.href);
    } catch {
      // keep raw href when it is not valid percent-encoding
    }
    items.push({ idref, href: resolveZipPath(base, decoded), isNav: entry.isNav });
  }
  return items;
}

export function opfTitle(opfXml: string): string | null {
  const doc = parseXml(opfXml, "package.opf");
  const title = doc.querySelector("title")?.textContent?.trim() ?? "";
  return title.length > 0 ? title : null;
}

export async function extractEPUB(file: File): Promise<ExtractedEpub> {
  const { default: JSZip } = await import("jszip");
  let zip;
  try {
    zip = await JSZip.loadAsync(await file.arrayBuffer());
  } catch {
    throw new Error("Não foi possível abrir o EPUB. O arquivo pode estar corrompido.");
  }

  const containerEntry = zip.file("META-INF/container.xml");
  if (containerEntry === null) {
    throw new Error("Arquivo EPUB inválido: estrutura interna ausente (META-INF/container.xml).");
  }
  const containerXml = await containerEntry.async("string");
  const opfPath = findOpfPath(containerXml);
  const opfEntry = zip.file(opfPath);
  if (opfEntry === null) {
    throw new Error(`EPUB inválido: o pacote "${opfPath}" não foi encontrado dentro do arquivo.`);
  }
  const opfXml = await opfEntry.async("string");
  const spine = parseSpine(containerXml, opfXml);

  const chapters: string[] = [];
  for (const item of spine) {
    if (chapters.length >= MAX_EPUB_CHAPTERS) break;
    if (item.isNav) continue;
    const entry = zip.file(item.href);
    if (entry === null) continue;
    const raw = await entry.async("string");
    const text = htmlChapterToText(raw);
    if (text.length < MIN_EPUB_CHAPTER_CHARS) continue;
    chapters.push(text);
  }

  if (chapters.length === 0) {
    throw new Error(
      "Não foi possível extrair texto deste EPUB. Ele pode ser protegido por DRM ou conter apenas imagens.",
    );
  }

  return {
    kind: "epub",
    title: opfTitle(opfXml) ?? stripFileName(file.name),
    pageCount: chapters.length,
    pages: chapters,
  };
}

// ---------- Sanitizer + chapter text ----------

const SANITIZE_REMOVE_SELECTOR = "script, style, noscript, iframe, object, embed, link, meta";

/** DOMPurify-free sanitizer: drops dangerous nodes, on* attributes and javascript: URLs. */
export function sanitizeChapterHtml(html: string): string {
  const doc = new DOMParser().parseFromString(html, "text/html");
  doc.querySelectorAll(SANITIZE_REMOVE_SELECTOR).forEach((el) => el.remove());
  doc.body.querySelectorAll("*").forEach((el) => {
    for (const attr of [...Array.from(el.attributes)]) {
      const name = attr.name.toLowerCase();
      if (name.startsWith("on")) {
        el.removeAttribute(attr.name);
        continue;
      }
      if (
        (name === "href" || name === "src" || name === "xlink:href") &&
        attr.value.trim().toLowerCase().startsWith("javascript:")
      ) {
        el.removeAttribute(attr.name);
      }
    }
  });
  return doc.body.innerHTML;
}

const BLOCK_TAGS = new Set([
  "address", "article", "aside", "blockquote", "details", "dialog", "dd", "div", "dl", "dt",
  "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6",
  "header", "hgroup", "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "tbody",
  "thead", "tfoot", "tr", "td", "th", "ul",
]);

const STRIP_SELECTOR = "script, style, noscript, nav, svg, head, title";

/** Chapter XHTML -> plain text: strips junk, converts block boundaries to newlines. */
export function htmlChapterToText(html: string): string {
  const doc = new DOMParser().parseFromString(html, "text/html");
  doc.querySelectorAll(STRIP_SELECTOR).forEach((el) => el.remove());
  const parts: string[] = [];
  appendNodeText(doc.body, parts);
  return parts
    .join("")
    .replace(/[\t\u00a0]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/ {2,}/g, " ")
    .replace(/\n{2,}/g, "\n")
    .trim();
}

function appendNodeText(node: Node, parts: string[]): void {
  for (const child of Array.from(node.childNodes)) {
    if (child.nodeType === Node.TEXT_NODE) {
      parts.push(child.textContent ?? "");
      continue;
    }
    if (child.nodeType !== Node.ELEMENT_NODE) continue;
    const tag = (child as Element).tagName.toLowerCase();
    if (tag === "br") {
      parts.push("\n");
    } else if (BLOCK_TAGS.has(tag)) {
      appendNodeText(child, parts);
      parts.push("\n");
    } else {
      appendNodeText(child, parts);
    }
  }
}

// ---------- Path helpers ----------

/** Resolves an EPUB href against the OPF directory inside the zip. */
export function resolveZipPath(base: string, href: string): string {
  const out: string[] = [];
  for (const segment of `${base}${href}`.split("/")) {
    if (segment === "" || segment === ".") continue;
    if (segment === "..") {
      out.pop();
      continue;
    }
    out.push(segment);
  }
  return out.join("/");
}

function parseXml(xml: string, label: string): Document {
  const doc = new DOMParser().parseFromString(xml, "application/xml");
  if (doc.querySelector("parsererror") !== null) {
    throw new Error(`EPUB inválido: falha ao ler ${label}. O arquivo pode estar protegido por DRM.`);
  }
  return doc;
}
