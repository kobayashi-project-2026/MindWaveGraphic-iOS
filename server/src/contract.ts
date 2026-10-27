// contract.ts
// iOS ⇄ サーバーの JSON 契約（docs/DATA_CONTRACTS.md §10）。
// iOS 側の正本: MindWaveGraphic/MindWaveGraphic/Contracts/InsightContracts.swift
// 片方を変更したら、もう片方・ドキュメント・テストを同時に更新すること。

export const SCHEMA_VERSION = 1;
export const MAX_BODY_BYTES = 16 * 1024;

export const SCENES = ["interview", "study", "sports", "social", "daily", "other", "meeting", "speech"] as const;
export const EXERCISES = ["breathing478", "box", "breathing214"] as const;
export const STATES = ["under_aroused", "optimal_tension", "over_tense"] as const;
export const HRV_TRENDS = ["up", "down", "flat", "unknown"] as const;
export const TONES = ["calm", "focus", "alert", "ovld"] as const;

export type MindState = (typeof STATES)[number];

export interface MeasurementSummary {
  state: MindState;
  score: number;
  heart_rate_bpm: number | null;
}

export interface SessionSummary {
  scene: (typeof SCENES)[number];
  exercise: (typeof EXERCISES)[number];
  duration_seconds: number;
  completed: boolean;
  before: MeasurementSummary;
  after: MeasurementSummary | null;
  hrv_trend: (typeof HRV_TRENDS)[number];
  self_report_before: number | null;
  self_report_after: number | null;
  confidence: number;
}

export interface InsightRequest {
  schema_version: number;
  request_id: string;
  locale: "ja-JP";
  consent: { external_ai_consented: boolean; consent_version: number };
  session: SessionSummary;
}

export interface InsightBody {
  title: string;
  summary: string;
  analysis: string;
  recommendation: string;
  next_action: string;
  caution: string;
  confidence_label: string;
  tone: (typeof TONES)[number];
}

export interface InsightResponse {
  schema_version: number;
  request_id: string;
  provider: "openai";
  model: string;
  generated_at: string;
  insight: InsightBody;
}

export interface InsightErrorBody {
  schema_version: number;
  request_id: string | null;
  error: string;
  message: string;
}

/** 各フィールドの最大文字数（Swift の InsightValidation.maxLengths と同じ） */
export const MAX_LENGTHS: Record<keyof Omit<InsightBody, "tone">, number> = {
  title: 40,
  summary: 160,
  analysis: 300,
  recommendation: 200,
  next_action: 120,
  caution: 160,
  confidence_label: 40,
};

/** 医療的断定と受け取られうる表現（Swift の InsightValidation.prohibitedPhrases と同じ） */
export const PROHIBITED_PHRASES = [
  "診断結果", "と診断", "治療", "病気", "疾患", "障害", "うつ病", "不安障害",
  "パニック", "処方", "服薬", "副交感神経", "自律神経",
];

/** 免責文。モデルの出力に関わらずサーバーがこの文言で上書きする */
export const FIXED_CAUTION = "これは医療的な診断ではなく、セルフケアの参考情報です。";

export type Validation<T> = { ok: true; value: T } | { ok: false; message: string };

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** 許可したキー以外を含む場合はエラー（アプリが誤って余計なデータを送らないようにする） */
function onlyKeys(obj: Record<string, unknown>, allowed: readonly string[], path: string): string | null {
  const extra = Object.keys(obj).filter((k) => !allowed.includes(k));
  return extra.length > 0 ? `${path} に未知のキー: ${extra.join(",")}` : null;
}

function isIntIn(v: unknown, min: number, max: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
}

function isOneOf<T extends string>(v: unknown, list: readonly T[]): v is T {
  return typeof v === "string" && (list as readonly string[]).includes(v);
}

function validateMeasurement(v: unknown, path: string): string | null {
  if (!isObject(v)) return `${path} がオブジェクトではない`;
  const extra = onlyKeys(v, ["state", "score", "heart_rate_bpm"], path);
  if (extra) return extra;
  if (!isOneOf(v.state, STATES)) return `${path}.state が不正`;
  if (!isIntIn(v.score, 0, 100)) return `${path}.score は 0〜100 の整数`;
  if (!(v.heart_rate_bpm === null || isIntIn(v.heart_rate_bpm, 20, 250))) return `${path}.heart_rate_bpm は null または 20〜250 の整数`;
  return null;
}

/** リクエスト本文の検証。consent=false は別途 403 にするため、ここでは形式だけを見る */
export function validateInsightRequest(body: unknown): Validation<InsightRequest> {
  if (!isObject(body)) return { ok: false, message: "本文が JSON オブジェクトではない" };
  const extra = onlyKeys(body, ["schema_version", "request_id", "locale", "consent", "session"], "request");
  if (extra) return { ok: false, message: extra };
  if (body.schema_version !== SCHEMA_VERSION) return { ok: false, message: `schema_version は ${SCHEMA_VERSION} のみ対応` };
  if (typeof body.request_id !== "string" || !UUID_RE.test(body.request_id)) return { ok: false, message: "request_id は UUID" };
  if (body.locale !== "ja-JP") return { ok: false, message: "locale は ja-JP のみ対応" };

  const consent = body.consent;
  if (!isObject(consent)) return { ok: false, message: "consent がない" };
  const consentExtra = onlyKeys(consent, ["external_ai_consented", "consent_version"], "consent");
  if (consentExtra) return { ok: false, message: consentExtra };
  if (typeof consent.external_ai_consented !== "boolean") return { ok: false, message: "consent.external_ai_consented は bool" };
  if (!isIntIn(consent.consent_version, 1, 1000)) return { ok: false, message: "consent.consent_version が不正" };

  const s = body.session;
  if (!isObject(s)) return { ok: false, message: "session がない" };
  const sessionExtra = onlyKeys(s, [
    "scene", "exercise", "duration_seconds", "completed", "before", "after",
    "hrv_trend", "self_report_before", "self_report_after", "confidence",
  ], "session");
  if (sessionExtra) return { ok: false, message: sessionExtra };
  if (!isOneOf(s.scene, SCENES)) return { ok: false, message: "session.scene が不正" };
  if (!isOneOf(s.exercise, EXERCISES)) return { ok: false, message: "session.exercise が不正" };
  if (!isIntIn(s.duration_seconds, 0, 3600)) return { ok: false, message: "session.duration_seconds は 0〜3600 の整数" };
  if (typeof s.completed !== "boolean") return { ok: false, message: "session.completed は bool" };
  const beforeErr = validateMeasurement(s.before, "session.before");
  if (beforeErr) return { ok: false, message: beforeErr };
  if (s.after !== null) {
    const afterErr = validateMeasurement(s.after, "session.after");
    if (afterErr) return { ok: false, message: afterErr };
  }
  if (!isOneOf(s.hrv_trend, HRV_TRENDS)) return { ok: false, message: "session.hrv_trend が不正" };
  for (const key of ["self_report_before", "self_report_after"] as const) {
    if (!(s[key] === null || isIntIn(s[key], 0, 3))) return { ok: false, message: `session.${key} は null または 0〜3` };
  }
  if (typeof s.confidence !== "number" || s.confidence < 0 || s.confidence > 1) {
    return { ok: false, message: "session.confidence は 0〜1" };
  }
  return { ok: true, value: body as unknown as InsightRequest };
}

/** AI 出力の検証（型・必須・文字数・禁止表現） */
export function validateInsightBody(body: unknown): Validation<InsightBody> {
  if (!isObject(body)) return { ok: false, message: "insight がオブジェクトではない" };
  const keys = [...Object.keys(MAX_LENGTHS), "tone"];
  const extra = onlyKeys(body, keys, "insight");
  if (extra) return { ok: false, message: extra };
  for (const [key, limit] of Object.entries(MAX_LENGTHS)) {
    const value = body[key];
    if (typeof value !== "string" || value.trim().length === 0) return { ok: false, message: `insight.${key} が空` };
    if ([...value.trim()].length > limit) return { ok: false, message: `insight.${key} が ${limit} 文字超` };
    const phrase = PROHIBITED_PHRASES.find((p) => value.includes(p));
    if (phrase) return { ok: false, message: `insight.${key} に禁止表現` };
  }
  if (!isOneOf(body.tone, TONES)) return { ok: false, message: "insight.tone が不正" };
  return { ok: true, value: body as unknown as InsightBody };
}

/** OpenAI Structured Outputs（strict）に渡す JSON Schema */
export const INSIGHT_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["title", "summary", "analysis", "recommendation", "next_action", "caution", "confidence_label", "tone"],
  properties: {
    title: { type: "string", description: "見出し（40文字以内）", maxLength: MAX_LENGTHS.title },
    summary: { type: "string", description: "結果の要約（160文字以内）", maxLength: MAX_LENGTHS.summary },
    analysis: { type: "string", description: "前後の変化の説明（300文字以内）", maxLength: MAX_LENGTHS.analysis },
    recommendation: { type: "string", description: "次に試すこと（200文字以内）", maxLength: MAX_LENGTHS.recommendation },
    next_action: { type: "string", description: "すぐできる行動（120文字以内）", maxLength: MAX_LENGTHS.next_action },
    caution: { type: "string", description: "免責文", maxLength: MAX_LENGTHS.caution },
    confidence_label: { type: "string", description: "確からしさの表示（例: 確からしさ: 中）", maxLength: MAX_LENGTHS.confidence_label },
    tone: { type: "string", enum: [...TONES] },
  },
} as const;
