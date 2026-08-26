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
  coverDataUrl?: string | null;
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

export function isEpubFile(file: Pick<File, "name" | "type">): boolean {
  if (file.name.toLowerCase().endsWith(".epub")) return true;
  const mime = file.type.toLowerCase();
  return mime === "application/epub+zip" || mime === "application/x-epub+zip";
}

export async function importMaterialFile(file: File): Promise<ExtractResult> {
  const lower = file.name.toLowerCase();
  if (lower.endsWith(".pdf") || file.type.toLowerCase() === "application/pdf") return extractPDF(file);
  if (isEpubFile(file)) return extractEPUB(file);
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
    loadingTask = pdfjsLib.getDocument({
      data,
      disableStream: true,
      disableAutoFetch: true,
    });
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

function safeDecodeUri(value: string): string {
  try {
    return decodeURI(value);
  } catch {
    return value;
  }
}

/** Localiza o href da capa no manifest (EPUB3 cover-image ou EPUB2 meta cover). */
export function findCoverManifestHref(opfXml: string, opfPath: string): string | null {
  const doc = parseXml(opfXml, "package.opf");
  const base = opfPath.includes("/") ? opfPath.slice(0, opfPath.lastIndexOf("/") + 1) : "";
  const manifestById = new Map<string, string>();

  for (const item of doc.querySelectorAll("manifest > item")) {
    const id = item.getAttribute("id");
    const href = item.getAttribute("href");
    if (id !== null && href !== null) manifestById.set(id, href);

    const properties = (item.getAttribute("properties") ?? "").split(/\s+/);
    if (properties.includes("cover-image") && href !== null) {
      return resolveZipPath(base, safeDecodeUri(href));
    }
  }

  const coverId = doc.querySelector('meta[name="cover"]')?.getAttribute("content") ?? "";
  if (coverId.length > 0) {
    const href = manifestById.get(coverId);
    if (href !== undefined) return resolveZipPath(base, safeDecodeUri(href));
  }

  return null;
}

function embeddedImagePayloadLength(src: string): number {
  const comma = src.indexOf(",");
  return comma >= 0 ? src.length - comma - 1 : src.length;
}

/** Escolhe a melhor capa entre capítulos — evita logos pequenos do início do livro. */
export function pickBestCoverFromChapters(chapters: string[]): string | null {
  let best: { src: string; score: number } | null = null;

  for (const chapter of chapters) {
    const doc = new DOMParser().parseFromString(chapter, "text/html");
    const chapterText = (doc.body.textContent ?? "").replace(/\s+/g, " ").trim();
    const shortChapter = chapterText.length < 120;

    for (const img of doc.querySelectorAll("img[src]")) {
      const src = img.getAttribute("src")?.trim() ?? "";
      if (!/^data:image\//i.test(src)) continue;

      const alt = (img.getAttribute("alt") ?? "").toLowerCase();
      const cls = (img.getAttribute("class") ?? "").toLowerCase();
      const hints = `${alt} ${cls}`;
      let score = 0;

      if (cls.includes("epub-cover") || cls.includes("cover")) score += 120;
      if (/capa|cover/.test(hints)) score += 90;
      if (shortChapter) score += 50;
      if (/logo|livros|watermark|icon|badge|selo/.test(hints)) score -= 120;
      if (/svg\+xml/i.test(src)) score -= 150;

      const payload = embeddedImagePayloadLength(src);
      if (payload < 6_000) score -= 80;
      else if (payload > 18_000) score += 35;
      else if (payload > 10_000) score += 15;

      if (best === null || score > best.score) {
        best = { src, score };
      }
    }
  }

  if (best === null || best.score < -40) return null;
  return best.src;
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

  const zipIndex = buildZipIndex(zip);

  const chapters: string[] = [];
  for (const item of spine) {
    if (chapters.length >= MAX_EPUB_CHAPTERS) break;
    if (item.isNav) continue;
    const entry = findZipEntry(zipIndex, item.href);
    if (entry === null) continue;
    const raw = await entry.async("string");
    let html = await inlineEpubChapterImages(raw, zipIndex, item.href);
    html = sanitizeChapterHtml(html);
    const plainLen = htmlChapterToText(raw).length;
    const hasImage = /<img\s/i.test(html);
    const visibleText = html.replace(/<[^>]+>/g, "").trim().length;
    if (plainLen < MIN_EPUB_CHAPTER_CHARS && visibleText < MIN_EPUB_CHAPTER_CHARS && !hasImage) {
      continue;
    }
    chapters.push(html);
  }

  if (chapters.length === 0) {
    // Última tentativa: inclui capítulos curtos (capa, dedicatória, etc.)
    for (const item of spine) {
      if (item.isNav) continue;
      const entry = findZipEntry(zipIndex, item.href);
      if (entry === null) continue;
      const raw = await entry.async("string");
      let html = await inlineEpubChapterImages(raw, zipIndex, item.href);
      html = sanitizeChapterHtml(html);
      if (html.replace(/<[^>]+>/g, "").trim().length === 0 && !/<img\s/i.test(html)) continue;
      chapters.push(html);
      if (chapters.length >= MAX_EPUB_CHAPTERS) break;
    }
  }

  if (chapters.length === 0) {
    throw new Error(
      "Não foi possível extrair texto deste EPUB. Ele pode ser protegido por DRM ou conter apenas imagens.",
    );
  }

  const coverHref = findCoverManifestHref(opfXml, opfPath);
  const coverFromManifest =
    coverHref !== null ? await resolveImageDataUrl(coverHref, zipIndex, "") : null;
  const coverDataUrl = coverFromManifest ?? pickBestCoverFromChapters(chapters);

  return {
    kind: "epub",
    title: opfTitle(opfXml) ?? stripFileName(file.name),
    pageCount: chapters.length,
    pages: chapters,
    coverDataUrl,
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

/** Capítulos salvos antes da correção de imagens precisam ser reimportados. */
export function epubChaptersNeedImageInlining(chapters: string[]): boolean {
  return chapters.some((chapter) => {
    if (/<img[^>]+src=["'](?!data:)(?!https?:)(?!blob:)/i.test(chapter)) return true;
    if (/<image[^>]+(?:href|xlink:href)=["'](?!data:)(?!https?:)(?!blob:)/i.test(chapter)) return true;
    if (/url\(\s*['"]?(?!data:|https?:|blob:)[^'")]+['"]?\s*\)/i.test(chapter)) return true;
    return false;
  });
}

type ZipEntry = import("jszip").JSZipObject;
type ZipIndex = Map<string, ZipEntry>;

function normalizeZipPath(path: string): string {
  let decoded = path;
  try {
    decoded = decodeURIComponent(path);
  } catch {
    decoded = path;
  }
  return decoded.replace(/\\/g, "/").replace(/^\/+/, "");
}

function buildZipIndex(zip: import("jszip")): ZipIndex {
  const index: ZipIndex = new Map();
  zip.forEach((relativePath, file) => {
    if (file.dir) return;
    const norm = normalizeZipPath(relativePath);
    index.set(norm, file);
    index.set(norm.toLowerCase(), file);
  });
  return index;
}

function guessImageMime(path: string): string {
  const lower = path.toLowerCase();
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".svg")) return "image/svg+xml";
  return "image/jpeg";
}

function findZipEntry(index: ZipIndex, path: string): ZipEntry | null {
  const norm = normalizeZipPath(path.split("#")[0] ?? path);
  const direct = index.get(norm) ?? index.get(norm.toLowerCase());
  if (direct !== undefined) return direct;

  const fileName = norm.split("/").pop();
  if (fileName === undefined || fileName.length === 0) return null;

  const lowerName = fileName.toLowerCase();
  for (const [key, entry] of index) {
    if (key.split("/").pop()?.toLowerCase() === lowerName) return entry;
  }
  return null;
}

function chapterBase(chapterHref: string): string {
  return chapterHref.includes("/") ? chapterHref.slice(0, chapterHref.lastIndexOf("/") + 1) : "";
}

function isExternalAssetUrl(url: string): boolean {
  return /^(data:|https?:|blob:|\/\/)/i.test(url.trim());
}

function firstUrlFromSrcset(srcset: string): string | null {
  const first = srcset.split(",")[0]?.trim().split(/\s+/)[0]?.trim() ?? "";
  return first.length > 0 ? first : null;
}

async function resolveImageDataUrl(
  href: string,
  index: ZipIndex,
  base: string,
): Promise<string | null> {
  const clean = href.trim().split("#")[0] ?? "";
  if (clean.length === 0 || isExternalAssetUrl(clean)) return null;

  const resolved = resolveZipPath(base, clean);
  const entry = findZipEntry(index, resolved);
  if (entry === null) return null;

  try {
    const mime = guessImageMime(resolved);
    const b64 = await entry.async("base64");
    return `data:${mime};base64,${b64}`;
  } catch {
    return null;
  }
}

async function setImageSource(
  el: Element,
  href: string,
  index: ZipIndex,
  base: string,
): Promise<boolean> {
  const dataUrl = await resolveImageDataUrl(href, index, base);
  if (dataUrl === null) return false;
  if (el.tagName.toLowerCase() === "img") {
    el.setAttribute("src", dataUrl);
    el.removeAttribute("srcset");
  } else {
    el.setAttribute("href", dataUrl);
    el.setAttributeNS("http://www.w3.org/1999/xlink", "href", dataUrl);
  }
  return true;
}

/** Capas via CSS (comum em EPUBs Le Livros) viram <img> antes do sanitize remover <style>. */
async function promoteCssBackgroundImages(
  doc: Document,
  index: ZipIndex,
  base: string,
): Promise<void> {
  if (doc.body.querySelector("img[src]") !== null) return;

  for (const styleEl of doc.querySelectorAll("style")) {
    const css = styleEl.textContent ?? "";
    const match = css.match(/url\(\s*['"]?([^'")]+)['"]?\s*\)/i);
    if (match?.[1] === undefined) continue;
    const dataUrl = await resolveImageDataUrl(match[1], index, base);
    if (dataUrl === null) continue;
    const img = doc.createElement("img");
    img.setAttribute("src", dataUrl);
    img.setAttribute("alt", "");
    img.className = "epub-cover";
    doc.body.insertBefore(img, doc.body.firstChild);
    return;
  }

  for (const el of doc.querySelectorAll("[style]")) {
    const style = el.getAttribute("style") ?? "";
    const match = style.match(/url\(\s*['"]?([^'")]+)['"]?\s*\)/i);
    if (match?.[1] === undefined) continue;
    const dataUrl = await resolveImageDataUrl(match[1], index, base);
    if (dataUrl === null) continue;
    const img = doc.createElement("img");
    img.setAttribute("src", dataUrl);
    img.setAttribute("alt", "");
    img.className = "epub-cover";
    doc.body.insertBefore(img, doc.body.firstChild);
    return;
  }
}

/** Converte imagens relativas do EPUB em data URLs embutidas. */
export async function inlineEpubChapterImages(
  html: string,
  zipOrIndex: import("jszip") | ZipIndex,
  chapterHref: string,
): Promise<string> {
  const index = zipOrIndex instanceof Map ? zipOrIndex : buildZipIndex(zipOrIndex);
  const doc = new DOMParser().parseFromString(html, "text/html");
  const base = chapterBase(chapterHref);

  await promoteCssBackgroundImages(doc, index, base);

  for (const img of doc.querySelectorAll("img")) {
    const src = img.getAttribute("src")?.trim() ?? "";
    const srcset = img.getAttribute("srcset")?.trim() ?? "";
    const candidate = src.length > 0 ? src : (firstUrlFromSrcset(srcset) ?? "");
    if (candidate.length === 0 || isExternalAssetUrl(candidate)) continue;

    const ok = await setImageSource(img, candidate, index, base);
    if (!ok && src.length > 0) img.remove();
  }

  for (const image of doc.querySelectorAll("image")) {
    const href =
      image.getAttribute("href")?.trim() ??
      image.getAttributeNS("http://www.w3.org/1999/xlink", "href")?.trim() ??
      image.getAttribute("xlink:href")?.trim() ??
      "";
    if (href.length === 0 || isExternalAssetUrl(href)) continue;
    const ok = await setImageSource(image, href, index, base);
    if (!ok) image.remove();
  }

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
