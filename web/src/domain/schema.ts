import {
  FLASHCARD_RATINGS,
  NODE_KINDS,
  STUDY_ARTIFACT_KINDS,
  TASK_PRIORITIES,
  WORKSPACE_INDEX_SCHEMA_VERSION,
  WORKSPACE_SCHEMA_VERSION,
  type Review,
  type Workspace,
  type WorkspaceIndexDocument,
} from "./types";

export type DecodeErrorCode =
  | "invalid-json"
  | "invalid-schema-version"
  | "unsupported-schema-version"
  | "invalid-document";

export class DomainDecodeError extends Error {
  constructor(
    readonly code: DecodeErrorCode,
    message: string,
    readonly path?: string,
    readonly foundVersion?: number,
    readonly supportedVersion?: number,
  ) {
    super(message);
    this.name = "DomainDecodeError";
  }
}

type Validator = (value: unknown, path: string) => void;

const record: Validator = (value, path) => {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(path, "object");
};
const string: Validator = (value, path) => {
  if (typeof value !== "string") fail(path, "string");
};
const number: Validator = (value, path) => {
  if (typeof value !== "number" || !Number.isFinite(value)) fail(path, "finite number");
};
const integer: Validator = (value, path) => {
  number(value, path);
  if (!Number.isInteger(value)) fail(path, "integer");
};
const boolean: Validator = (value, path) => {
  if (typeof value !== "boolean") fail(path, "boolean");
};
const uuid: Validator = (value, path) => {
  string(value, path);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value as string)) fail(path, "UUID");
};
const date: Validator = (value, path) => {
  string(value, path);
  if (!/^\d{4}-\d{2}-\d{2}T/.test(value as string) || !Number.isFinite(Date.parse(value as string))) {
    fail(path, "ISO-8601 date");
  }
};
const oneOf =
  (values: readonly string[]): Validator =>
  (value, path) => {
    string(value, path);
    if (!values.includes(value as string)) fail(path, values.join(" | "));
  };
const arrayOf =
  (item: Validator): Validator =>
  (value, path) => {
    if (!Array.isArray(value)) fail(path, "array");
    (value as unknown[]).forEach((entry, index) => item(entry, `${path}[${index}]`));
  };
const nullable =
  (validator: Validator): Validator =>
  (value, path) => {
    if (value !== null) validator(value, path);
  };

function fail(path: string, expected: string): never {
  throw new DomainDecodeError("invalid-document", `${path} must be ${expected}.`, path);
}

function fields(
  value: unknown,
  path: string,
  required: Record<string, Validator>,
  optional: Record<string, Validator> = {},
): asserts value is Record<string, unknown> {
  record(value, path);
  const object = value as Record<string, unknown>;
  for (const [key, validator] of Object.entries(required)) {
    if (!(key in object) || object[key] === null) fail(`${path}.${key}`, "present and non-null");
    validator(object[key], `${path}.${key}`);
  }
  for (const [key, validator] of Object.entries(optional)) {
    // Unknown additive fields are ignored on purpose for forward compatibility.
    if (key in object && object[key] !== undefined) validator(object[key], `${path}.${key}`);
  }
}

const rect: Validator = (value, path) =>
  fields(value, path, { x: number, y: number, width: number, height: number });
const point: Validator = (value, path) => fields(value, path, { x: number, y: number });
const stroke: Validator = (value, path) =>
  fields(value, path, { id: uuid, points: arrayOf(point), width: number }, { colorHex: nullable(string) });
const annotation: Validator = (value, path) =>
  fields(
    value,
    path,
    { id: uuid, quote: string, createdAt: date },
    { note: nullable(string), color: nullable(oneOf(["yellow", "green", "blue", "pink", "purple"])) },
  );
const obsidian: Validator = (value, path) => {
  fields(
    value,
    path,
    {
      relativePath: string,
      vaultName: string,
      frontmatter: record,
      tags: arrayOf(string),
      isDailyNote: boolean,
      importedAt: date,
    },
    {
      status: nullable(string),
      priority: nullable(string),
      color: nullable(string),
      attachmentType: nullable(string),
    },
  );
  const frontmatter = (value as { frontmatter: Record<string, unknown> }).frontmatter;
  for (const [key, entry] of Object.entries(frontmatter)) string(entry, `${path}.frontmatter.${key}`);
};
const node: Validator = (value, path) =>
  fields(
    value,
    path,
    {
      id: uuid,
      kind: oneOf(NODE_KINDS),
      title: string,
      frame: rect,
      zIndex: integer,
      noteBody: string,
      pdfPageIndex: integer,
      pdfSelectedText: string,
      pdfVisibleText: string,
      webURL: string,
      webSelectedText: string,
      calcBody: string,
    },
    {
      linkedNoteID: nullable(uuid),
      pdfBookmark: nullable(string),
      pdfText: nullable(string),
      pdfPageCount: nullable(integer),
      pdfNavigationQuote: nullable(string),
      epubBookmark: nullable(string),
      epubText: nullable(string),
      epubCoverDataUrl: nullable(string),
      epubPageIndex: nullable(integer),
      epubFontSize: nullable(number),
      epubTheme: nullable(oneOf(["automatic", "light", "dark"])),
      epubAnnotations: nullable(arrayOf(annotation)),
      epubVisibleText: nullable(string),
      epubPageCount: nullable(integer),
      webSearchProvider: nullable(string),
      webVisibleText: nullable(string),
      webNavigationQuote: nullable(string),
      inkStrokes: nullable(arrayOf(stroke)),
      inkRecognizedText: nullable(string),
      slidesPages: nullable(arrayOf(string)),
      slidesPageIndex: nullable(integer),
      slidesSelectedText: nullable(string),
      slidesNavigationQuote: nullable(string),
      visitedUnitIndices: nullable(arrayOf(integer)),
      sourceArtifactID: nullable(uuid),
      sourceArtifactCardIndex: nullable(integer),
      sourceArtifactKind: nullable(oneOf(STUDY_ARTIFACT_KINDS)),
      sourceMaterialID: nullable(uuid),
      sourcePageIndex: nullable(integer),
      sourceQuote: nullable(string),
      sourceURL: nullable(string),
      obsidian: nullable(obsidian),
    },
  );
const artifact: Validator = (value, path) =>
  fields(
    value,
    path,
    { id: uuid, kind: oneOf(STUDY_ARTIFACT_KINDS), body: string, createdAt: date },
    {
      sourceNodeID: nullable(uuid),
      sourcePageIndex: nullable(integer),
      sourceQuote: nullable(string),
      sourceURL: nullable(string),
      updatedAt: nullable(date),
      sourceExternalID: nullable(string),
    },
  );
const review: Validator = (value, path) =>
  fields(
    value,
    path,
    { key: string, dueAt: date, intervalDays: number, easeFactor: number, repetitions: integer },
    {
      sourceNodeID: nullable(uuid),
      deckID: nullable(uuid),
      lastRating: nullable(oneOf(FLASHCARD_RATINGS)),
      lastReviewedAt: nullable(date),
      firstReviewedAt: nullable(date),
    },
  );
const history: Validator = (value, path) =>
  fields(value, path, { id: uuid, nodeID: uuid, openedAt: date }, { pageIndex: nullable(integer) });
const connection: Validator = (value, path) =>
  fields(
    value,
    path,
    { id: uuid, fromNodeID: uuid, toNodeID: uuid, kind: oneOf(["wikilink", "canvas"]) },
    { label: nullable(string), externalID: nullable(string), color: nullable(string) },
  );
const event: Validator = (value, path) =>
  fields(
    value,
    path,
    {
      id: uuid,
      kind: oneOf(["openedMaterial", "createdNote", "reviewedFlashcard", "reviewedQuestion", "completedTask"]),
      occurredAt: date,
    },
    { nodeID: nullable(uuid), artifactID: nullable(uuid) },
  );
const task: Validator = (value, path) =>
  fields(value, path, {
    id: uuid,
    title: string,
    dueDate: date,
    priority: oneOf(TASK_PRIORITIES),
    isCompleted: boolean,
    createdAt: date,
  });
const notebook: Validator = (value, path) =>
  fields(
    value,
    path,
    { id: uuid, title: string, plainText: string, createdAt: date, updatedAt: date },
    { rtfData: nullable(string), sourceMaterialID: nullable(uuid), sourcePageIndex: nullable(integer) },
  );
const session: Validator = (value, path) =>
  fields(
    value,
    path,
    { id: uuid, startedAt: date, endedAt: date, plannedMinutes: integer, completedMinutes: integer, intention: string },
    { materialID: nullable(uuid) },
  );
const frame: Validator = (value, path) => fields(value, path, { id: uuid, title: string, rect, createdAt: date });

function parseJSON(input: string | unknown): unknown {
  if (typeof input !== "string") return input;
  try {
    return JSON.parse(input) as unknown;
  } catch {
    throw new DomainDecodeError("invalid-json", "The document is not valid JSON.");
  }
}

/** Missing schemaVersion means legacy document (0); null/negative/non-integer/string are invalid. */
function schemaVersion(value: Record<string, unknown>, supported: number, label: string): number {
  if (!("schemaVersion" in value)) return 0;
  const version = value.schemaVersion;
  if (typeof version !== "number" || !Number.isInteger(version) || version < 0) {
    throw new DomainDecodeError("invalid-schema-version", `The ${label} schema version is invalid.`, "$.schemaVersion");
  }
  if (version > supported) {
    throw new DomainDecodeError(
      "unsupported-schema-version",
      `The ${label} uses schema version ${version}, but only ${supported} is supported.`,
      "$.schemaVersion",
      version,
      supported,
    );
  }
  return version;
}

export function decodeWorkspace(input: string | unknown): Workspace {
  const value = parseJSON(input);
  record(value, "$workspace");
  const object = value as Record<string, unknown>;
  schemaVersion(object, WORKSPACE_SCHEMA_VERSION, "workspace");
  // Flat workspace JSON: the workspace fields live at the top level of the document.
  fields(
    value,
    "$workspace",
    {
      id: uuid,
      name: string,
      nodes: arrayOf(node),
      cameraX: number,
      cameraY: number,
      cameraScale: number,
      updatedAt: date,
    },
    {
      schemaVersion: integer,
      inkStrokes: nullable(arrayOf(stroke)),
      studyArtifacts: nullable(arrayOf(artifact)),
      flashcardReviews: nullable(arrayOf(review)),
      studyHistory: nullable(arrayOf(history)),
      examDate: nullable(date),
      presentationDate: nullable(date),
      connections: nullable(arrayOf(connection)),
      obsidianVaultBookmark: nullable(string),
      obsidianVaultName: nullable(string),
      studyActivityEvents: nullable(arrayOf(event)),
      studyTasks: nullable(arrayOf(task)),
      notebooks: nullable(arrayOf(notebook)),
      focusSessions: nullable(arrayOf(session)),
      frames: nullable(arrayOf(frame)),
    },
  );
  return { ...object, schemaVersion: WORKSPACE_SCHEMA_VERSION } as unknown as Workspace;
}

export function decodeWorkspaceIndexDocument(input: string | unknown): WorkspaceIndexDocument {
  const value = parseJSON(input);
  record(value, "$index");
  const object = value as Record<string, unknown>;
  const version = schemaVersion(object, WORKSPACE_INDEX_SCHEMA_VERSION, "workspace index");
  fields(
    value,
    "$index",
    { workspaceIDs: arrayOf(uuid) },
    { schemaVersion: integer, selectedID: nullable(uuid) },
  );
  return { ...object, schemaVersion: version } as unknown as WorkspaceIndexDocument;
}

export function encodeWorkspace(workspace: Workspace): string {
  return JSON.stringify({ ...workspace, schemaVersion: WORKSPACE_SCHEMA_VERSION });
}

export function encodeWorkspaceIndex(index: WorkspaceIndexDocument): string {
  return JSON.stringify({ ...index, schemaVersion: WORKSPACE_INDEX_SCHEMA_VERSION });
}
