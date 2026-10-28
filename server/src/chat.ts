// chat.ts
// 複数往復の AI 相談（POST /v1/chat）。docs/OPENAI_CHAT_ARCHITECTURE.md
//
// 会話状態の方針:
// - 会話履歴はアプリ（iPhone）側が保持し、直近の数往復だけを毎回送る（サーバー・OpenAI には保存しない）
// - OpenAI へは store: false で送る（Responses API の会話保存機能・Conversations API は使わない）
// - 計測データ（生体由来の情報）は既定で受け付けない。利用者の同意と本物の利用者認証が整うまで 403 にする
//
// iOS 側の正本: MindWaveGraphic/MindWaveGraphic/Contracts/ChatContracts.swift

import { SCHEMA_VERSION, type Validation } from "./contract.ts";
import { UpstreamError } from "./openai.ts";

/** 状況確認画面（ContextCalibrationView / ContextScene）の場面 */
export const CHAT_SCENES = ["calm", "interview", "sports", "important", "work", "other"] as const;
export const CHAT_ROLES = ["user", "assistant"] as const;
export const MEASUREMENT_SOURCES = ["mock", "watch_live", "health_kit", "unavailable"] as const;
export const MEASUREMENT_STATES = ["under_aroused", "optimal_tension", "over_tense"] as const;
export const HRV_STATUSES = ["measured", "missing", "stale", "not_applicable"] as const;
export const BASELINE_STATUSES = ["personal", "provisional", "not_applicable"] as const;

/** 既定の上限（環境変数で変更可能。docs/OPENAI_CHAT_SETUP.md） */
export const CHAT_DEFAULTS = {
  maxMessages: 12,          // 送信できる発言数（直近 6 往復）
  maxUserChars: 500,        // 利用者の1発言の最大文字数
  maxAssistantChars: 1500,  // 過去の AI 発言の最大文字数（履歴として送り返す分）
  maxTotalChars: 8000,      // 履歴全体の最大文字数
  maxReplyChars: 1500,      // AI 返答として受け付ける最大文字数
  maxOutputTokens: 600,     // OpenAI の max_output_tokens（推論トークンを含む）
} as const;

export interface ChatLimits {
  maxMessages: number;
  maxUserChars: number;
  maxAssistantChars: number;
  maxTotalChars: number;
}

export interface ChatMessage {
  role: (typeof CHAT_ROLES)[number];
  content: string;
}

/** 計測の要約（値ではなく分類のみ）。現在は既定で受け付けない */
export interface ChatMeasurementContext {
  source: (typeof MEASUREMENT_SOURCES)[number];
  is_mock: boolean;
  state: (typeof MEASUREMENT_STATES)[number] | null;
  hrv_status: (typeof HRV_STATUSES)[number];
  baseline_status: (typeof BASELINE_STATUSES)[number];
  data_age_seconds: number | null;
}

export interface ChatRequest {
  schema_version: number;
  request_id: string;
  conversation_id: string;
  locale: "ja-JP";
  messages: ChatMessage[];
  context: {
    scene: (typeof CHAT_SCENES)[number] | null;
    measurement: ChatMeasurementContext | null;
  };
  consent: { biometric_context_consented: boolean; consent_version: number };
}

export interface ChatUsage {
  input_tokens: number;
  output_tokens: number;
  reasoning_tokens: number;
  total_tokens: number;
}

export interface ChatResponse {
  schema_version: number;
  request_id: string;
  conversation_id: string;
  /** "openai" = 実際の OpenAI、"openai-stub" = ローカル開発用スタブ（実際の AI ではない） */
  provider: "openai" | "openai-stub";
  model: string;
  generated_at: string;
  reply: { text: string; truncated: boolean };
  usage: ChatUsage | null;
}

/** 返答に含めない医療的断定表現。会話は自然な表現を優先するため、単発インサイトより対象を絞っている */
export const CHAT_PROHIBITED_PHRASES = ["と診断します", "と診断されます", "診断結果", "処方します", "服薬してください"];

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function extraKeys(obj: Record<string, unknown>, allowed: readonly string[], path: string): string | null {
  const extra = Object.keys(obj).filter((k) => !allowed.includes(k));
  return extra.length > 0 ? `${path} に未知のキー: ${extra.join(",")}` : null;
}

function isOneOf<T extends string>(v: unknown, list: readonly T[]): v is T {
  return typeof v === "string" && (list as readonly string[]).includes(v);
}

function charCount(s: string): number {
  return [...s].length;
}

function validateMeasurement(m: unknown): string | null {
  if (!isObject(m)) return "context.measurement がオブジェクトではない";
  const extra = extraKeys(m, ["source", "is_mock", "state", "hrv_status", "baseline_status", "data_age_seconds"], "context.measurement");
  if (extra) return extra;
  if (!isOneOf(m.source, MEASUREMENT_SOURCES)) return "context.measurement.source が不正";
  if (typeof m.is_mock !== "boolean" || m.is_mock !== (m.source === "mock")) return "context.measurement.is_mock が source と一致しない";
  if (!(m.state === null || isOneOf(m.state, MEASUREMENT_STATES))) return "context.measurement.state が不正";
  if (!isOneOf(m.hrv_status, HRV_STATUSES)) return "context.measurement.hrv_status が不正";
  if (!isOneOf(m.baseline_status, BASELINE_STATUSES)) return "context.measurement.baseline_status が不正";
  const age = m.data_age_seconds;
  if (!(age === null || (typeof age === "number" && Number.isInteger(age) && age >= 0 && age <= 7 * 86400))) {
    return "context.measurement.data_age_seconds が不正";
  }
  return null;
}

/** リクエストの形式検証（同意・計測の可否は handler 側で 403 を返す） */
export function validateChatRequest(body: unknown, limits: ChatLimits): Validation<ChatRequest> {
  const fail = (message: string): Validation<ChatRequest> => ({ ok: false, message });
  if (!isObject(body)) return fail("本文が JSON オブジェクトではない");
  const extra = extraKeys(body, ["schema_version", "request_id", "conversation_id", "locale", "messages", "context", "consent"], "request");
  if (extra) return fail(extra);
  if (body.schema_version !== SCHEMA_VERSION) return fail(`schema_version は ${SCHEMA_VERSION} のみ対応`);
  if (typeof body.request_id !== "string" || !UUID_RE.test(body.request_id)) return fail("request_id は UUID");
  if (typeof body.conversation_id !== "string" || !UUID_RE.test(body.conversation_id)) return fail("conversation_id は UUID");
  if (body.locale !== "ja-JP") return fail("locale は ja-JP のみ対応");

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0) return fail("messages が空");
  if (messages.length > limits.maxMessages) return fail(`messages は ${limits.maxMessages} 件まで`);
  let total = 0;
  for (const [i, m] of messages.entries()) {
    if (!isObject(m)) return fail(`messages[${i}] がオブジェクトではない`);
    const mExtra = extraKeys(m, ["role", "content"], `messages[${i}]`);
    if (mExtra) return fail(mExtra);
    if (!isOneOf(m.role, CHAT_ROLES)) return fail(`messages[${i}].role が不正`);
    if (typeof m.content !== "string" || m.content.trim().length === 0) return fail(`messages[${i}].content が空`);
    const limit = m.role === "user" ? limits.maxUserChars : limits.maxAssistantChars;
    const n = charCount(m.content);
    if (n > limit) return fail(`messages[${i}].content は ${limit} 文字まで`);
    total += n;
  }
  if (total > limits.maxTotalChars) return fail(`messages の合計は ${limits.maxTotalChars} 文字まで`);
  if ((messages[messages.length - 1] as ChatMessage).role !== "user") return fail("最後の発言は user であること");

  const context = body.context;
  if (!isObject(context)) return fail("context がない");
  const cExtra = extraKeys(context, ["scene", "measurement"], "context");
  if (cExtra) return fail(cExtra);
  if (!(context.scene === null || isOneOf(context.scene, CHAT_SCENES))) return fail("context.scene が不正");
  if (context.measurement !== null) {
    const err = validateMeasurement(context.measurement);
    if (err) return fail(err);
  }

  const consent = body.consent;
  if (!isObject(consent)) return fail("consent がない");
  const consentExtra = extraKeys(consent, ["biometric_context_consented", "consent_version"], "consent");
  if (consentExtra) return fail(consentExtra);
  if (typeof consent.biometric_context_consented !== "boolean") return fail("consent.biometric_context_consented は bool");
  if (typeof consent.consent_version !== "number" || !Number.isInteger(consent.consent_version) || consent.consent_version < 1) {
    return fail("consent.consent_version が不正");
  }
  return { ok: true, value: body as unknown as ChatRequest };
}

const SCENE_LABELS: Record<(typeof CHAT_SCENES)[number], string> = {
  calm: "安静・日常", interview: "面接・発表前", sports: "試合・大会前",
  important: "大切な予定の前", work: "作業・集中", other: "その他",
};

/** モデルへの指示。医療的断定の禁止・危機時の対応・簡潔さを明示する */
export const CHAT_INSTRUCTIONS = [
  "あなたは呼吸ガイドアプリ「Mind Wave Graphic」のセルフケア相談パートナーです。",
  "利用者は緊張や不安を和らげたいと考えています。これまでの会話の流れを踏まえ、日本語で自然に答えてください。",
  "必ず守ること:",
  "- 医療的な診断・病名の断定・治療や薬の指示はしない。体調や症状が心配な相談には、医師など専門家への相談を勧める。",
  "- 自傷や命の危険を示す内容があれば、ためらわず身近な人や専門の相談窓口、緊急の場合は救急（119）へ連絡するよう優しく伝える。",
  "- 呼吸法・準備の仕方・考え方の切り替えなど、すぐ試せる具体的なセルフケアを提案する。",
  "- 入力にない事実や計測値を作らない。計測情報が渡されていない場合は、心拍などの数値に触れない。",
  "- 敬体（です・ます）で、400文字程度までに簡潔にまとめる。箇条書きは必要なときだけ使う。",
].join("\n");

/** 場面・計測の補足（会話の先頭に developer メッセージとして添える） */
export function buildContextNote(req: ChatRequest): string | null {
  const parts: string[] = [];
  if (req.context.scene) parts.push(`利用者が選んだ場面: ${SCENE_LABELS[req.context.scene]}`);
  const m = req.context.measurement;
  if (m) {
    parts.push(
      `計測の要約（参考情報。医療的な判断に使わない）: source=${m.source}, mock=${m.is_mock}, state=${m.state ?? "不明"}, ` +
      `hrv_status=${m.hrv_status}, baseline_status=${m.baseline_status}, data_age_seconds=${m.data_age_seconds ?? "不明"}`,
    );
    if (m.is_mock) parts.push("この計測はデモ用の Mock データで、利用者本人の計測ではない。");
  }
  return parts.length > 0 ? parts.join("\n") : null;
}

export interface ChatOpenAIConfig {
  apiKey: string;
  model: string;
  baseUrl: string;
  timeoutMs: number;
  maxOutputTokens: number;
  /** 推論の深さ（"none" / "low" など）。未設定ならパラメーター自体を送らない（非推論モデル向け） */
  reasoningEffort?: string;
  fetchImpl: typeof fetch;
}

/** Responses API のリクエスト本文（APIキーは含めない）。会話は input に順番どおり並べる */
export function buildChatResponsesRequest(req: ChatRequest, cfg: Pick<ChatOpenAIConfig, "model" | "maxOutputTokens" | "reasoningEffort">): Record<string, unknown> {
  const input: Array<{ role: string; content: string }> = [];
  const note = buildContextNote(req);
  if (note) input.push({ role: "developer", content: note });
  for (const m of req.messages) input.push({ role: m.role, content: m.content });
  const body: Record<string, unknown> = {
    model: cfg.model,
    instructions: CHAT_INSTRUCTIONS,
    input,
    max_output_tokens: cfg.maxOutputTokens,
    // 入出力を OpenAI 側に保存しない（会話履歴はアプリが保持する）
    store: false,
  };
  if (cfg.reasoningEffort) body.reasoning = { effort: cfg.reasoningEffort };
  return body;
}

function num(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** Responses API の usage を取り出す（利用量の監視用） */
export function extractUsage(json: Record<string, unknown>): ChatUsage | null {
  const u = json.usage;
  if (!isObject(u)) return null;
  const details = isObject(u.output_tokens_details) ? u.output_tokens_details : {};
  return {
    input_tokens: num(u.input_tokens),
    output_tokens: num(u.output_tokens),
    reasoning_tokens: num(details.reasoning_tokens),
    total_tokens: num(u.total_tokens),
  };
}

/** 応答から返答テキストを取り出す。出力上限で途中終了した場合は truncated=true で返す */
export function extractChatText(json: unknown): { text: string; truncated: boolean } {
  if (!isObject(json)) throw new UpstreamError("invalid_upstream_response", "応答が JSON オブジェクトではない");
  let truncated = false;
  if (json.status !== undefined && json.status !== "completed") {
    const reason = isObject(json.incomplete_details) ? json.incomplete_details.reason : undefined;
    if (json.status === "incomplete" && reason === "max_output_tokens") truncated = true;
    else throw new UpstreamError("invalid_upstream_response", `status=${String(json.status)}`);
  }
  const texts: string[] = [];
  const output = Array.isArray(json.output) ? json.output : [];
  for (const item of output) {
    if (!isObject(item) || item.type !== "message" || !Array.isArray(item.content)) continue;
    for (const part of item.content) {
      if (!isObject(part)) continue;
      if (part.type === "refusal") throw new UpstreamError("upstream_refusal", "モデルが応答を拒否");
      if (part.type === "output_text" && typeof part.text === "string") texts.push(part.text);
    }
  }
  const text = texts.join("").trim();
  if (text.length === 0) {
    // 推論だけで出力上限に達した場合など
    throw new UpstreamError("invalid_upstream_response", truncated ? "出力上限で本文が空" : "output_text がない");
  }
  return { text, truncated };
}

/** 返答の検証（長さ・医療的断定表現） */
export function validateChatReply(text: string, maxChars: number = CHAT_DEFAULTS.maxReplyChars): Validation<string> {
  if (charCount(text) > maxChars) return { ok: false, message: `返答が ${maxChars} 文字超` };
  const phrase = CHAT_PROHIBITED_PHRASES.find((p) => text.includes(p));
  if (phrase) return { ok: false, message: "返答に医療的断定表現" };
  return { ok: true, value: text };
}

/** OpenAI のエラー状態をサーバーのエラーへ変換する（応答本文は読まない・ログに出さない） */
export function mapUpstreamStatus(status: number): UpstreamError {
  if (status === 429) return new UpstreamError("upstream_rate_limited", `openai status=${status}`, status);
  if (status === 401 || status === 403) return new UpstreamError("upstream_auth_error", `openai status=${status}`, status);
  return new UpstreamError("upstream_error", `openai status=${status}`, status);
}

/** OpenAI を呼び出して会話の返答を得る */
export async function generateChatReply(
  req: ChatRequest,
  cfg: ChatOpenAIConfig,
): Promise<{ text: string; truncated: boolean; model: string; usage: ChatUsage | null }> {
  const controller = new AbortController();
  // タイムアウトは応答本文の受信完了まで含める
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
  let json: unknown;
  try {
    let response: Response;
    try {
      response = await cfg.fetchImpl(`${cfg.baseUrl.replace(/\/$/, "")}/responses`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${cfg.apiKey}` },
        body: JSON.stringify(buildChatResponsesRequest(req, cfg)),
        signal: controller.signal,
      });
    } catch {
      if (controller.signal.aborted) throw new UpstreamError("upstream_timeout", `timeout after ${cfg.timeoutMs}ms`);
      throw new UpstreamError("upstream_error", "network error");
    }
    if (!response.ok) throw mapUpstreamStatus(response.status);
    try {
      json = await response.json();
    } catch {
      if (controller.signal.aborted) throw new UpstreamError("upstream_timeout", `timeout after ${cfg.timeoutMs}ms (body)`);
      throw new UpstreamError("invalid_upstream_response", "応答が JSON ではない");
    }
  } finally {
    clearTimeout(timer);
  }
  const { text, truncated } = extractChatText(json);
  const validated = validateChatReply(text);
  if (!validated.ok) throw new UpstreamError("invalid_upstream_response", validated.message);
  const res = json as Record<string, unknown>;
  return {
    text: validated.value,
    truncated,
    model: typeof res.model === "string" ? res.model : cfg.model,
    usage: extractUsage(res),
  };
}
