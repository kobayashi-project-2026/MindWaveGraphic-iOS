import { test } from "node:test";
import assert from "node:assert/strict";
import { createHandler, type Env } from "../src/index.ts";
import {
  buildContextResponsesRequest,
  CONTEXT_JSON_SCHEMA,
  type ContextAssistRequest,
  validateContextAssistRequest,
  validateContextResult,
} from "../src/context.ts";
import { createStubFetch, STUB_CHAT_PREFIX, type StubCall, type StubMode } from "../scripts/stub-openai.ts";
import { TOKEN } from "./fixtures.ts";

const ENV: Env = { OPENAI_API_KEY: "sk-test-not-real", CLIENT_TOKENS: TOKEN, OPENAI_TIMEOUT_MS: "100" };

function request(messages: ContextAssistRequest["messages"], overrides: Partial<ContextAssistRequest> = {}): ContextAssistRequest {
  return {
    schema_version: 1,
    request_id: "2B2C3D4E-5F60-4718-89AB-CDEF01234567",
    conversation_id: "BBBBBBBB-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
    locale: "ja-JP",
    step: "scene",
    messages,
    current: { scene: null, conditions: [] },
    ...overrides,
  };
}

const FIRST = [
  { role: "assistant" as const, content: "こんにちは！今はどんな状況かな？" },
  { role: "user" as const, content: "これから就職活動の面接があって、少し緊張しています" },
];

function setup(mode: StubMode = "ok") {
  const logs: Array<Record<string, unknown>> = [];
  const calls: StubCall[] = [];
  const handler = createHandler({ fetchImpl: createStubFetch(mode, calls), log: (e) => logs.push(e), providerName: "openai-stub" });
  return { handler, logs, calls };
}

function post(body: unknown, token: string | null = TOKEN): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("https://example.test/v1/context-assist", { method: "POST", headers, body: JSON.stringify(body) });
}

test("context 契約: 正しい要求は通る・不正な step/場面/状態/未知キー/最後が assistant は拒否", () => {
  assert.equal(validateContextAssistRequest(request(FIRST)).ok, true);
  const bad = (r: unknown) => assert.equal(validateContextAssistRequest(r).ok, false);
  bad(request(FIRST, { step: "measure" as never }));
  bad(request(FIRST, { current: { scene: "party" as never, conditions: [] } }));
  bad(request(FIRST, { current: { scene: null, conditions: ["dancing" as never] } }));
  bad({ ...request(FIRST), heart_rate: 90 });
  bad(request([FIRST[0]!]));
  bad(request([{ role: "user", content: "あ".repeat(301) }]));
});

test("Structured Outputs: strict・全項目 required・候補は既存 enum に限定・store=false・計測データの項目なし", () => {
  const body = buildContextResponsesRequest(request(FIRST), { model: "gpt-6-luna", maxOutputTokens: 400, reasoningEffort: "low" });
  const format = (body.text as any).format;
  assert.equal(format.type, "json_schema");
  assert.equal(format.strict, true);
  assert.deepEqual([...CONTEXT_JSON_SCHEMA.required].sort(), Object.keys(CONTEXT_JSON_SCHEMA.properties).sort());
  assert.deepEqual(CONTEXT_JSON_SCHEMA.properties.scene_candidate.enum, ["calm", "interview", "sports", "important", "work", "other", null]);
  assert.deepEqual(CONTEXT_JSON_SCHEMA.properties.condition_candidates.items.enum, ["running", "stairs", "smoking", "caffeine", "sleep_lack", "after_meal", "none"]);
  assert.equal(body.store, false);
  const input = body.input as Array<{ role: string; content: string }>;
  assert.deepEqual(input.map((m) => m.role), ["developer", "assistant", "user"]);
  // 計測値の項目がない（本人が話す「心臓がドキドキ」= heart_pounding や、禁止を述べる指示文は対象外）
  assert.ok(!JSON.stringify(body).match(/heart_rate|hrv_sdnn|"hrv"|"sdnn"|bpm|sk-/i));
});

test("結果の検証: 未知の候補・型不正・医療的表現は不採用、none と他の状態の同時指定は none を外す", () => {
  const ok = { reply: "面接前なんだね", scene_candidate: "interview", condition_candidates: ["stairs", "none", "stairs"], needs_clarification: false, clarification_question: null, emotion: "calm", action: "nod" };
  const v = validateContextResult(ok);
  assert.ok(v.ok);
  if (v.ok) assert.deepEqual(v.value.condition_candidates, ["stairs"]);
  assert.equal(validateContextResult({ ...ok, scene_candidate: "office_party" }).ok, false);
  assert.equal(validateContextResult({ ...ok, condition_candidates: ["flying"] }).ok, false);
  assert.equal(validateContextResult({ ...ok, needs_clarification: "yes" }).ok, false);
  assert.equal(validateContextResult({ ...ok, reply: "不安障害と診断されます" }).ok, false);
  assert.equal(validateContextResult({ ...ok, extra: 1 }).ok, false);
});

test("200（スタブ）: 面接の文章から scene=interview、階段の文章から stairs。スタブと明示し、ログに本文を出さない", async () => {
  const { handler, logs } = setup();
  const r1 = await handler(post(request(FIRST)), ENV);
  assert.equal(r1.status, 200);
  const b1 = await r1.json() as any;
  assert.equal(b1.provider, "openai-stub");
  assert.equal(b1.result.scene_candidate, "interview");
  assert.ok(!String(b1.result.reply).includes("キーワード判定"), "機械的な文を返さない");
  assert.ok(String(b1.result.reply).includes("？"), "次の質問を含む自然な返答");
  const r2 = await handler(post(request([...FIRST, { role: "assistant", content: "面接前なんだね。" }, { role: "user", content: "さっき階段を上ってきました" }],
    { step: "condition", current: { scene: "interview", conditions: [] } })), ENV);
  const b2 = await r2.json() as any;
  assert.deepEqual(b2.result.condition_candidates, ["stairs"]);
  const serialized = JSON.stringify(logs);
  assert.ok(logs.every((l) => l.event === "context_assist_request"));
  for (const secret of ["面接", "階段", "interview", TOKEN]) assert.ok(!serialized.includes(secret), `log must not include ${secret}`);
});

test("曖昧な文章（緊張しているだけ）: スタブは場面を決めず needs_clarification=true", async () => {
  const res = await setup().handler(post(request([{ role: "user", content: "少し緊張しています" }])), ENV);
  const b = await res.json() as any;
  assert.equal(b.result.scene_candidate, null);
  assert.equal(b.result.needs_clarification, true);
});

test("異常系: 401 / 400 / 503 / 不正な候補 502 / タイムアウト 504 / OpenAI 429", async () => {
  assert.equal((await setup().handler(post(request(FIRST), null), ENV)).status, 401);
  assert.equal((await setup().handler(post({ ...request(FIRST), messages: [] }), ENV)).status, 400);
  assert.equal((await setup().handler(post(request(FIRST)), { ...ENV, OPENAI_API_KEY: "" })).status, 503);
  const expect = async (mode: StubMode, status: number, error: string) => {
    const res = await setup(mode).handler(post(request(FIRST)), ENV);
    assert.equal(res.status, status, mode);
    assert.equal((await res.json() as any).error, error, mode);
  };
  await expect("invalid_candidate", 502, "invalid_upstream_response");
  await expect("invalid_json", 502, "invalid_upstream_response");
  await expect("timeout", 504, "upstream_timeout");
  await expect("http_429", 429, "upstream_rate_limited");
});

test("既存の /v1/chat は影響を受けない（スタブの会話返答のまま）", async () => {
  const { handler } = setup();
  const chatReq = {
    schema_version: 1, request_id: "1B2C3D4E-5F60-4718-89AB-CDEF01234567", conversation_id: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
    locale: "ja-JP", messages: [{ role: "user", content: "面接前で緊張しています" }],
    context: { scene: null, measurement: null }, consent: { biometric_context_consented: false, consent_version: 1 },
  };
  const res = await handler(new Request("https://example.test/v1/chat", {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${TOKEN}` }, body: JSON.stringify(chatReq),
  }), ENV);
  assert.equal(res.status, 200);
  assert.ok(String((await res.json() as any).reply.text).includes("受け取った履歴"));
});

test("表情・動作（友達の原本と同じ許可値）: schema の enum、不正・欠落は calm / nod（候補は採用したまま）", () => {
  assert.deepEqual(CONTEXT_JSON_SCHEMA.properties.emotion.enum, ["happy", "calm", "sad", "sleepy"]);
  assert.deepEqual(CONTEXT_JSON_SCHEMA.properties.action.enum, ["wave", "jump", "nod"]);
  const base = { reply: "面接前なんだね", scene_candidate: "interview", condition_candidates: [], needs_clarification: false, clarification_question: null };
  const good = validateContextResult({ ...base, emotion: "happy", action: "wave" });
  assert.ok(good.ok && good.value.emotion === "happy" && good.value.action === "wave");
  const bad = validateContextResult({ ...base, emotion: "angry", action: "dance" });
  assert.ok(bad.ok && bad.value.emotion === "calm" && bad.value.action === "nod" && bad.value.scene_candidate === "interview");
  const missing = validateContextResult(base);
  assert.ok(missing.ok && missing.value.emotion === "calm" && missing.value.action === "nod");
});

test("200（スタブ）: 応答に emotion / action を含む", async () => {
  const res = await setup().handler(post(request(FIRST)), ENV);
  const b = await res.json() as any;
  assert.ok(["happy", "calm", "sad", "sleepy"].includes(b.result.emotion));
  assert.ok(["wave", "jump", "nod"].includes(b.result.action));
});

test("主観的な緊張（tension 段階）: step と current.tension を受け付け、tension_candidate を返す。不正値は null", async () => {
  assert.equal(validateContextAssistRequest(request([{ role: "user", content: "かなり緊張してる" }], { step: "tension" as never, current: { scene: null, conditions: [], tension: null } as never })).ok, true);
  assert.equal(validateContextAssistRequest(request(FIRST, { current: { scene: null, conditions: [], tension: "panic" } as never })).ok, false);
  assert.deepEqual(CONTEXT_JSON_SCHEMA.properties.tension_candidate.enum, ["calm", "slight", "high", null]);
  const base = { reply: "そっか", scene_candidate: null, condition_candidates: [], needs_clarification: false, clarification_question: null, emotion: "calm", action: "nod" };
  const ok = validateContextResult({ ...base, tension_candidate: "high" });
  assert.ok(ok.ok && ok.value.tension_candidate === "high");
  const bad = validateContextResult({ ...base, tension_candidate: "very" });
  assert.ok(bad.ok && bad.value.tension_candidate === null);
  const res = await setup().handler(post(request([{ role: "user", content: "かなり緊張してる" }], { step: "tension" as never })), ENV);
  const b = await res.json() as any;
  assert.equal(res.status, 200);
  assert.equal(b.result.tension_candidate, "high");
});

test("実通信の準備: 状況整理は推論モデルのとき reasoning=none（設定で変更可）・出力上限 500", async () => {
  const calls: StubCall[] = [];
  const handler = createHandler({ fetchImpl: createStubFetch("ok", calls), log: () => {}, providerName: "openai-stub" });
  await handler(post(request(FIRST)), { ...ENV, OPENAI_REASONING_EFFORT: "low" });
  assert.deepEqual(calls[0]?.body.reasoning, { effort: "none" });
  assert.equal(calls[0]?.body.max_output_tokens, 500);
  await handler(post(request(FIRST)), { ...ENV, OPENAI_REASONING_EFFORT: "low", CONTEXT_REASONING_EFFORT: "low", CONTEXT_MAX_OUTPUT_TOKENS: "700" });
  assert.deepEqual(calls[1]?.body.reasoning, { effort: "low" });
  assert.equal(calls[1]?.body.max_output_tokens, 700);
  await handler(post(request(FIRST)), { ...ENV, OPENAI_REASONING_EFFORT: "" });
  assert.equal("reasoning" in (calls[2]?.body ?? {}), false, "非推論モデル設定では送らない");
});

test("実通信の準備: OpenAI のエラーは分類（type / code / param）だけをログに残し、本文は残さない", async () => {
  const logs: Array<Record<string, unknown>> = [];
  const handler = createHandler({ fetchImpl: createStubFetch("http_429"), log: (e) => logs.push(e), providerName: "openai-stub" });
  const res = await handler(post(request(FIRST)), ENV);
  assert.equal(res.status, 429);
  assert.equal(logs[0]?.upstream_status, 429);
  assert.equal(logs[0]?.upstream_error_type, "rate_limit_exceeded");
  assert.ok(!JSON.stringify(logs).includes("stub rate limit"), "エラーメッセージ本文は記録しない");
});

test("実通信の準備: /v1/health は STUB / 実通信のどちらで動いているかを返す（秘密情報なし）", async () => {
  const stub = await createHandler({ providerName: "openai-stub" })(new Request("https://x.test/v1/health"), ENV);
  assert.equal((await stub.json() as any).provider_mode, "stub");
  const real = await createHandler({})(new Request("https://x.test/v1/health"), ENV);
  const body = await real.text();
  assert.equal(JSON.parse(body).provider_mode, "openai");
  assert.ok(!body.includes("sk-") && !body.includes(TOKEN));
});

test("実通信の結果を反映: 返答に質問があるときは clarification_question を外す（質問が二重に表示されないように）", () => {
  const base = { scene_candidate: null, condition_candidates: [], needs_clarification: true, tension_candidate: "high", emotion: "calm", action: "nod" };
  const asked = validateContextResult({ ...base, reply: "そっか、かなり緊張してるんだね。何か予定があるの？", clarification_question: "どんな予定の前かな？" });
  assert.ok(asked.ok && asked.value.clarification_question === null && asked.value.needs_clarification === true);
  const notAsked = validateContextResult({ ...base, reply: "そっか、かなり緊張してるんだね。", clarification_question: "どんな予定の前かな？" });
  assert.ok(notAsked.ok && notAsked.value.clarification_question === "どんな予定の前かな？");
});

test("訂正の指示: 最新の発言を優先し、取り消された身体状態を入れないようモデルに伝える", () => {
  const body = buildContextResponsesRequest(request(FIRST), { model: "m", maxOutputTokens: 100 });
  assert.ok(String(body.instructions).includes("最新の発言を優先"));
});

test("スタブの返答: 3往復が自然な文で進み、訂正（やっぱり〜）は最新の発言を優先", async () => {
  const { stubContextResult } = await import("../scripts/stub-openai.ts");
  const turn = (text: string, note = "現在の段階: tension") =>
    stubContextResult({ input: [{ role: "developer", content: note }, { role: "user", content: text }] }) as any;
  const a = turn("かなり緊張してる");
  assert.equal(a.tension_candidate, "high");
  assert.match(a.reply, /予定/);
  const b = turn("これから就活の面接なんだ", "現在の段階: scene");
  assert.equal(b.scene_candidate, "interview");
  assert.match(b.reply, /座ってる？/);
  const c = turn("さっき階段を上ってきた", "現在の段階: condition。画面で選択中の場面: 面接・発表。");
  assert.deepEqual(c.condition_candidates, ["stairs"]);
  assert.match(c.reply, /測定してみようか？$/);
  assert.equal(turn("やっぱり面接じゃなくて試合だった", "現在の段階: condition").scene_candidate, "sports");
  assert.equal(turn("特に予定はない", "現在の段階: scene").scene_candidate, "calm");
  for (const r of [a, b, c]) assert.equal(r.clarification_question, null, "質問を二重にしない");
});

test("2026-11-05 追加の補助項目: situation_note・user_intent。欠落・不正・長すぎる値は null / answer にして候補は採用する（古い出力とも互換）", () => {
  const base = { reply: "試験の前なんだね。今は座ってる？", scene_candidate: "work", condition_candidates: [], needs_clarification: false,
    clarification_question: null, tension_candidate: null, emotion: "calm", action: "nod" };
  const old = validateContextResult(base);
  assert.ok(old.ok && old.value.situation_note === null && old.value.user_intent === "answer", "古い出力（項目なし）");
  const ok = validateContextResult({ ...base, situation_note: "明日の英語の試験", user_intent: "answer" });
  assert.ok(ok.ok && ok.value.situation_note === "明日の英語の試験" && ok.value.scene_candidate === "work");
  const bad = validateContextResult({ ...base, situation_note: "あ".repeat(41), user_intent: "dance" });
  assert.ok(bad.ok && bad.value.situation_note === null && bad.value.user_intent === "answer", "不正値は採用しない");
  const schema = CONTEXT_JSON_SCHEMA as any;
  assert.ok(schema.required.includes("situation_note") && schema.required.includes("user_intent"), "strict: 全項目 required");
  assert.ok(String(buildContextResponsesRequest(request(FIRST), { model: "m", maxOutputTokens: 100 }).instructions).includes("同じ質問・同じ言い回しを繰り返さない"));
});

test("スタブ: 測定を望まない・質問・場面にない予定（試験）を区別する", async () => {
  const { stubContextResult } = await import("../scripts/stub-openai.ts");
  const turn = (text: string) => stubContextResult({ input: [{ role: "developer", content: "現在の段階: scene" }, { role: "user", content: text }] }) as any;
  assert.equal(turn("今日は測りたくない").user_intent, "decline_measurement");
  assert.equal(turn("もこりんって何歳？").user_intent, "question");
  const exam = turn("明日、英語の試験がある");
  assert.equal(exam.situation_note, "明日、英語の試験がある");
});

test("指示: 過去の出来事は予定（場面）として扱わない（2026-11-05 の実通信で「昨日の試験」が work になった）", () => {
  const body = buildContextResponsesRequest(request(FIRST), { model: "m", maxOutputTokens: 100 });
  assert.ok(String(body.instructions).includes("過去の出来事は、これからの予定ではない"));
});

test("2026-11-11 会話の情報（check_in）: 要求で受け取り developer メッセージに入れる。不正な値は 400。古いアプリ（項目なし）も可", async () => {
  const { handler } = setup();
  const checkIn = { sleep: "5_7h", activity: null, condition: null, situation: "interview_exam", timing: null, emotion: null, tension_level: 75,
    causes: [], body_signals: ["heart_pounding"], support: null, declined: ["activity"], asked: ["sleep", "situation"], remaining_slots: ["timing", "emotion", "support"] };
  const ok = await handler(post(request(FIRST, { current: { scene: null, conditions: [], check_in: checkIn, next_slot: "timing" } })), ENV);
  assert.equal(ok.status, 200);
  const body = buildContextResponsesRequest({ ...(JSON.parse(JSON.stringify(request(FIRST))) as any), current: { scene: null, conditions: [], check_in: checkIn, next_slot: "timing" } }, { model: "m", maxOutputTokens: 100 }) as any;
  const note = String(body.input[0].content);
  assert.ok(note.includes("場面=interview_exam") && note.includes("緊張の強さ(0〜100)=75") && note.includes("次に尋ねる候補（優先順）: timing,emotion,support"), note);
  const bad = await handler(post(request(FIRST, { current: { scene: null, conditions: [], check_in: { ...checkIn, emotion: "dance" } } })), ENV);
  assert.equal(bad.status, 400);
  const badTension = await handler(post(request(FIRST, { current: { scene: null, conditions: [], check_in: { ...checkIn, tension_level: 150 } } })), ENV);
  assert.equal(badTension.status, 400);
});

test("check_in の出力: strict の schema（全項目 required・null 可）。未知の値は採用しない。none と具体的な症状は同時に出さない", async () => {
  const schema = CONTEXT_JSON_SCHEMA as any;
  assert.ok(schema.required.includes("check_in"));
  const ci = schema.properties.check_in;
  assert.equal(ci.additionalProperties, false);
  assert.deepEqual([...ci.required].sort(), Object.keys(ci.properties).sort());
  const base = { reply: "明日の面接なんだね。今の気持ちは？", scene_candidate: "interview", condition_candidates: [], needs_clarification: false,
    clarification_question: null, tension_candidate: null, emotion: "calm", action: "nod", situation_note: null, user_intent: "answer" };
  const r = validateContextResult({ ...base, check_in: { sleep: "lots", activity: null, condition: null, situation: "interview_exam", timing: "tomorrow_or_later",
    emotion: null, tension_level: 300, causes: ["failure", "x"], body_signals: ["none", "trembling"], support: null, declined: [] } });
  assert.ok(r.ok);
  assert.equal(r.value.check_in.sleep, null);
  assert.equal(r.value.check_in.tension_level, null);
  assert.deepEqual(r.value.check_in.causes, ["failure"]);
  assert.deepEqual(r.value.check_in.body_signals, ["trembling"]);
  const old = validateContextResult(base);
  assert.ok(old.ok && old.value.check_in.situation === null, "check_in なしの出力でも動く");
  assert.ok(String(buildContextResponsesRequest(request(FIRST), { model: "m", maxOutputTokens: 100 }).instructions).includes("気持ちの種類（emotion）と緊張の強さ（tension_level）は別"));
});

test("スタブ: 次に尋ねる候補があれば、その質問を 1 つ返す（今尋ねている項目はとばす）", async () => {
  const { stubContextResult } = await import("../scripts/stub-openai.ts");
  const r = stubContextResult({ input: [{ role: "developer", content: "現在の段階: tension。 次に尋ねる候補（優先順）: sleep,condition,situation。今尋ねている項目: sleep。" },
    { role: "user", content: "6時間くらい" }] }) as any;
  assert.match(r.reply, /今の体調はどう？/);
  assert.ok(r.check_in && "tension_level" in r.check_in);
});
