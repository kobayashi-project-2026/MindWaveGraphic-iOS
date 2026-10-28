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
  assert.ok(!JSON.stringify(body).match(/heart|hrv|bpm|sk-/i));
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
  assert.ok(String(b1.result.reply).startsWith(STUB_CHAT_PREFIX));
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
