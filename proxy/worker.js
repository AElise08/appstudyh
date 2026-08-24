// Proxy Studyh para "Entrar com ChatGPT" (openai-oauth).
//
// Por que existe: o chatgpt.com bloqueia chamadas diretas do navegador (CORS),
// então as credenciais OAuth do usuário precisam passar por um servidor seu.
// Este Worker recebe os headers do openai-oauth, chama o endpoint Codex do
// ChatGPT e devolve apenas o texto da resposta.
//
// Deploy:
//   1. npm create cloudflare@latest studyh-proxy
//   2. Substitua src/index.ts por este arquivo e adicione:
//        npm i @openai-oauth/web@server @openai-oauth/ai-sdk ai
//      (no Worker, importe de "@openai-oauth/web/server" e "@openai-oauth/ai-sdk")
//   3. npx wrangler deploy
//   4. Em Studyh Web → Ajustes → "Entrar com ChatGPT", cole:
//        https://studyh-proxy.<sua-conta>.workers.dev/api/chat
//
// Segurança: nenhuma credencial é armazenada no Worker — os headers chegam por
// requisição, são usados só para atender aquele pedido e descartados.

import { createOpenAIOAuth } from "@openai-oauth/ai-sdk";
import { openaiCredentials } from "@openai-oauth/web/server";
import { generateText } from "ai";

const ALLOWED_ORIGIN = ""; // configure com a origem do seu app em produção

const cors = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "Content-Type, Authorization, chatgpt-account-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });

    const body = await request.json().catch(() => null);
    if (!body?.messages) return new Response(JSON.stringify({ error: "messages obrigatório" }), { status: 400, headers: cors });

    try {
      const openai = createOpenAIOAuth(openaiCredentials(request));
      const result = await generateText({
        model: openai(body.model || "gpt-5.4-mini"),
        messages: body.messages,
      });
      return Response.json({ text: result.text }, { headers: cors });
    } catch (err) {
      return Response.json({ error: String(err?.message || err) }, { status: 502, headers: cors });
    }
  },
};
