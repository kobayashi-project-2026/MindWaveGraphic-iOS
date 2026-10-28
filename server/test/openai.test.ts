import { test } from "node:test";
import assert from "node:assert/strict";
import { FIXED_CAUTION } from "../src/contract.ts";
import { buildResponsesRequest, generateInsight, UpstreamError, type OpenAIConfig } from "../src/openai.ts";
import { createStubFetch, STUB_INSIGHT, type StubCall, type StubMode } from "../scripts/stub-openai.ts";
import { validRequest } from "./fixtures.ts";

function cfg(mode: StubMode, calls: StubCall[] = [], timeoutMs = 2000): OpenAIConfig {
  return { apiKey: "sk-test-not-real", model: "test-model", baseUrl: "https://api.openai.com/v1/", timeoutMs, fetchImpl: createStubFetch(mode, calls) };
}

test("Responses API の要求形式: strict JSON Schema・store=false・本文に APIキーなし", () => {
  const body = buildResponsesRequest(validRequest(), "test-model");
  assert.equal(body.model, "test-model");
  assert.equal(body.store, false);
  const format = (body.text as any).format;
  assert.equal(format.type, "json_schema");
  assert.equal(format.strict, true);
  assert.equal(format.name, "mindwave_insight");
  const serialized = JSON.stringify(body);
  assert.ok(!serialized.includes("sk-"), "API key must not be in body");
  assert.ok(!serialized.includes("6F1C2D3E"), "request_id is not sent to OpenAI");
});

test("正常応答: URL・認証ヘッダー・検証済みインサイト・免責文は固定", async () => {
  const calls: StubCall[] = [];
  const result = await generateInsight(validRequest(), cfg("ok", calls));
  assert.equal(calls.length, 1);
  assert.equal(calls[0]?.url, "https://api.openai.com/v1/responses");
  assert.equal(calls[0]?.authorization, "Bearer sk-test-not-real");
  assert.equal(result.insight.title, STUB_INSIGHT.title);
  assert.equal(result.insight.caution, FIXED_CAUTION);
  assert.equal(result.model, "stub-model");
});

async function expectCode(mode: StubMode, code: string, timeoutMs = 2000) {
  await assert.rejects(generateInsight(validRequest(), cfg(mode, [], timeoutMs)), (e: unknown) => {
    assert.ok(e instanceof UpstreamError);
    assert.equal(e.code, code);
    return true;
  });
}

test("タイムアウト → upstream_timeout", async () => { await expectCode("timeout", "upstream_timeout", 50); });
test("HTTP 500 → upstream_error", async () => { await expectCode("http_500", "upstream_error"); });
test("拒否（refusal）→ upstream_refusal", async () => { await expectCode("refusal", "upstream_refusal"); });
test("JSON でない出力 → invalid_upstream_response", async () => { await expectCode("invalid_json", "invalid_upstream_response"); });
test("禁止表現を含む出力 → invalid_upstream_response", async () => { await expectCode("prohibited", "invalid_upstream_response"); });

test("本文の受信が止まった場合もタイムアウト → upstream_timeout", async () => {
  // ヘッダー（200）は即座に返し、本文のストリームを閉じないまま止める
  const stalledFetch: typeof fetch = async (_input, init) => {
    const signal = (init as RequestInit | undefined)?.signal ?? undefined;
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("{\"output\":"));
        signal?.addEventListener("abort", () => controller.error(new DOMException("aborted", "AbortError")));
      },
    });
    return new Response(body, { status: 200, headers: { "Content-Type": "application/json" } });
  };
  const config: OpenAIConfig = { ...cfg("ok"), timeoutMs: 50, fetchImpl: stalledFetch };
  await assert.rejects(generateInsight(validRequest(), config), (e: unknown) => {
    assert.ok(e instanceof UpstreamError);
    assert.equal(e.code, "upstream_timeout");
    return true;
  });
});
