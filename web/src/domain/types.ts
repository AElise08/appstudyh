export const WORKSPACE_SCHEMA_VERSION = 1 as const;
export const WORKSPACE_INDEX_SCHEMA_VERSION = 1 as const;

export type UUID = string;
export type ISODateString = string;
export type Base64String = string;

export const NODE_KINDS = ["note", "pdf", "epub", "web", "calc", "slides"] as const;
export type NodeKind = (typeof NODE_KINDS)[number];

export interface CanvasRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface InkPoint { x: number; y: number }
export interface InkStroke {
  id: UUID;
  points: InkPoint[];
  width: number;
  colorHex?: string | null;
}

export interface ObsidianMetadata {
  relativePath: string;
  vaultName: string;
  frontmatter: Record<string, string>;
  tags: string[];
  status?: string | null;
  priority?: string | null;
  color?: string | null;
  isDailyNote: boolean;
  attachmentType?: string | null;
  importedAt: ISODateString;
}

export type CanvasConnectionKind = "wikilink" | "canvas";
export interface Connection {
  id: UUID;
  fromNodeID: UUID;
  toNodeID: UUID;
  label?: string | null;
  kind: CanvasConnectionKind;
  externalID?: string | null;
  color?: string | null;
}

export type EPUBReaderTheme = "automatic" | "light" | "dark";
export type EPUBHighlightColor = "yellow" | "green" | "blue" | "pink" | "purple";
export interface EPUBAnnotation {
  id: UUID;
  quote: string;
  note?: string | null;
  color?: EPUBHighlightColor | null;
  createdAt: ISODateString;
}

export interface StudyFrame {
  id: UUID;
  title: string;
  rect: CanvasRect;
  createdAt: ISODateString;
}

export const STUDY_ARTIFACT_KINDS = [
  "summary", "userMessage", "assistantMessage", "flashcards", "question", "feedback", "note",
] as const;
export type ArtifactKind = (typeof STUDY_ARTIFACT_KINDS)[number];

export interface CanvasNode {
  id: UUID;
  kind: NodeKind;
  title: string;
  frame: CanvasRect;
  zIndex: number;
  noteBody: string;
  linkedNoteID?: UUID | null;
  pdfBookmark?: Base64String | null;
  pdfPageIndex: number;
  pdfSelectedText: string;
  pdfVisibleText: string;
  pdfText?: string | null;
  pdfPageCount?: number | null;
  pdfNavigationQuote?: string | null;
  epubBookmark?: Base64String | null;
  epubText?: string | null;
  epubCoverDataUrl?: string | null;
  epubPageIndex?: number | null;
  epubFontSize?: number | null;
  epubTheme?: EPUBReaderTheme | null;
  epubAnnotations?: EPUBAnnotation[] | null;
  epubVisibleText?: string | null;
  epubPageCount?: number | null;
  webURL: string;
  webSelectedText: string;
  webSearchProvider?: string | null;
  webVisibleText?: string | null;
  webNavigationQuote?: string | null;
  calcBody: string;
  inkStrokes?: InkStroke[] | null;
  inkRecognizedText?: string | null;
  slidesPages?: string[] | null;
  slidesPageIndex?: number | null;
  slidesSelectedText?: string | null;
  slidesNavigationQuote?: string | null;
  visitedUnitIndices?: number[] | null;
  sourceArtifactID?: UUID | null;
  sourceArtifactCardIndex?: number | null;
  sourceArtifactKind?: ArtifactKind | null;
  sourceMaterialID?: UUID | null;
  sourcePageIndex?: number | null;
  sourceQuote?: string | null;
  sourceURL?: string | null;
  obsidian?: ObsidianMetadata | null;
}

export interface Artifact {
  id: UUID;
  kind: ArtifactKind;
  body: string;
  sourceNodeID?: UUID | null;
  createdAt: ISODateString;
  sourcePageIndex?: number | null;
  sourceQuote?: string | null;
  sourceURL?: string | null;
  updatedAt?: ISODateString | null;
  sourceExternalID?: string | null;
}

export const FLASHCARD_RATINGS = ["hard", "good", "easy"] as const;
export type ReviewRating = (typeof FLASHCARD_RATINGS)[number];
export interface Review {
  key: string;
  sourceNodeID?: UUID | null;
  deckID?: UUID | null;
  dueAt: ISODateString;
  intervalDays: number;
  easeFactor: number;
  repetitions: number;
  lastRating?: ReviewRating | null;
  lastReviewedAt?: ISODateString | null;
  firstReviewedAt?: ISODateString | null;
}

export interface HistoryEntry {
  id: UUID;
  nodeID: UUID;
  openedAt: ISODateString;
  pageIndex?: number | null;
}

export type ActivityEventKind =
  | "openedMaterial"
  | "createdNote"
  | "reviewedFlashcard"
  | "reviewedQuestion"
  | "completedTask";
export interface ActivityEvent {
  id: UUID;
  kind: ActivityEventKind;
  nodeID?: UUID | null;
  artifactID?: UUID | null;
  occurredAt: ISODateString;
}

export const TASK_PRIORITIES = ["high", "normal", "low"] as const;
export type TaskPriority = (typeof TASK_PRIORITIES)[number];
export interface Task {
  id: UUID;
  title: string;
  dueDate: ISODateString;
  priority: TaskPriority;
  isCompleted: boolean;
  createdAt: ISODateString;
}

export interface Notebook {
  id: UUID;
  title: string;
  rtfData?: Base64String | null;
  plainText: string;
  createdAt: ISODateString;
  updatedAt: ISODateString;
  sourceMaterialID?: UUID | null;
  sourcePageIndex?: number | null;
}

export interface FocusSession {
  id: UUID;
  startedAt: ISODateString;
  endedAt: ISODateString;
  plannedMinutes: number;
  completedMinutes: number;
  intention: string;
  materialID?: UUID | null;
}

export interface Workspace {
  schemaVersion: typeof WORKSPACE_SCHEMA_VERSION;
  id: UUID;
  name: string;
  nodes: CanvasNode[];
  cameraX: number;
  cameraY: number;
  cameraScale: number;
  updatedAt: ISODateString;
  inkStrokes?: InkStroke[] | null;
  studyArtifacts?: Artifact[] | null;
  flashcardReviews?: Review[] | null;
  studyHistory?: HistoryEntry[] | null;
  examDate?: ISODateString | null;
  presentationDate?: ISODateString | null;
  connections?: Connection[] | null;
  obsidianVaultBookmark?: Base64String | null;
  obsidianVaultName?: string | null;
  studyActivityEvents?: ActivityEvent[] | null;
  studyTasks?: Task[] | null;
  notebooks?: Notebook[] | null;
  focusSessions?: FocusSession[] | null;
  frames?: StudyFrame[] | null;
}

export interface WorkspaceIndexDocument {
  schemaVersion: typeof WORKSPACE_INDEX_SCHEMA_VERSION;
  workspaceIDs: UUID[];
  selectedID?: UUID | null;
}
