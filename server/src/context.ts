// context.ts
// もこりんとの会話で「測定前の状況（場面・身体状態）」を整理する（POST /v1/context-assist）。
// docs/MOKORIN_CONTEXT_INTEGRATION.md
//
// - 返すのは「候補」だけ。確定・測定開始はアプリ上で利用者が行う
// - 候補は iOS の ContextScene / BodyCondition の rawValue に限定（Structured Outputs の enum とサーバー検証の二重チェック）
// - 会話履歴はアプリが保持して毎回送る。OpenAI へは store: false（サーバー・OpenAI に保存しない）
// - 心拍・HRV などの計測データを受け取る項目はない
//
// iOS 側の正本: MindWaveGraphic/MindWaveGraphic/Contracts/ContextAssistContracts.swift

import { CHECKIN_INSTRUCTIONS, CHECKIN_JSON_SCHEMA, buildCheckInNote, normalizeCheckIn, validateCheckInRequest, type CheckInResult } from "./checkin.ts";
import { SCHEMA_VERSION, type Validation } from "./contract.ts";
import { CHAT_SCENES, extractUsage, type ChatUsage } from "./chat.ts";
import { UpstreamError, upstreamErrorFromResponse } from "./openai.ts";

export const CONTEXT_SCENES = CHAT_SCENES;
export const BODY_CONDITIONS = ["running", "stairs", "smoking", "caffeine", "sleep_lack", "after_meal", "none"] as const;
export const CONTEXT_STEPS = ["tension", "scene", "condition", "review"] as const;
/** 利用者の主観的な緊張（自己申告）。心拍・HRV から計算する緊張スコアとは別物で、計算には使わない */
export const SUBJECTIVE_TENSIONS = ["calm", "slight", "high"] as const;
/** もこりんの表情・動作（友達の原本 app.py / script.js と同じ許可値。third_party/mokorin_friend_source） */
export const MOKORIN_EMOTIONS = ["happy", "calm", "sad", "sleepy"] as const;
export const MOKORIN_ACTIONS = ["wave", "jump", "nod"] as const;
/** 利用者の発言の意図（会話の進め方の補助。測定の判断には使わない）
 *  answer=質問への答え / question=もこりんへの質問・雑談 / decline_measurement=今は測定したくない / ready=測定を始めたい */
export const USER_INTENTS = ["answer", "question", "decline_measurement", "ready"] as const;

export type ContextScene = (typeof CONTEXT_SCENES)[number];
export type BodyCondition = (typeof BODY_CONDITIONS)[number];

export const CONTEXT_LIMITS = {
  maxMessages: 12,
  maxUserChars: 300,
  maxAssistantChars: 300,
  maxTotalChars: 4000,
  maxReplyChars: 160,
  maxQuestionChars: 120,
  maxSituationNoteChars: 40,
  maxOutputTokens: 500,
} as const;

export interface ContextAssistRequest {
  schema_version: number;
  request_id: string;
  conversation_id: string;
  locale: "ja-JP";
  /** アプリ側の現在の段階 */
  step: (typeof CONTEXT_STEPS)[number];
  messages: Array<{ role: "user" | "assistant"; content: string }>;
  /** 画面で現在選ばれている内容（利用者がボタンで選んだもの・確認済みの提案） */
  current: { scene: ContextScene | null; conditions: BodyCondition[]; tension?: (typeof SUBJECTIVE_TENSIONS)[number] | null;
    /** 会話の情報（STEP 0〜6。2026-11-11 追加・省略可能） */
    check_in?: Record<string, unknown>; next_slot?: string | null };
}

export interface ContextAssistResult {
  reply: string;
  scene_candidate: ContextScene | null;
  condition_candidates: BodyCondition[];
  needs_clarification: boolean;
  clarification_question: string | null;
  /** 利用者が述べた主観的な緊張（自己申告）。計測値ではない。不明・不正は null */
  tension_candidate: (typeof SUBJECTIVE_TENSIONS)[number] | null;
  /** もこりんの表情。不正な値は calm（原本 app.py の既定と同じ） */
  emotion: (typeof MOKORIN_EMOTIONS)[number];
  /** もこりんの動作。不正な値は nod（原本 app.py の既定と同じ） */
  action: (typeof MOKORIN_ACTIONS)[number];
  /** 利用者が述べた予定の短い要約（既存の場面に分類しきれない内容: 試験・初対面など）。推測しない。不明は null。2026-11-05 追加（古いアプリは無視する） */
  situation_note: string | null;
  /** 利用者の発言の意図。不正・欠落は answer。2026-11-05 追加 */
  user_intent: (typeof USER_INTENTS)[number];
  /** 今回の発言から取り出した会話の情報（2026-11-11 追加。古いアプリは無視する） */
  check_in: CheckInResult;
}

export interface ContextAssistResponse {
  schema_version: number;
  request_id: string;
  conversation_id: string;
  provider: "openai" | "openai-stub";
  model: string;
  generated_at: string;
  result: ContextAssistResult;
  usage: ChatUsage | null;
}

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

const chars = (s: string) => [...s].length;

export function validateContextAssistRequest(body: unknown): Validation<ContextAssistRequest> {
  const fail = (message: string): Validation<ContextAssistRequest> => ({ ok: false, message });
  if (!isObject(body)) return fail("本文が JSON オブジェクトではない");
  const extra = extraKeys(body, ["schema_version", "request_id", "conversation_id", "locale", "step", "messages", "current"], "request");
  if (extra) return fail(extra);
  if (body.schema_version !== SCHEMA_VERSION) return fail(`schema_version は ${SCHEMA_VERSION} のみ対応`);
  if (typeof body.request_id !== "string" || !UUID_RE.test(body.request_id)) return fail("request_id は UUID");
  if (typeof body.conversation_id !== "string" || !UUID_RE.test(body.conversation_id)) return fail("conversation_id は UUID");
  if (body.locale !== "ja-JP") return fail("locale は ja-JP のみ対応");
  if (!isOneOf(body.step, CONTEXT_STEPS)) return fail("step が不正");

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0) return fail("messages が空");
  if (messages.length > CONTEXT_LIMITS.maxMessages) return fail(`messages は ${CONTEXT_LIMITS.maxMessages} 件まで`);
  let total = 0;
  for (const [i, m] of messages.entries()) {
    if (!isObject(m)) return fail(`messages[${i}] がオブジェクトではない`);
    const mExtra = extraKeys(m, ["role", "content"], `messages[${i}]`);
    if (mExtra) return fail(mExtra);
    if (m.role !== "user" && m.role !== "assistant") return fail(`messages[${i}].role が不正`);
    if (typeof m.content !== "string" || m.content.trim().length === 0) return fail(`messages[${i}].content が空`);
    const limit = m.role === "user" ? CONTEXT_LIMITS.maxUserChars : CONTEXT_LIMITS.maxAssistantChars;
    if (chars(m.content) > limit) return fail(`messages[${i}].content は ${limit} 文字まで`);
    total += chars(m.content);
  }
  if (total > CONTEXT_LIMITS.maxTotalChars) return fail(`messages の合計は ${CONTEXT_LIMITS.maxTotalChars} 文字まで`);
  if ((messages[messages.length - 1] as { role: string }).role !== "user") return fail("最後の発言は user であること");

  const current = body.current;
  if (!isObject(current)) return fail("current がない");
  const cExtra = extraKeys(current, ["scene", "conditions", "tension", "check_in", "next_slot"], "current");
  if (cExtra) return fail(cExtra);
  const checkInError = validateCheckInRequest(current.check_in);
  if (checkInError) return fail(checkInError);
  if (!(current.next_slot === undefined || current.next_slot === null || (typeof current.next_slot === "string" && current.next_slot.length <= 20))) return fail("current.next_slot が不正");
  if (!(current.scene === null || isOneOf(current.scene, CONTEXT_SCENES))) return fail("current.scene が不正");
  if (!Array.isArray(current.conditions) || !current.conditions.every((c) => isOneOf(c, BODY_CONDITIONS))) return fail("current.conditions が不正");
  if (!(current.tension === undefined || current.tension === null || isOneOf(current.tension, SUBJECTIVE_TENSIONS))) return fail("current.tension が不正");
  return { ok: true, value: body as unknown as ContextAssistRequest };
}

const SCENE_LABELS: Record<ContextScene, string> = {
  calm: "安静", interview: "面接 / 発表前", sports: "試合 / 大会前",
  important: "大切な予定前", work: "作業 / 集中", other: "その他",
};
const CONDITION_LABELS: Record<BodyCondition, string> = {
  running: "走ってきた", stairs: "階段 / 移動直後", smoking: "喫煙後", caffeine: "カフェイン摂取後",
  sleep_lack: "睡眠不足", after_meal: "食後", none: "特になし",
};

export const CONTEXT_INSTRUCTIONS = [
  "あなたは呼吸ガイドアプリ「Mind Wave Graphic」のキャラクター「もこりん」です。",
  "測定の前に、利用者の「場面」と「身体状態」を会話で一緒に整理します。やさしく共感し、短い日本語（120文字程度まで）で話します。一人称は使わなくてよい。",
  `場面の候補は次のいずれか: ${CONTEXT_SCENES.map((s) => `${s}=${SCENE_LABELS[s]}`).join(", ")}`,
  `身体状態の候補は次のいずれか（複数可）: ${BODY_CONDITIONS.map((c) => `${c}=${CONDITION_LABELS[c]}`).join(", ")}`,
  "必ず守ること:",
  "- 最初の段階（tension）では、利用者が今緊張しているかを聞く。答えは tension_candidate に calm（落ち着いている・緊張していない）/ slight（少し）/ high（かなり）で返す。これは本人の主観で、計測した緊張度ではない。緊張していなくても責めず、そのまま次の質問へ進む。",
  "- tension の次は「何か予定があるの？」のように自然に場面を尋ね、その次に「今は落ち着いて座ってる？それとも移動してきたところ？」のように身体状態を尋ねる。すでに答えた内容は聞き直さない。",
  "- 利用者がはっきり述べた内容だけを候補にする。「緊張している」「不安」だけでは場面を決めず、scene_candidate を null にして、どんな場面の前かを尋ねる。",
  "- 身体状態は、利用者が「特にない」「座っている」「落ち着いている」など明言した場合だけ none にする。none と他の状態は同時に出さない。",
  "- 分からない・曖昧な場合は needs_clarification を true にし、clarification_question に短い質問を1つ書く。すでに答えてもらったことは聞き直さない。",
  "- 利用者が前に言った内容を訂正したとき（例:「面接って言ったけど、実際は試合だった」「階段じゃなくて走ってきた」）は、最新の発言を優先して候補を返す。condition_candidates には今の身体状態だけを入れ、訂正で取り消されたものは入れない。",
  "- step が scene なら場面を、condition なら身体状態を中心に確認する。両方わかったら、内容をまとめて「この状況で測定してみようか？」と確認する。",
  "- 測定はアプリの画面で利用者が開始する。測定を開始した・結果が出たなどと言わない。",
  "- 緊張度や心拍などの数値を推測しない。医療的な診断・病名・治療の話をしない。",
  "- reply は利用者への返答そのもの（共感＋次の質問または確認）にする。質問は reply に1つだけ含め、clarification_question にはその同じ質問文を入れる（別の質問を足さない）。",
  "- emotion はもこりんの表情（happy / calm / sad / sleepy）、action は動作（wave / jump / nod）。返答の雰囲気に合わせる（あいさつは wave、共感・確認は nod、つらそうな相談は sad、睡眠不足は sleepy など）。",
  "会話の質（必ず守る）:",
  "- 直前までの会話を踏まえて返す。同じ質問・同じ言い回しを繰り返さない。一度に尋ねるのは1つだけ。",
  "- 場面と身体状態がわかったら、それ以上質問せずにまとめて測定を提案する。必要のない質問（場所・原因など）を毎回しない。",
  "- 場面の候補にない予定も受け止める。例: 試験・テスト→work（作業 / 集中）、初対面の人と会う→important または other、大学の発表→interview。分類しきれない内容は situation_note に利用者の言葉に近い短い要約（40文字以内）で入れ、scene_candidate は最も近い既存の候補か null。推測で補わない。",
  "- 「昨日の試験」「さっきの面接」のような過去の出来事は、これからの予定ではない。scene_candidate にせず（null）、気になっていることとして受け止め、situation_note に短く入れる。",
  "- 状況に合わせて言い回しを変える。例: 面接なら「どんな面接？」ではなく身体状態へ進む、試合なら「ウォーミングアップは終わった？」、疲れていると言われたら「無理しないでね」と気づかう、理由がわからない緊張は「理由がわからなくても大丈夫だよ」と受け止める、緊張していない人には軽く進める。複数の不安を話されたら、一番気になることを1つだけ確かめる。",
  "- 利用者がもこりんへの質問や雑談をしたら（user_intent=question）、短く答えてから、未確認の項目があればやさしく話を戻す。知らないこと・わからないことは知らないと答える。",
  "- 利用者が「今は測りたくない」「やめておく」など測定を望まないときは user_intent=decline_measurement にし、尊重して「大丈夫だよ」と伝える。説得しない。",
  "- 利用者が「もう測りたい」「始めて」と言ったら user_intent=ready。未確認の項目は聞かずにまとめる。それ以外の普通の答えは answer。",
  "- 深刻な体の症状（胸の痛み・息苦しさなど）を話されたら、無理をせず近くの人や医療機関に相談するよう短く伝える。診断はしない。",
  "- 長い説明を求められたときだけ詳しく話す（それでも160文字以内）。",
  CHECKIN_INSTRUCTIONS,
].join("\n");

/** OpenAI Structured Outputs（strict）に渡す JSON Schema */
export const CONTEXT_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["reply", "scene_candidate", "condition_candidates", "needs_clarification", "clarification_question", "tension_candidate", "emotion", "action", "situation_note", "user_intent", "check_in"],
  properties: {
    reply: { type: "string", description: "もこりんの返答（120文字程度まで）" },
    scene_candidate: { type: ["string", "null"], enum: [...CONTEXT_SCENES, null], description: "明言された場面。なければ null" },
    condition_candidates: { type: "array", items: { type: "string", enum: [...BODY_CONDITIONS] }, description: "明言された身体状態" },
    needs_clarification: { type: "boolean" },
    clarification_question: { type: ["string", "null"], description: "追加で尋ねる質問。不要なら null" },
    tension_candidate: { type: ["string", "null"], enum: [...SUBJECTIVE_TENSIONS, null], description: "利用者が述べた主観的な緊張。なければ null" },
    emotion: { type: "string", enum: [...MOKORIN_EMOTIONS], description: "もこりんの表情" },
    action: { type: "string", enum: [...MOKORIN_ACTIONS], description: "もこりんの動作" },
    situation_note: { type: ["string", "null"], description: "利用者が述べた予定の短い要約（40文字以内）。推測しない。なければ null" },
    user_intent: { type: "string", enum: [...USER_INTENTS], description: "利用者の発言の意図" },
    check_in: CHECKIN_JSON_SCHEMA,
  },
} as const;

/** 画面の現在の選択を developer メッセージで伝える（会話と矛盾しないように） */
export function buildCurrentNote(req: ContextAssistRequest): string {
  const scene = req.current.scene ? SCENE_LABELS[req.current.scene] : "未選択";
  const conds = req.current.conditions.length > 0 ? req.current.conditions.map((c) => CONDITION_LABELS[c]).join("・") : "未選択";
  const tension = req.current.tension ? { calm: "落ち着いている", slight: "少し緊張", high: "かなり緊張" }[req.current.tension] : "未回答";
  return `現在の段階: ${req.step}。本人の主観的な緊張: ${tension}。画面で選択中の場面: ${scene}。身体状態: ${conds}。` +
    buildCheckInNote(req.current.check_in, req.current.next_slot);
}

export function buildContextResponsesRequest(
  req: ContextAssistRequest,
  cfg: { model: string; maxOutputTokens: number; reasoningEffort?: string },
): Record<string, unknown> {
  const input: Array<{ role: string; content: string }> = [{ role: "developer", content: buildCurrentNote(req) }];
  for (const m of req.messages) input.push({ role: m.role, content: m.content });
  const body: Record<string, unknown> = {
    model: cfg.model,
    instructions: CONTEXT_INSTRUCTIONS,
    input,
    text: { format: { type: "json_schema", name: "mokorin_context", schema: CONTEXT_JSON_SCHEMA, strict: true } },
    max_output_tokens: cfg.maxOutputTokens,
    store: false,
  };
  if (cfg.reasoningEffort) body.reasoning = { effort: cfg.reasoningEffort };
  return body;
}

const PROHIBITED = ["と診断", "診断結果", "病気", "治療", "処方", "服薬"];

/** モデル出力の検証と正規化（不正な値は採用しない） */
export function validateContextResult(v: unknown): Validation<ContextAssistResult> {
  const fail = (message: string): Validation<ContextAssistResult> => ({ ok: false, message });
  if (!isObject(v)) return fail("result がオブジェクトではない");
  const extra = extraKeys(v, ["reply", "scene_candidate", "condition_candidates", "needs_clarification", "clarification_question", "tension_candidate", "emotion", "action", "situation_note", "user_intent", "check_in"], "result");
  if (extra) return fail(extra);
  if (typeof v.reply !== "string" || v.reply.trim().length === 0) return fail("reply が空");
  if (chars(v.reply) > CONTEXT_LIMITS.maxReplyChars) return fail("reply が長すぎる");
  if (PROHIBITED.some((p) => (v.reply as string).includes(p))) return fail("reply に医療的表現");
  if (!(v.scene_candidate === null || isOneOf(v.scene_candidate, CONTEXT_SCENES))) return fail("scene_candidate が不正");
  if (!Array.isArray(v.condition_candidates) || !v.condition_candidates.every((c) => isOneOf(c, BODY_CONDITIONS))) return fail("condition_candidates が不正");
  if (typeof v.needs_clarification !== "boolean") return fail("needs_clarification が不正");
  const q = v.clarification_question;
  if (!(q === null || (typeof q === "string" && chars(q) <= CONTEXT_LIMITS.maxQuestionChars))) return fail("clarification_question が不正");
  // 返答の中にすでに質問がある場合は、別の質問を重ねて表示しないよう clarification_question を外す
  // （アプリは質問が返答に含まれないときだけ後ろに付け足すため。2026-11-04 の実通信で、言い回しの違う質問が返った）
  const replyAsks = /[？?]/.test(v.reply);
  // 重複を除き、「特になし」と他の状態が同時に来たら「特になし」を外す
  let conds = [...new Set(v.condition_candidates as BodyCondition[])];
  if (conds.includes("none") && conds.length > 1) conds = conds.filter((c) => c !== "none");
  return {
    ok: true,
    value: {
      reply: v.reply.trim(),
      scene_candidate: v.scene_candidate as ContextScene | null,
      condition_candidates: conds,
      needs_clarification: v.needs_clarification,
      clarification_question: typeof q === "string" && q.trim().length > 0 && !replyAsks ? q.trim() : null,
      // 主観的な緊張は補助情報のため、不正・欠落は null（候補の採否には影響させない）
      tension_candidate: isOneOf(v.tension_candidate, SUBJECTIVE_TENSIONS) ? v.tension_candidate : null,
      // 表情・動作は見た目だけのため、不正・欠落なら原本 app.py と同じ既定値（calm / nod）にする（候補の採否には影響させない）
      emotion: isOneOf(v.emotion, MOKORIN_EMOTIONS) ? v.emotion : "calm",
      action: isOneOf(v.action, MOKORIN_ACTIONS) ? v.action : "nod",
      // 補助情報のため、不正・長すぎる値は採用せず null / answer にする（候補の採否には影響させない）
      situation_note: typeof v.situation_note === "string" && v.situation_note.trim().length > 0
        && chars(v.situation_note.trim()) <= CONTEXT_LIMITS.maxSituationNoteChars ? v.situation_note.trim() : null,
      user_intent: isOneOf(v.user_intent, USER_INTENTS) ? v.user_intent : "answer",
      // 会話の情報は補助のため、未知の値は採用せず空にする（他の候補の採否には影響させない）
      check_in: normalizeCheckIn(v.check_in),
    },
  };
}

export interface ContextOpenAIConfig {
  apiKey: string;
  model: string;
  baseUrl: string;
  timeoutMs: number;
  maxOutputTokens: number;
  reasoningEffort?: string;
  fetchImpl: typeof fetch;
}

/** OpenAI を呼び出して状況整理の候補を得る */
export async function generateContextAssist(
  req: ContextAssistRequest,
  cfg: ContextOpenAIConfig,
): Promise<{ result: ContextAssistResult; model: string; usage: ChatUsage | null }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs);
  let json: unknown;
  try {
    let response: Response;
    try {
      response = await cfg.fetchImpl(`${cfg.baseUrl.replace(/\/$/, "")}/responses`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${cfg.apiKey}` },
        body: JSON.stringify(buildContextResponsesRequest(req, cfg)),
        signal: controller.signal,
      });
    } catch {
      if (controller.signal.aborted) throw new UpstreamError("upstream_timeout", `timeout after ${cfg.timeoutMs}ms`);
      throw new UpstreamError("upstream_error", "network error");
    }
    if (!response.ok) throw await upstreamErrorFromResponse(response);
    try {
      json = await response.json();
    } catch {
      if (controller.signal.aborted) throw new UpstreamError("upstream_timeout", `timeout after ${cfg.timeoutMs}ms (body)`);
      throw new UpstreamError("invalid_upstream_response", "応答が JSON ではない");
    }
  } finally {
    clearTimeout(timer);
  }
  if (!isObject(json)) throw new UpstreamError("invalid_upstream_response", "応答が JSON オブジェクトではない");
  if (json.status !== undefined && json.status !== "completed") {
    throw new UpstreamError("invalid_upstream_response", `status=${String(json.status)}`);
  }
  let text: string | null = null;
  for (const item of Array.isArray(json.output) ? json.output : []) {
    if (!isObject(item) || item.type !== "message" || !Array.isArray(item.content)) continue;
    for (const part of item.content) {
      if (!isObject(part)) continue;
      if (part.type === "refusal") throw new UpstreamError("upstream_refusal", "モデルが応答を拒否");
      if (part.type === "output_text" && typeof part.text === "string") text = part.text;
    }
  }
  if (text === null) throw new UpstreamError("invalid_upstream_response", "output_text がない");
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new UpstreamError("invalid_upstream_response", "output_text が JSON ではない");
  }
  const validated = validateContextResult(parsed);
  if (!validated.ok) throw new UpstreamError("invalid_upstream_response", validated.message);
  return {
    result: validated.value,
    model: typeof json.model === "string" ? json.model : cfg.model,
    usage: extractUsage(json),
  };
}
