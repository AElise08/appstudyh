import {
  buildUserMessage,
  PEDAGOGICAL_SYSTEM,
  type AIMode,
} from "./prompt.js";
import { type AISettings } from "./settings.js";

export async function runTutor(
  settings: AISettings,
  mode: AIMode,
  selection: string,
  surrounding: string,
): Promise<string> {
  const userMessage = buildUserMessage(mode, selection, surrounding);
  const response = await fetch(settings.endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${settings.apiKey}`,
    },
    body: JSON.stringify({
      model: settings.model,
      messages: [
        { role: "system", content: PEDAGOGICAL_SYSTEM },
        { role: "user", content: userMessage },
      ],
      temperature: 0.4,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => "");
    throw new Error(body.length > 0 ? body : `Erro ${response.status} ao chamar a IA`);
  }

  const data = (await response.json()) as {
    choices?: { message?: { content?: string } }[];
    text?: string;
  };

  const fromChoices = data.choices?.[0]?.message?.content?.trim();
  if (fromChoices !== undefined && fromChoices.length > 0) return fromChoices;
  if (typeof data.text === "string" && data.text.trim().length > 0) return data.text.trim();
  throw new Error("Resposta vazia da IA.");
}
