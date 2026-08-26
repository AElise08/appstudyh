export interface AISettings {
  endpoint: string;
  apiKey: string;
  model: string;
}

const STORAGE_KEY = "studyh.ai.settings";

const DEFAULTS: AISettings = {
  endpoint: "https://api.openai.com/v1/chat/completions",
  apiKey: "",
  model: "gpt-4.1-mini",
};

export function loadAISettings(): AISettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === null) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<AISettings>;
    return { ...DEFAULTS, ...parsed };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveAISettings(settings: AISettings): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
}

export function isAIConfigured(settings: AISettings): boolean {
  return settings.apiKey.trim().length > 0 && settings.endpoint.trim().length > 0;
}
