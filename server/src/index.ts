// index.ts
// Cloudflare Worker エントリポイント。
//
//   GET  /v1/health    稼働確認（秘密情報は返さない）
//   POST /v1/insights  ガイド要約 → OpenAI → 検証済みインサイト（docs/DATA_CONTRACTS.md §10）
//   POST /v1/chat      複数往復の AI 相談（docs/OPENAI_CHAT_ARCHITECTURE.md）
//
// 処理順: 認証(401) → レート制限(429) → サイズ(413) → JSON(400) → 契約検証(400) → 同意・計測可否(403)
//        → APIキー設定(503) → OpenAI 呼び出し(200 / 429 / 502 / 504)
// ログは構造化 JSON で、リクエスト内容（会話本文・心拍・場面など）・トークン・APIキーは出力しない。

import {
  type InsightErrorBody,
  type InsightResponse,
  MAX_BODY_BYTES,
  SCHEMA_VERSION,
  validateInsightRequest,
} from "./contract.ts";
import { generateInsight, UpstreamError } from "./openai.ts";
import {
  CHAT_DEFAULTS,
  type ChatResponse,
  generateChatReply,
  validateChatRequest,
} from "./chat.ts";
import { FixedWindowRateLimiter } from "./ratelimit.ts";

export interface Env {
  /** OpenAI APIキー（wrangler secret put OPENAI_API_KEY） */
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  OPENAI_BASE_URL?: string;
  OPENAI_TIMEOUT_MS?: string;
  /** 推論の深さ（none / low / medium …）。空なら送らない（非推論モデルを使う場合） */
  OPENAI_REASONING_EFFORT?: string;
  /** 会話用モデル（未設定なら OPENAI_MODEL） */
  OPENAI_CHAT_MODEL?: string;
  /** 会話の出力トークン上限（推論トークンを含む） */
  CHAT_MAX_OUTPUT_TOKENS?: string;
  CHAT_MAX_MESSAGES?: string;
  CHAT_MAX_USER_CHARS?: string;
  CHAT_MAX_TOTAL_CHARS?: string;
  /** "true" のときだけ計測の要約（context.measurement）を受け付ける。本物の利用者認証が整うまで設定しない */
  CHAT_ALLOW_MEASUREMENT_CONTEXT?: string;
  /** クライアントトークンあたりの 1 分間の上限（/v1/insights と /v1/chat の合計）。0 で無効 */
  RATE_LIMIT_PER_MINUTE?: string;
  /** 許可するクライアントトークン（カンマ区切り。wrangler secret put CLIENT_TOKENS） */
  CLIENT_TOKENS?: string;
}

export interface HandlerDeps {
  fetchImpl?: typeof fetch;
  log?: (entry: Record<string, unknown>) => void;
  now?: () => Date;
  /** 応答の provider。ローカル開発のスタブでは "openai-stub"（実際の AI ではないことをアプリに伝える） */
  providerName?: "openai" | "openai-stub";
  /** テスト用に時計を差し替えたレート制限 */
  rateLimiter?: FixedWindowRateLimiter;
}

// gpt-4o-mini は 2027-01-14 に提供終了予定のため、公式の後継として案内されている低コストモデルを既定にする
const DEFAULT_MODEL = "gpt-6-luna";
const DEFAULT_RATE_LIMIT_PER_MINUTE = 20;
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

/** 認証に成功したらトークン（レート制限のキー）を返す。CLIENT_TOKENS が未設定なら全拒否（fail closed） */
function authorizedToken(request: Request, env: Env): string | null {
  const tokens = (env.CLIENT_TOKENS ?? "").split(",").map((t) => t.trim()).filter((t) => t.length >= 16);
  if (tokens.length === 0) return null;
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer (.+)$/.exec(header);
  if (!match || !match[1]) return null;
  const presented = match[1];
  let ok = false;
  for (const t of tokens) ok = timingSafeEqual(presented, t) || ok;
  return ok ? presented : null;
}

function intEnv(value: string | undefined, fallback: number, min: number, max: number): number {
  const n = Number(value);
  return Number.isInteger(n) && n >= min && n <= max ? n : fallback;
}

/** OpenAI 側のエラーを HTTP 状態へ変換する */
function upstreamHttpStatus(code: string): number {
  if (code === "upstream_timeout") return 504;
  if (code === "upstream_rate_limited") return 429;
  return 502;
}

/** 本文を読み、サイズ上限と JSON 形式を確認する */
async function readJsonBody(request: Request): Promise<{ ok: true; body: unknown } | { ok: false; status: number; error: string; message: string }> {
  const declared = Number(request.headers.get("Content-Length") ?? "0");
  if (declared > MAX_BODY_BYTES) return { ok: false, status: 413, error: "payload_too_large", message: "本文が大きすぎます" };
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > MAX_BODY_BYTES) return { ok: false, status: 413, error: "payload_too_large", message: "本文が大きすぎます" };
  try {
    return { ok: true, body: JSON.parse(raw) };
  } catch {
    return { ok: false, status: 400, error: "invalid_request", message: "JSON ではありません" };
  }
}

export function createHandler(deps: HandlerDeps = {}) {
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const now = deps.now ?? (() => new Date());
  const providerName = deps.providerName ?? "openai";
  let limiter = deps.rateLimiter;
  let limiterSetting: number | null = null;

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

    const route = url.pathname === "/v1/insights" ? "insight" : url.pathname === "/v1/chat" ? "chat" : null;
    if (!route) return errorResponse(404, "not_found", "not found", null);
    if (request.method !== "POST") return errorResponse(405, "method_not_allowed", "POST のみ", null);

    const event = route === "insight" ? "insight_request" : "chat_request";
    const finish = (response: Response, outcome: string, requestId: string | null, extra: Record<string, unknown> = {}) => {
      log({ event, outcome, status: response.status, request_id: requestId, latency_ms: Date.now() - started, ...extra });
      return response;
    };

    const token = authorizedToken(request, env);
    if (!token) {
      return finish(errorResponse(401, "unauthorized", "認証に失敗しました", null), "unauthorized", null);
    }

    // レート制限（トークン単位・1インスタンス内）。設定値が変わったら作り直す
    if (!deps.rateLimiter) {
      const perMinute = intEnv(env.RATE_LIMIT_PER_MINUTE, DEFAULT_RATE_LIMIT_PER_MINUTE, 0, 10_000);
      if (!limiter || limiterSetting !== perMinute) {
        limiter = new FixedWindowRateLimiter(perMinute);
        limiterSetting = perMinute;
      }
    }
    const rate = limiter!.check(token);
    if (!rate.allowed) {
      const res = errorResponse(429, "rate_limited", "リクエストが多すぎます。しばらく待ってから再度お試しください", null);
      res.headers.set("Retry-After", String(rate.retryAfterSeconds));
      return finish(res, "rate_limited", null);
    }

    const parsed = await readJsonBody(request);
    if (!parsed.ok) {
      return finish(errorResponse(parsed.status, parsed.error, parsed.message, null), parsed.error === "payload_too_large" ? "payload_too_large" : "invalid_json", null);
    }

    const timeoutMs = Number(env.OPENAI_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS) || DEFAULT_TIMEOUT_MS;
    const reasoningEffort = env.OPENAI_REASONING_EFFORT?.trim() || undefined;
    const baseUrl = env.OPENAI_BASE_URL || DEFAULT_BASE_URL;
    const fetchImpl = deps.fetchImpl ?? fetch;

    const upstreamFailure = (error: unknown, requestId: string) => {
      if (error instanceof UpstreamError) {
        const status = upstreamHttpStatus(error.code);
        const message = error.code === "upstream_rate_limited"
          ? "AI の利用が混み合っています。しばらく待ってから再度お試しください"
          : "AI の応答を取得できませんでした";
        return finish(errorResponse(status, error.code, message, requestId), error.code, requestId, { upstream_status: error.upstreamStatus ?? null });
      }
      return finish(errorResponse(502, "upstream_error", "AI の応答を取得できませんでした", requestId), "unexpected_error", requestId);
    };

    if (route === "insight") {
      const validated = validateInsightRequest(parsed.body);
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
      try {
        const result = await generateInsight(req, {
          apiKey: env.OPENAI_API_KEY,
          model: env.OPENAI_MODEL || DEFAULT_MODEL,
          baseUrl,
          timeoutMs,
          reasoningEffort,
          fetchImpl,
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
        return upstreamFailure(error, req.request_id);
      }
    }

    // ── /v1/chat ───────────────────────────────────────────────
    const limits = {
      maxMessages: intEnv(env.CHAT_MAX_MESSAGES, CHAT_DEFAULTS.maxMessages, 1, 40),
      maxUserChars: intEnv(env.CHAT_MAX_USER_CHARS, CHAT_DEFAULTS.maxUserChars, 1, 4000),
      maxAssistantChars: CHAT_DEFAULTS.maxAssistantChars,
      maxTotalChars: intEnv(env.CHAT_MAX_TOTAL_CHARS, CHAT_DEFAULTS.maxTotalChars, 1, 12_000),
    };
    const validated = validateChatRequest(parsed.body, limits);
    if (!validated.ok) {
      return finish(errorResponse(400, "invalid_request", validated.message, null), "invalid_request", null);
    }
    const req = validated.value;
    if (req.context.measurement !== null) {
      // 生体由来の情報は、利用者認証が整い明示的に有効化されるまで受け付けない
      if (env.CHAT_ALLOW_MEASUREMENT_CONTEXT !== "true") {
        return finish(errorResponse(403, "measurement_context_disabled", "計測データの送信は現在無効です", req.request_id), "measurement_context_disabled", req.request_id);
      }
      if (!req.consent.biometric_context_consented) {
        return finish(errorResponse(403, "consent_required", "計測データの送信に同意していません", req.request_id), "consent_required", req.request_id);
      }
    }
    if (!env.OPENAI_API_KEY) {
      return finish(errorResponse(503, "not_configured", "サーバーに OpenAI が設定されていません", req.request_id), "not_configured", req.request_id);
    }
    try {
      const result = await generateChatReply(req, {
        apiKey: env.OPENAI_API_KEY,
        model: env.OPENAI_CHAT_MODEL || env.OPENAI_MODEL || DEFAULT_MODEL,
        baseUrl,
        timeoutMs,
        maxOutputTokens: intEnv(env.CHAT_MAX_OUTPUT_TOKENS, CHAT_DEFAULTS.maxOutputTokens, 16, 4000),
        reasoningEffort,
        fetchImpl,
      });
      const responseBody: ChatResponse = {
        schema_version: SCHEMA_VERSION,
        request_id: req.request_id,
        conversation_id: req.conversation_id,
        provider: providerName,
        model: result.model,
        generated_at: now().toISOString(),
        reply: { text: result.text, truncated: result.truncated },
        usage: result.usage,
      };
      // 利用量の監視用ログ（会話本文は出さない）
      return finish(json(200, responseBody), "ok", req.request_id, {
        model: result.model,
        provider: providerName,
        messages: req.messages.length,
        truncated: result.truncated,
        input_tokens: result.usage?.input_tokens ?? null,
        output_tokens: result.usage?.output_tokens ?? null,
        reasoning_tokens: result.usage?.reasoning_tokens ?? null,
      });
    } catch (error) {
      return upstreamFailure(error, req.request_id);
    }
  };
}

const handler = createHandler();

export default {
  fetch(request: Request, env: Env): Promise<Response> {
    return handler(request, env);
  },
};
