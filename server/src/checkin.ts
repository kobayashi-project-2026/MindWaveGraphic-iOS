// checkin.ts
// もこりんの会話で集める情報（STEP 0〜6）。2026-11-11 追加。アプリの MokorinCheckIn（Swift）と同じ列挙値。
// - 要求 current.check_in（省略可能）: これまでに分かっている項目・答えたくない項目・尋ねた項目・次に尋ねる候補
// - 要求 current.next_slot（省略可能）: 今尋ねている項目
// - 応答 result.check_in: 今回の発言から取り出した項目（Structured Outputs では全項目 required・null 可）
// 主観的な緊張の強さ（tension_level 0〜100）は本人の評価。AI が数値を推測・計算しない（スコアの計算はアプリが行う）。

export const CHECKIN_SLOTS = ["sleep", "activity", "condition", "situation", "timing", "emotion", "tension", "cause", "body", "support"] as const;
export const SLEEP = ["under_3h", "3_5h", "5_7h", "7_9h", "over_9h", "unknown"] as const;
export const ACTIVITY = ["exercised", "light", "usual", "little"] as const;
export const CONDITION = ["energetic", "slightly_tired", "very_tired", "sluggish", "unwell"] as const;
export const SITUATION = ["presentation", "interview_exam", "communication", "important_event", "restless", "other"] as const;
export const TIMING = ["soon", "today", "tomorrow_or_later", "finished", "not_specific"] as const;
export const EMOTION = ["tense", "anxious", "rushed", "unconfident", "irritated", "unsure"] as const;
export const CAUSES = ["failure", "others_view", "speaking", "outcome", "ability", "comparison", "unknown", "other"] as const;
export const BODY = ["heart_pounding", "shallow_breath", "trembling", "tense_muscles", "foggy", "none", "unsure"] as const;
export const SUPPORT = ["calm_down", "organize", "confidence", "refresh", "find_method", "unsure"] as const;

export interface CheckInResult {
  sleep: (typeof SLEEP)[number] | null;
  activity: (typeof ACTIVITY)[number] | null;
  condition: (typeof CONDITION)[number] | null;
  situation: (typeof SITUATION)[number] | null;
  timing: (typeof TIMING)[number] | null;
  emotion: (typeof EMOTION)[number] | null;
  tension_level: number | null;
  causes: Array<(typeof CAUSES)[number]>;
  body_signals: Array<(typeof BODY)[number]>;
  support: (typeof SUPPORT)[number] | null;
  declined: Array<(typeof CHECKIN_SLOTS)[number]>;
}

const LABELS: Record<string, string> = {
  sleep: "昨夜の睡眠", activity: "今日の活動", condition: "体調", situation: "場面", timing: "時期", emotion: "気持ち",
  tension: "緊張の強さ(0〜100)", cause: "気になること", body: "体の変化", support: "してみたいこと",
};

const nullableEnum = (values: readonly string[]) => ({ type: ["string", "null"], enum: [...values, null] });

/** Structured Outputs（strict）の check_in */
export const CHECKIN_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["sleep", "activity", "condition", "situation", "timing", "emotion", "tension_level", "causes", "body_signals", "support", "declined"],
  properties: {
    sleep: nullableEnum(SLEEP),
    activity: nullableEnum(ACTIVITY),
    condition: nullableEnum(CONDITION),
    situation: nullableEnum(SITUATION),
    timing: nullableEnum(TIMING),
    emotion: nullableEnum(EMOTION),
    tension_level: { type: ["integer", "null"], description: "本人が言った緊張の強さ（0〜100）。言っていなければ null。推測しない" },
    causes: { type: "array", items: { type: "string", enum: [...CAUSES] } },
    body_signals: { type: "array", items: { type: "string", enum: [...BODY] } },
    support: nullableEnum(SUPPORT),
    declined: { type: "array", items: { type: "string", enum: [...CHECKIN_SLOTS] }, description: "本人が答えたくないと言った項目" },
  },
} as const;

export const CHECKIN_INSTRUCTIONS = [
  "会話で確かめる情報（STEP 0〜6）: 睡眠・今日の活動・体調・場面・時期・気持ち・緊張の強さ(0〜100)・気になること・体の変化・してみたいこと。",
  "- check_in には、今回の利用者の発言から分かった項目だけを入れる。言っていない項目は null / 空配列。推測しない。",
  "- 1 つの発言に複数の情報があれば、すべて取り出す（例:「明日面接があって、不安であまり寝られなかった。今は心臓がドキドキしてる」→ situation=interview_exam, timing=tomorrow_or_later, emotion=anxious, sleep=3_5h, body_signals=[heart_pounding]）。",
  "- 気持ちの種類（emotion）と緊張の強さ（tension_level）は別。イライラ・不安を強い緊張と決めつけない。tension_level は本人が強さを言ったときだけ（かなり=75、少し=20、とても強い=100、落ち着いている=0、数字を言えばその数）。",
  "- body_signals の none（特にない）・unsure（分からない）は、具体的な症状と同時に入れない。",
  "- 答えたくない・とばしたいと言われた項目は declined に入れ、二度と尋ねない。",
  "- 質問は次に尋ねる候補（remaining_slots）の先頭のうち、今回の発言で分からなかったものを 1 つだけ。すでに分かっている項目・尋ねた項目（asked）は尋ねない。必要な情報（場面・気持ち・緊張の強さ・してみたいこと）がそろったら質問をやめ、短くまとめて測定や改善を提案する。",
  "- 最初から緊張していると決めつけない。落ち着いている人には軽く進める。同じ相づちを繰り返さない。",
  "- 体調が悪いと言われたら質問を続けず休むことをすすめる。深刻な症状（胸の痛み・強い息苦しさ・失神など）は医療機関・救急への相談を短く伝える。",
  "- 心拍・HRV・スコアの数値を推測・計算しない。診断しない。",
].join("\n");

/** 要求の current.check_in の形を確かめる（列挙値は既知のものだけ。数は 0〜100） */
export function validateCheckInRequest(v: unknown): string | null {
  if (v === undefined || v === null) return null;
  if (typeof v !== "object" || Array.isArray(v)) return "current.check_in がオブジェクトではない";
  const o = v as Record<string, unknown>;
  const allowed = ["sleep", "activity", "condition", "situation", "timing", "emotion", "tension_level", "causes", "body_signals", "support", "declined", "asked", "remaining_slots"];
  const extra = Object.keys(o).filter((k) => !allowed.includes(k));
  if (extra.length > 0) return `current.check_in に不明な項目: ${extra.join(",")}`;
  const single: Array<[string, readonly string[]]> = [["sleep", SLEEP], ["activity", ACTIVITY], ["condition", CONDITION], ["situation", SITUATION], ["timing", TIMING], ["emotion", EMOTION], ["support", SUPPORT]];
  for (const [k, values] of single) {
    if (!(o[k] === undefined || o[k] === null || values.includes(o[k] as string))) return `current.check_in.${k} が不正`;
  }
  if (!(o.tension_level === undefined || o.tension_level === null || (Number.isInteger(o.tension_level) && (o.tension_level as number) >= 0 && (o.tension_level as number) <= 100))) {
    return "current.check_in.tension_level が不正";
  }
  const lists: Array<[string, readonly string[]]> = [["causes", CAUSES], ["body_signals", BODY], ["declined", CHECKIN_SLOTS], ["asked", CHECKIN_SLOTS], ["remaining_slots", CHECKIN_SLOTS]];
  for (const [k, values] of lists) {
    const a = o[k];
    if (a === undefined) continue;
    if (!Array.isArray(a) || a.length > 20 || !a.every((x) => values.includes(x as string))) return `current.check_in.${k} が不正`;
  }
  return null;
}

/** 現在の会話の情報を、AI への developer メッセージの一部にする（本人の発言・選択から分かったことだけ） */
export function buildCheckInNote(checkIn: Record<string, unknown> | undefined, nextSlot: unknown): string {
  if (!checkIn) return "";
  const known = ["sleep", "activity", "condition", "situation", "timing", "emotion", "support"]
    .filter((k) => typeof checkIn[k] === "string").map((k) => `${LABELS[k]}=${checkIn[k]}`);
  if (typeof checkIn.tension_level === "number") known.push(`${LABELS.tension}=${checkIn.tension_level}`);
  for (const [k, label] of [["causes", "cause"], ["body_signals", "body"]] as const) {
    const a = checkIn[k];
    if (Array.isArray(a) && a.length > 0) known.push(`${LABELS[label]}=${a.join("/")}`);
  }
  const list = (k: string) => (Array.isArray(checkIn[k]) ? (checkIn[k] as string[]).join(",") : "");
  return ` 分かっている情報: ${known.join("、") || "なし"}。答えたくない項目: ${list("declined") || "なし"}。尋ねた項目: ${list("asked") || "なし"}。` +
    `次に尋ねる候補（優先順）: ${list("remaining_slots") || "なし（まとめる）"}。今尋ねている項目: ${typeof nextSlot === "string" ? nextSlot : "なし"}。`;
}

function oneOf<T extends string>(v: unknown, values: readonly T[]): T | null {
  return typeof v === "string" && (values as readonly string[]).includes(v) ? (v as T) : null;
}

/** モデルの check_in を正規化（未知の値は採用しない。check_in がなければ空） */
export function normalizeCheckIn(v: unknown): CheckInResult {
  const o = (v && typeof v === "object" && !Array.isArray(v) ? v : {}) as Record<string, unknown>;
  const list = <T extends string>(a: unknown, values: readonly T[]): T[] =>
    Array.isArray(a) ? [...new Set(a.filter((x): x is T => typeof x === "string" && (values as readonly string[]).includes(x)))] : [];
  let body = list(o.body_signals, BODY);
  const concrete = body.filter((b) => b !== "none" && b !== "unsure");
  if (concrete.length > 0) body = concrete;
  const t = o.tension_level;
  return {
    sleep: oneOf(o.sleep, SLEEP), activity: oneOf(o.activity, ACTIVITY), condition: oneOf(o.condition, CONDITION),
    situation: oneOf(o.situation, SITUATION), timing: oneOf(o.timing, TIMING), emotion: oneOf(o.emotion, EMOTION),
    tension_level: typeof t === "number" && Number.isInteger(t) && t >= 0 && t <= 100 ? t : null,
    causes: list(o.causes, CAUSES), body_signals: body, support: oneOf(o.support, SUPPORT), declined: list(o.declined, CHECKIN_SLOTS),
  };
}

/** STUB 用: 次に尋ねる項目の質問文（アプリの CheckInSlot.question と同じ） */
export const SLOT_QUESTIONS: Record<string, string> = {
  sleep: "昨日はどのくらい眠れた？", activity: "今日はどのくらい体を動かした？", condition: "今の体調はどう？",
  situation: "今、どんな場面にいる？", timing: "その出来事はいつ頃？", emotion: "今の気持ちに一番近いものはどれ？",
  tension: "緊張の強さはどのくらい？0（全く緊張していない）から100（とても強い）で教えてね。", cause: "今、一番気になっていることはある？",
  body: "今、体に何か変化はある？いくつでも教えてね。", support: "今、どんなことをしてみたい？",
};
