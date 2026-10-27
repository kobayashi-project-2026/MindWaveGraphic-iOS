import { test } from "node:test";
import assert from "node:assert/strict";
import { createHandler, type Env } from "../src/index.ts";
import { createStubFetch, type StubMode } from "../scripts/stub-openai.ts";
import { TOKEN, validRequest } from "./fixtures.ts";

const ENV: Env = { OPENAI_API_KEY: "sk-test-not-real", CLIENT_TOKENS: `other-token-abcdefghijkl,${TOKEN}`, OPENAI_TIMEOUT_MS: "100" };

function setup(mode: StubMode = "ok") {
  const logs: Array<Record<string, unknown>> = [];
  const handler = createHandler({ fetchImpl: createStubFetch(mode), log: (e) => logs.push(e), now: () => new Date("2026-10-28T04:40:00.000Z") });
  return { handler, logs };
}

function post(body: unknown, token: string | null = TOKEN, raw?: string): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("https://example.test/v1/insights", { method: "POST", headers, body: raw ?? JSON.stringify(body) });
}

test("GET /v1/health は秘密情報を返さない", async () => {
  const { handler } = setup();
  const res = await handler(new Request("https://example.test/v1/health"), ENV);
  assert.equal(res.status, 200);
  const text = await res.text();
  assert.ok(!text.includes("sk-test") && !text.includes(TOKEN));
  assert.equal(JSON.parse(text).openai_configured, true);
});

test("200: 契約どおりの応答・request_id のエコー", async () => {
  const { handler, logs } = setup();
  const res = await handler(post(validRequest()), ENV);
  assert.equal(res.status, 200);
  const body = await res.json() as any;
  assert.equal(body.schema_version, 1);
  assert.equal(body.request_id, validRequest().request_id);
  assert.equal(body.provider, "openai");
  assert.equal(body.generated_at, "2026-10-28T04:40:00.000Z");
  assert.equal(typeof body.insight.title, "string");
  assert.equal(logs[0]?.outcome, "ok");
});

test("ログに心拍・場面などのリクエスト内容を出さない", async () => {
  const { handler, logs } = setup();
  await handler(post(validRequest()), ENV);
  const serialized = JSON.stringify(logs);
  for (const s of ["heart_rate", "interview", "breathing478", "96", TOKEN, "sk-test"]) {
    assert.ok(!serialized.includes(s), `log contains ${s}`);
  }
});

test("401: トークンなし・不一致・サーバー未設定（fail closed）", async () => {
  const { handler } = setup();
  assert.equal((await handler(post(validRequest(), null), ENV)).status, 401);
  assert.equal((await handler(post(validRequest(), "wrong-token-0123456789"), ENV)).status, 401);
  assert.equal((await handler(post(validRequest()), { ...ENV, CLIENT_TOKENS: undefined })).status, 401);
});

test("400: JSON 不正・契約違反 / 413: 大きすぎる本文", async () => {
  const { handler } = setup();
  assert.equal((await handler(post(null, TOKEN, "{oops"), ENV)).status, 400);
  const bad = validRequest() as any;
  bad.session.emotion_memo = "x";
  const res = await handler(post(bad), ENV);
  assert.equal(res.status, 400);
  assert.equal((await res.json() as any).error, "invalid_request");
  assert.equal((await handler(post(null, TOKEN, "x".repeat(17 * 1024)), ENV)).status, 413);
});

test("403: 同意なし（OpenAI を呼ばない）", async () => {
  let called = false;
  const handler = createHandler({ fetchImpl: (async () => { called = true; return new Response("{}"); }) as typeof fetch, log: () => {} });
  const r = validRequest();
  r.consent.external_ai_consented = false;
  const res = await handler(post(r), ENV);
  assert.equal(res.status, 403);
  assert.equal((await res.json() as any).error, "consent_required");
  assert.equal(called, false);
});

test("503: APIキー未設定", async () => {
  const { handler } = setup();
  const res = await handler(post(validRequest()), { ...ENV, OPENAI_API_KEY: undefined });
  assert.equal(res.status, 503);
  assert.equal((await res.json() as any).error, "not_configured");
});

test("504: OpenAI タイムアウト / 502: OpenAI 失敗・不正応答", async () => {
  assert.equal((await setup("timeout").handler(post(validRequest()), ENV)).status, 504);
  assert.equal((await setup("http_500").handler(post(validRequest()), ENV)).status, 502);
  assert.equal((await setup("refusal").handler(post(validRequest()), ENV)).status, 502);
  assert.equal((await setup("prohibited").handler(post(validRequest()), ENV)).status, 502);
});

test("404 / 405", async () => {
  const { handler } = setup();
  assert.equal((await handler(new Request("https://example.test/v1/other"), ENV)).status, 404);
  assert.equal((await handler(new Request("https://example.test/v1/insights"), ENV)).status, 405);
});
