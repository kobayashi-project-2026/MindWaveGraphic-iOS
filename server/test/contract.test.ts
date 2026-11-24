import { test } from "node:test";
import assert from "node:assert/strict";
import { INSIGHT_JSON_SCHEMA, validateInsightBody, validateInsightRequest } from "../src/contract.ts";
import { STUB_INSIGHT } from "../scripts/stub-openai.ts";
import { validRequest } from "./fixtures.ts";

test("正しいリクエストは通る（after・心拍の null も可）", () => {
  assert.equal(validateInsightRequest(validRequest()).ok, true);
  const r = validRequest();
  r.session.after = null;
  r.session.before.heart_rate_bpm = null;
  r.session.self_report_after = null;
  assert.equal(validateInsightRequest(r).ok, true);
});

test("未知のキー（メモ・日時など）を含むリクエストは拒否（データ最小化）", () => {
  const r = validRequest() as unknown as Record<string, any>;
  r.session.emotion_memo = "秘密のメモ";
  assert.equal(validateInsightRequest(r).ok, false);
  const r2 = validRequest() as unknown as Record<string, any>;
  r2.session.before.hrv_sdnn_ms = 40;
  assert.equal(validateInsightRequest(r2).ok, false);
  const r3 = validRequest() as unknown as Record<string, any>;
  r3.user_email = "a@example.com";
  assert.equal(validateInsightRequest(r3).ok, false);
});

test("値の範囲・列挙・バージョン", () => {
  const cases: Array<(r: Record<string, any>) => void> = [
    (r) => { r.schema_version = 2; },
    (r) => { r.request_id = "not-a-uuid"; },
    (r) => { r.locale = "en-US"; },
    (r) => { r.session.scene = "moon"; },
    (r) => { r.session.before.score = 101; },
    (r) => { r.session.before.score = 50.5; },
    (r) => { r.session.before.heart_rate_bpm = 300; },
    (r) => { r.session.hrv_trend = "sideways"; },
    (r) => { r.session.self_report_before = 4; },
    (r) => { r.session.confidence = 1.2; },
    (r) => { r.session.duration_seconds = -1; },
  ];
  for (const mutate of cases) {
    const r = validRequest() as unknown as Record<string, any>;
    mutate(r);
    assert.equal(validateInsightRequest(r).ok, false, JSON.stringify(r).slice(0, 80));
  }
});

test("同意 false は形式としては有効（403 はハンドラーで返す）", () => {
  const r = validRequest();
  r.consent.external_ai_consented = false;
  assert.equal(validateInsightRequest(r).ok, true);
});

test("インサイト本文の検証: 正常・空欄・長さ・禁止表現・tone", () => {
  assert.equal(validateInsightBody(STUB_INSIGHT).ok, true);
  assert.equal(validateInsightBody({ ...STUB_INSIGHT, title: " " }).ok, false);
  assert.equal(validateInsightBody({ ...STUB_INSIGHT, title: "あ".repeat(41) }).ok, false);
  assert.equal(validateInsightBody({ ...STUB_INSIGHT, summary: "病気の可能性があります" }).ok, false);
  assert.equal(validateInsightBody({ ...STUB_INSIGHT, tone: "happy" }).ok, false);
  assert.equal(validateInsightBody({ ...STUB_INSIGHT, extra: "x" }).ok, false);
});

test("Structured Outputs strict の要件: 全プロパティ required・additionalProperties false", () => {
  assert.equal(INSIGHT_JSON_SCHEMA.additionalProperties, false);
  assert.deepEqual([...INSIGHT_JSON_SCHEMA.required].sort(), Object.keys(INSIGHT_JSON_SCHEMA.properties).sort());
});

test("Structured Outputs: スキーマは公式の対応キーワードだけを使う（maxLength など非対応のキーワードを含まない）", async () => {
  const { CONTEXT_JSON_SCHEMA } = await import("../src/context.ts");
  const allowed = new Set(["type", "properties", "required", "additionalProperties", "items", "enum", "description",
    "anyOf", "pattern", "format", "minItems", "maxItems", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "$defs", "$ref"]);
  const walk = (node: unknown, path: string): string[] => {
    if (typeof node !== "object" || node === null || Array.isArray(node)) return [];
    const bad: string[] = [];
    for (const [k, v] of Object.entries(node)) {
      if (path.endsWith(".properties")) { bad.push(...walk(v, `${path}.${k}`)); continue; }
      if (!allowed.has(k)) bad.push(`${path}.${k}`);
      if (k === "properties" || k === "items" || k === "$defs") bad.push(...walk(v, `${path}.${k}`));
    }
    return bad;
  };
  assert.deepEqual(walk(INSIGHT_JSON_SCHEMA, "insight"), []);
  assert.deepEqual(walk(CONTEXT_JSON_SCHEMA, "context"), []);
});
