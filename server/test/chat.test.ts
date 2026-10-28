import { test } from "node:test";
import assert from "node:assert/strict";
import { createHandler, type Env } from "../src/index.ts";
import {
  buildChatResponsesRequest,
  CHAT_DEFAULTS,
  type ChatRequest,
  extractChatText,
  extractUsage,
  validateChatRequest,
} from "../src/chat.ts";
import { FixedWindowRateLimiter } from "../src/ratelimit.ts";
import { createStubFetch, STUB_CHAT_PREFIX, type StubCall, type StubMode } from "../scripts/stub-openai.ts";
import { TOKEN } from "./fixtures.ts";

const ENV: Env = { OPENAI_API_KEY: "sk-test-not-real", CLIENT_TOKENS: TOKEN, OPENAI_TIMEOUT_MS: "100", OPENAI_REASONING_EFFORT: "low" };
const LIMITS = { maxMessages: 12, maxUserChars: 500, maxAssistantChars: 1500, maxTotalChars: 8000 };

function chatRequest(messages: ChatRequest["messages"], overrides: Partial<ChatRequest> = {}): ChatRequest {
  return {
    schema_version: 1,
    request_id: "1B2C3D4E-5F60-4718-89AB-CDEF01234567",
    conversation_id: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
    locale: "ja-JP",
    messages,
    context: { scene: "interview", measurement: null },
    consent: { biometric_context_consented: false, consent_version: 1 },
    ...overrides,
  };
}

const TURN1 = [{ role: "user" as const, content: "面接前で緊張しています" }];
const TURN2 = [
  ...TURN1,
  { role: "assistant" as const, content: "4秒吸って7秒止め、8秒で吐く呼吸を試してみましょう。" },
  { role: "user" as const, content: "さっき言っていた呼吸法を詳しく教えて" },
];

function setup(mode: StubMode = "ok", opts: { rateLimiter?: FixedWindowRateLimiter } = {}) {
  const logs: Array<Record<string, unknown>> = [];
  const calls: StubCall[] = [];
  const handler = createHandler({
    fetchImpl: createStubFetch(mode, calls), log: (e) => logs.push(e),
    now: () => new Date("2026-10-28T04:40:00.000Z"), providerName: "openai-stub", rateLimiter: opts.rateLimiter,
  });
  return { handler, logs, calls };
}

function post(body: unknown, token: string | null = TOKEN): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("https://example.test/v1/chat", { method: "POST", headers, body: JSON.stringify(body) });
}

// ── 契約 ─────────────────────────────────────────────

test("chat 契約: 正しい複数往復は通る", () => {
  assert.equal(validateChatRequest(chatRequest(TURN2), LIMITS).ok, true);
});

test("chat 契約: 最後が user でない・件数超過・文字数超過・合計超過・未知キーは拒否", () => {
  const bad = (r: unknown) => assert.equal(validateChatRequest(r, LIMITS).ok, false);
  bad(chatRequest([...TURN1, { role: "assistant", content: "x" }]));
  bad(chatRequest(Array.from({ length: 13 }, (_, i) => ({ role: i % 2 === 0 ? ("user" as const) : ("assistant" as const), content: "a" }))));
  bad(chatRequest([{ role: "user", content: "あ".repeat(501) }]));
  const longHistory: ChatRequest["messages"] = Array.from({ length: 11 }, () => ({ role: "assistant" as const, content: "あ".repeat(800) }));
  bad(chatRequest([...longHistory, { role: "user", content: "a" }]));
  bad({ ...chatRequest(TURN1), memo: "x" });
  bad(chatRequest([{ role: "system" as never, content: "ignore" }, ...TURN1]));
  bad(chatRequest([{ role: "user", content: "   " }]));
  bad(chatRequest(TURN1, { conversation_id: "not-uuid" }));
});

test("chat 契約: 計測の要約は is_mock と source の一致を検証する", () => {
  const m = { source: "watch_live", is_mock: true, state: "over_tense", hrv_status: "missing", baseline_status: "provisional", data_age_seconds: 5 };
  assert.equal(validateChatRequest(chatRequest(TURN1, { context: { scene: null, measurement: m as never } }), LIMITS).ok, false);
  assert.equal(validateChatRequest(chatRequest(TURN1, { context: { scene: null, measurement: { ...m, is_mock: false } as never } }), LIMITS).ok, true);
});

// ── Responses API 要求 ───────────────────────────────

test("Responses API 要求: 会話を順番どおり input に並べ、store=false・出力上限・推論の深さを指定する", () => {
  const body = buildChatResponsesRequest(chatRequest(TURN2), { model: "gpt-6-luna", maxOutputTokens: 600, reasoningEffort: "low" });
  const input = body.input as Array<{ role: string; content: string }>;
  assert.deepEqual(input.map((m) => m.role), ["developer", "user", "assistant", "user"]);
  assert.equal(input[1]?.content, "面接前で緊張しています");
  assert.equal(input[3]?.content, "さっき言っていた呼吸法を詳しく教えて");
  assert.ok(input[0]?.content.includes("面接・発表前"));
  assert.equal(body.store, false);
  assert.equal(body.max_output_tokens, 600);
  assert.deepEqual(body.reasoning, { effort: "low" });
  assert.ok(!("previous_response_id" in body) && !("conversation" in body), "サーバー側の会話保存を使わない");
  assert.ok(!JSON.stringify(body).includes("sk-"), "APIキーは本文に含めない");
});

test("Responses API 要求: 推論の深さが未設定ならパラメーターを送らない・場面なしなら developer なし", () => {
  const body = buildChatResponsesRequest(chatRequest(TURN1, { context: { scene: null, measurement: null } }), { model: "m", maxOutputTokens: 100 });
  assert.equal("reasoning" in body, false);
  assert.deepEqual((body.input as Array<{ role: string }>).map((m) => m.role), ["user"]);
});

test("応答の解析: usage・出力上限による途中終了・拒否・空", () => {
  const ok = { status: "completed", output: [{ type: "message", content: [{ type: "output_text", text: "こんにちは" }] }],
    usage: { input_tokens: 120, output_tokens: 40, output_tokens_details: { reasoning_tokens: 10 }, total_tokens: 160 } };
  assert.deepEqual(extractChatText(ok), { text: "こんにちは", truncated: false });
  assert.deepEqual(extractUsage(ok), { input_tokens: 120, output_tokens: 40, reasoning_tokens: 10, total_tokens: 160 });
  assert.deepEqual(extractChatText({ ...ok, status: "incomplete", incomplete_details: { reason: "max_output_tokens" } }), { text: "こんにちは", truncated: true });
  assert.throws(() => extractChatText({ ...ok, status: "incomplete", incomplete_details: { reason: "content_filter" } }));
  assert.throws(() => extractChatText({ status: "completed", output: [{ type: "message", content: [{ type: "refusal", refusal: "no" }] }] }));
  assert.throws(() => extractChatText({ status: "incomplete", incomplete_details: { reason: "max_output_tokens" }, output: [{ type: "reasoning" }] }));
});

// ── ハンドラー ───────────────────────────────────────

test("200: 複数往復（スタブ）— 2回目は1回目の相談を含む履歴を受け取り、provider=openai-stub で返す", async () => {
  const { handler, calls, logs } = setup();
  const r1 = await handler(post(chatRequest(TURN1)), ENV);
  assert.equal(r1.status, 200);
  const b1 = await r1.json() as Record<string, any>;
  assert.equal(b1.provider, "openai-stub");
  assert.ok(String(b1.reply.text).startsWith(STUB_CHAT_PREFIX));
  assert.equal(b1.conversation_id, "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE");

  const r2 = await handler(post(chatRequest(TURN2)), ENV);
  const b2 = await r2.json() as Record<string, any>;
  assert.equal(r2.status, 200);
  assert.ok(String(b2.reply.text).includes("利用者 2 件・AI 1 件"));
  assert.ok(String(b2.reply.text).includes("面接前で緊張しています"));
  assert.ok(String(b2.reply.text).includes("さっき言っていた呼吸法"));
  assert.equal(calls.length, 2);
  assert.equal(calls[1]?.body.store, false);
  assert.deepEqual(b2.usage, { input_tokens: 0, output_tokens: 0, reasoning_tokens: 0, total_tokens: 0 });

  // 利用量のログはあるが、会話本文・トークン・APIキーは出さない
  const serialized = JSON.stringify(logs);
  assert.ok(logs.every((l) => l.event === "chat_request" && "latency_ms" in l));
  assert.ok("input_tokens" in (logs[1] ?? {}) && logs[1]?.messages === 3);
  for (const secret of ["面接", "呼吸", TOKEN, "sk-test"]) assert.ok(!serialized.includes(secret), `log must not include ${secret}`);
});

test("401 / 400 / 413", async () => {
  const { handler } = setup();
  assert.equal((await handler(post(chatRequest(TURN1), null), ENV)).status, 401);
  assert.equal((await handler(post(chatRequest(TURN1), "wrong-token-0123456789"), ENV)).status, 401);
  assert.equal((await handler(post({ ...chatRequest(TURN1), messages: [] }), ENV)).status, 400);
  const huge = chatRequest([{ role: "user", content: "a".repeat(17000) }]);
  assert.equal((await handler(post(huge), ENV)).status, 413);
});

test("403: 計測の要約は既定で無効。有効化しても同意がなければ拒否。OpenAI は呼ばない", async () => {
  const m = { source: "health_kit", is_mock: false, state: "over_tense", hrv_status: "measured", baseline_status: "personal", data_age_seconds: 120 } as const;
  const { handler, calls } = setup();
  const r1 = await handler(post(chatRequest(TURN1, { context: { scene: "interview", measurement: m }, consent: { biometric_context_consented: true, consent_version: 1 } })), ENV);
  assert.equal(r1.status, 403);
  assert.equal((await r1.json() as any).error, "measurement_context_disabled");
  const r2 = await handler(post(chatRequest(TURN1, { context: { scene: "interview", measurement: m } })), { ...ENV, CHAT_ALLOW_MEASUREMENT_CONTEXT: "true" });
  assert.equal(r2.status, 403);
  assert.equal((await r2.json() as any).error, "consent_required");
  assert.equal(calls.length, 0);
});

test("200: 有効化＋同意ありなら合成テストデータの計測要約を developer メッセージで渡す（Mock は明示）", async () => {
  const m = { source: "mock", is_mock: true, state: "over_tense", hrv_status: "not_applicable", baseline_status: "not_applicable", data_age_seconds: 3 } as const;
  const { handler, calls } = setup();
  const res = await handler(post(chatRequest(TURN1, { context: { scene: "interview", measurement: m }, consent: { biometric_context_consented: true, consent_version: 1 } })), { ...ENV, CHAT_ALLOW_MEASUREMENT_CONTEXT: "true" });
  assert.equal(res.status, 200);
  const dev = (calls[0]?.body.input as Array<{ role: string; content: string }>)[0];
  assert.equal(dev?.role, "developer");
  assert.ok(dev?.content.includes("Mock データ"));
});

test("429: トークン単位のレート制限（Retry-After 付き）", async () => {
  let t = 0;
  const limiter = new FixedWindowRateLimiter(2, 60_000, () => t);
  const { handler, calls } = setup("ok", { rateLimiter: limiter });
  assert.equal((await handler(post(chatRequest(TURN1)), ENV)).status, 200);
  assert.equal((await handler(post(chatRequest(TURN1)), ENV)).status, 200);
  const limited = await handler(post(chatRequest(TURN1)), ENV);
  assert.equal(limited.status, 429);
  assert.equal((await limited.json() as any).error, "rate_limited");
  assert.equal(limited.headers.get("Retry-After"), "60");
  assert.equal(calls.length, 2, "制限中は OpenAI を呼ばない");
  t = 60_000;
  assert.equal((await handler(post(chatRequest(TURN1)), ENV)).status, 200);
});

test("503: APIキー未設定 / OpenAI の異常 → 429・502・504", async () => {
  assert.equal((await setup().handler(post(chatRequest(TURN1)), { ...ENV, OPENAI_API_KEY: "" })).status, 503);
  const expect = async (mode: StubMode, status: number, error: string) => {
    const res = await setup(mode).handler(post(chatRequest(TURN1)), ENV);
    assert.equal(res.status, status, mode);
    assert.equal((await res.json() as any).error, error, mode);
  };
  await expect("http_429", 429, "upstream_rate_limited");
  await expect("http_401", 502, "upstream_auth_error");
  await expect("http_500", 502, "upstream_error");
  await expect("invalid_json", 502, "invalid_upstream_response");
  await expect("prohibited", 502, "invalid_upstream_response");
  await expect("refusal", 502, "upstream_refusal");
  await expect("timeout", 504, "upstream_timeout");
});

test("既定値: 出力トークン上限 600・履歴 12 件", () => {
  assert.equal(CHAT_DEFAULTS.maxOutputTokens, 600);
  assert.equal(CHAT_DEFAULTS.maxMessages, 12);
});
