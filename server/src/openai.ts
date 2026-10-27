// openai.ts
// OpenAI Responses API（POST /v1/responses）を Structured Outputs（strict JSON Schema）で呼び出す。
// APIキーはこのサーバーの環境変数だけが持つ。リクエスト内容・応答本文はログに出さない。
// 参照: https://developers.openai.com/api/docs/guides/structured-outputs

import {
  FIXED_CAUTION,
  INSIGHT_JSON_SCHEMA,
  type InsightBody,
  type InsightRequest,
  validateInsightBody,
} from "./contract.ts";

export interface OpenAIConfig {
  apiKey: string;
  model: string;
  /** 既定 https://api.openai.com/v1（ローカルのスタブへ向ける場合のみ変更） */
  baseUrl: string;
  timeoutMs: number;
  fetchImpl: typeof fetch;
}

export type UpstreamErrorCode =
  | "upstream_error"
  | "upstream_timeout"
  | "upstream_refusal"
  | "invalid_upstream_response";

export class UpstreamError extends Error {
  readonly code: UpstreamErrorCode;
  readonly upstreamStatus: number | undefined;

  constructor(code: UpstreamErrorCode, message: string, upstreamStatus?: number) {
    super(message);
    this.code = code;
    this.upstreamStatus = upstreamStatus;
  }
}

const SCENE_LABELS: Record<string, string> = {
  interview: "面接・面談前", study: "勉強・試験", sports: "試合・大会前", social: "人付き合い",
  daily: "日常", other: "その他", meeting: "重要な会議", speech: "スピーチ・発表",
};
const EXERCISE_LABELS: Record<string, string> = {
  breathing478: "4-7-8呼吸", box: "ボックス呼吸", breathing214: "2-1-4呼吸",
};
const STATE_LABELS: Record<string, string> = {
  under_aroused: "落ち着き", optimal_tension: "集中中間域", over_tense: "高緊張",
};

/** モデルへの指示（システム側）。医療的表現の禁止・入力にない数値の創作禁止を明示する */
export const INSTRUCTIONS = [
  "あなたは呼吸ガイドアプリ「Mind Wave Graphic」のセルフケア振り返りコーチです。",
  "ユーザーが行った呼吸ガイド1回分の要約(JSON)をもとに、日本語で短い振り返りを作成します。",
  "必ず守ること:",
  "- 医療的な診断・病名・治療・薬・生理学的な仕組み（神経系など）には触れない。断定しない。",
  "- 入力にない数値・事実を作らない。心拍が null の場合は心拍に言及しない。",
  "- スコアは緊張の揺らぎの目安であり、良い/悪いと評価しない。",
  "- 前向きで具体的、1〜2文で簡潔に。敬体（です・ます）で書く。",
  "- tone は after（なければ before）の状態に合わせる: 落ち着き=calm, 集中中間域=focus, 高緊張=alert（スコア80以上は ovld）。",
  `- caution は「${FIXED_CAUTION}」とする。`,
].join("\n");

/** モデルへ渡すユーザー入力。検証済みの要約だけを使い、ラベルを補う */
export function buildUserInput(req: InsightRequest): string {
  const s = req.session;
  const summary = {
    scene: SCENE_LABELS[s.scene] ?? s.scene,
    exercise: EXERCISE_LABELS[s.exercise] ?? s.exercise,
    duration_seconds: s.duration_seconds,
    completed: s.completed,
    before: { ...s.before, state_label: STATE_LABELS[s.before.state] },
    after: s.after ? { ...s.after, state_label: STATE_LABELS[s.after.state] } : null,
    hrv_trend: s.hrv_trend,
    self_report_before: s.self_report_before,
    self_report_after: s.self_report_after,
    measurement_confidence: s.confidence,
  };
  return `以下はガイド1回分の要約です。self_report は 0=落ち着いている〜3=強く緊張。\n${JSON.stringify(summary)}`;
}

/** Responses API のリクエスト本文（APIキーは含めない） */
export function buildResponsesRequest(req: InsightRequest, model: string): Record<string, unknown> {
  return {
    model,
    instructions: INSTRUCTIONS,
    input: [{ role: "user", content: buildUserInput(req) }],
    text: {
      format: {
        type: "json_schema",
        name: "mindwave_insight",
        schema: INSIGHT_JSON_SCHEMA,
        strict: true,
      },
    },
    max_output_tokens: 1200,
    // 入出力を OpenAI 側に保存しない
    store: false,
  };
}

/** Responses API の応答から出力テキストを取り出す。拒否・未完了はエラー */
export function extractOutputText(json: unknown): string {
  if (typeof json !== "object" || json === null) {
    throw new UpstreamError("invalid_upstream_response", "応答が JSON オブジェクトではない");
  }
  const res = json as Record<string, unknown>;
  if (res.status !== undefined && res.status !== "completed") {
    throw new UpstreamError("invalid_upstream_response", `status=${String(res.status)}`);
  }
  const output = Array.isArray(res.output) ? res.output : [];
  for (const item of output) {
    if (typeof item !== "object" || item === null) continue;
    const msg = item as Record<string, unknown>;
    if (msg.type !== "message" || !Array.isArray(msg.content)) continue;
    for (const part of msg.content) {
      if (typeof part !== "object" || part === null) continue;
      const p = part as Record<string, unknown>;
      if (p.type === "refusal") throw new UpstreamError("upstream_refusal", "モデルが応答を拒否");
      if (p.type === "output_text" && typeof p.text === "string") return p.text;
    }
  }
  // SDK 互換の集約フィールドがあれば使う
  if (typeof res.output_text === "string" && res.output_text.length > 0) return res.output_text;
  throw new UpstreamError("invalid_upstream_response", "output_text がない");
}

/** OpenAI を呼び出し、検証済みのインサイトを返す */
export async function generateInsight(
  req: InsightRequest,
  cfg: OpenAIConfig,
): Promise<{ insight: InsightBody; model: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
  let response: Response;
  try {
    response = await cfg.fetchImpl(`${cfg.baseUrl.replace(/\/$/, "")}/responses`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${cfg.apiKey}`,
      },
      body: JSON.stringify(buildResponsesRequest(req, cfg.model)),
      signal: controller.signal,
    });
  } catch (error) {
    if (controller.signal.aborted) {
      throw new UpstreamError("upstream_timeout", `timeout after ${cfg.timeoutMs}ms`);
    }
    throw new UpstreamError("upstream_error", "network error");
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok) {
    // 応答本文には入力の一部が含まれうるため読まない・ログに出さない
    throw new UpstreamError("upstream_error", `openai status=${response.status}`, response.status);
  }

  let json: unknown;
  try {
    json = await response.json();
  } catch {
    throw new UpstreamError("invalid_upstream_response", "応答が JSON ではない");
  }
  const text = extractOutputText(json);

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new UpstreamError("invalid_upstream_response", "output_text が JSON ではない");
  }
  // 免責文はモデル出力に依存させず固定文言にする
  if (typeof parsed === "object" && parsed !== null) {
    (parsed as Record<string, unknown>).caution = FIXED_CAUTION;
  }
  const validated = validateInsightBody(parsed);
  if (!validated.ok) {
    throw new UpstreamError("invalid_upstream_response", validated.message);
  }
  const model = typeof (json as Record<string, unknown>).model === "string"
    ? ((json as Record<string, unknown>).model as string)
    : cfg.model;
  return { insight: validated.value, model };
}
