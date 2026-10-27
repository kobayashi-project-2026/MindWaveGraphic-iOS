// index.ts
// Cloudflare Worker エントリポイント。
//
//   GET  /v1/health    稼働確認（秘密情報は返さない）
//   POST /v1/insights  ガイド要約 → OpenAI → 検証済みインサイト（docs/DATA_CONTRACTS.md §10）
//
// 処理順: 認証(401) → サイズ(413) → JSON(400) → 契約検証(400) → 同意(403) → APIキー設定(503)
//        → OpenAI 呼び出し(200 / 502 / 504)
// ログは構造化 JSON で、リクエスト内容（心拍・場面など）は出力しない。

import {
  type InsightErrorBody,
  type InsightResponse,
  MAX_BODY_BYTES,
  SCHEMA_VERSION,
  validateInsightRequest,
} from "./contract.ts";
import { generateInsight, UpstreamError } from "./openai.ts";

export interface Env {
  /** OpenAI APIキー（wrangler secret put OPENAI_API_KEY） */
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  OPENAI_BASE_URL?: string;
  OPENAI_TIMEOUT_MS?: string;
  /** 許可するクライアントトークン（カンマ区切り。wrangler secret put CLIENT_TOKENS） */
  CLIENT_TOKENS?: string;
}

export interface HandlerDeps {
  fetchImpl?: typeof fetch;
  log?: (entry: Record<string, unknown>) => void;
  now?: () => Date;
}

const DEFAULT_MODEL = "gpt-4o-mini";
const DEFAULT_BASE_URL = "https://api.openai.com/v1";
const DEFAULT_TIMEOUT_MS = 15_000;

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function errorResponse(status: number, error: string, message: string, requestId: string | null): Response {
  const body: InsightErrorBody = { schema_version: SCHEMA_VERSION, request_id: requestId, error, message };
  return json(status, body);
}

/** 長さに依存しない比較（トークン総当たりの時間差対策） */
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  const len = Math.max(x.length, y.length);
  for (let i = 0; i < len; i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

/** CLIENT_TOKENS が未設定なら全拒否（fail closed） */
function isAuthorized(request: Request, env: Env): boolean {
  const tokens = (env.CLIENT_TOKENS ?? "").split(",").map((t) => t.trim()).filter((t) => t.length >= 16);
  if (tokens.length === 0) return false;
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer (.+)$/.exec(header);
  if (!match || !match[1]) return false;
  const presented = match[1];
  let ok = false;
  for (const t of tokens) ok = timingSafeEqual(presented, t) || ok;
  return ok;
}

export function createHandler(deps: HandlerDeps = {}) {
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const now = deps.now ?? (() => new Date());

  return async function handle(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const started = Date.now();

    if (url.pathname === "/v1/health") {
      if (request.method !== "GET") return errorResponse(405, "method_not_allowed", "GET のみ", null);
      return json(200, {
        status: "ok",
        schema_version: SCHEMA_VERSION,
        openai_configured: Boolean(env.OPENAI_API_KEY),
        auth_configured: Boolean(env.CLIENT_TOKENS),
      });
    }

    if (url.pathname !== "/v1/insights") return errorResponse(404, "not_found", "not found", null);
    if (request.method !== "POST") return errorResponse(405, "method_not_allowed", "POST のみ", null);

    const finish = (response: Response, outcome: string, requestId: string | null, extra: Record<string, unknown> = {}) => {
      log({ event: "insight_request", outcome, status: response.status, request_id: requestId, latency_ms: Date.now() - started, ...extra });
      return response;
    };

    if (!isAuthorized(request, env)) {
      return finish(errorResponse(401, "unauthorized", "認証に失敗しました", null), "unauthorized", null);
    }

    const declared = Number(request.headers.get("Content-Length") ?? "0");
    if (declared > MAX_BODY_BYTES) {
      return finish(errorResponse(413, "payload_too_large", "本文が大きすぎます", null), "payload_too_large", null);
    }
    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) {
      return finish(errorResponse(413, "payload_too_large", "本文が大きすぎます", null), "payload_too_large", null);
    }

    let body: unknown;
    try {
      body = JSON.parse(raw);
    } catch {
      return finish(errorResponse(400, "invalid_request", "JSON ではありません", null), "invalid_json", null);
    }

    const validated = validateInsightRequest(body);
    if (!validated.ok) {
      return finish(errorResponse(400, "invalid_request", validated.message, null), "invalid_request", null);
    }
    const req = validated.value;

    if (!req.consent.external_ai_consented) {
      return finish(errorResponse(403, "consent_required", "外部AIへの送信に同意していません", req.request_id), "consent_required", req.request_id);
    }

    if (!env.OPENAI_API_KEY) {
      return finish(errorResponse(503, "not_configured", "サーバーに OpenAI が設定されていません", req.request_id), "not_configured", req.request_id);
    }

    const timeoutMs = Number(env.OPENAI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS) || DEFAULT_TIMEOUT_MS;
    try {
      const result = await generateInsight(req, {
        apiKey: env.OPENAI_API_KEY,
        model: env.OPENAI_MODEL || DEFAULT_MODEL,
        baseUrl: env.OPENAI_BASE_URL || DEFAULT_BASE_URL,
        timeoutMs,
        fetchImpl: deps.fetchImpl ?? fetch,
      });
      const responseBody: InsightResponse = {
        schema_version: SCHEMA_VERSION,
        request_id: req.request_id,
        provider: "openai",
        model: result.model,
        generated_at: now().toISOString(),
        insight: result.insight,
      };
      return finish(json(200, responseBody), "ok", req.request_id, { model: result.model });
    } catch (error) {
      if (error instanceof UpstreamError) {
        const status = error.code === "upstream_timeout" ? 504 : 502;
        return finish(
          errorResponse(status, error.code, "AI の応答を取得できませんでした", req.request_id),
          error.code, req.request_id, { upstream_status: error.upstreamStatus ?? null },
        );
      }
      return finish(errorResponse(502, "upstream_error", "AI の応答を取得できませんでした", req.request_id), "unexpected_error", req.request_id);
    }
  };
}

const handler = createHandler();

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handler(request, env);
  },
};
