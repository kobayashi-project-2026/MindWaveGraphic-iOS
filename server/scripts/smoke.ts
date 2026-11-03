// smoke.ts
// 起動中のサーバー（dev-server）に対して、もこりんの状況整理（/v1/context-assist）3往復と
// AI 相談（/v1/chat）2往復を実行し、結果・トークン使用量・概算料金を表示する。
//
//   node scripts/smoke.ts --base http://127.0.0.1:8787              # STUB サーバーの確認（無料）
//   node scripts/smoke.ts --base http://127.0.0.1:8787 --allow-real # 実通信（課金あり。承認後のみ）
//
// 安全のための動作:
// - 最初に /v1/health を確認し、実通信モードなら --allow-real がない限り何も送らずに終了する
// - クライアントトークンは環境変数 SMOKE_CLIENT_TOKEN または server/.dev.vars の CLIENT_TOKENS（先頭）から読み、表示しない
// - OpenAI へ届くリクエストは最大 5 件（状況整理 3 + 相談 2）。料金は応答の usage から計算する
// - 心拍・HRV などの計測データは送らない

import { existsSync, readFileSync } from "node:fs";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const option = (name: string, fallback: string) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1]! : fallback;
};

const BASE = option("--base", "http://127.0.0.1:8787").replace(/\/$/, "");
const ALLOW_REAL = flag("--allow-real");
const ALLOW_UNKNOWN = flag("--allow-unknown-mode");
// 公式料金（2026-11-04 確認、gpt-6-luna、100万トークンあたり USD）
const PRICE_INPUT = Number(option("--price-input", "0.10"));
const PRICE_CACHED = Number(option("--price-cached", "0.01"));
const PRICE_OUTPUT = Number(option("--price-output", "0.50"));

function loadToken(): string {
  if (process.env.SMOKE_CLIENT_TOKEN) return process.env.SMOKE_CLIENT_TOKEN;
  const path = new URL("../.dev.vars", import.meta.url);
  if (!existsSync(path)) throw new Error("server/.dev.vars がありません");
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = /^\s*CLIENT_TOKENS\s*=\s*(.*)\s*$/.exec(line);
    if (m && m[1]) return m[1].split(",")[0]!.trim();
  }
  throw new Error("CLIENT_TOKENS が設定されていません");
}

interface Usage { input_tokens: number; output_tokens: number; reasoning_tokens: number; total_tokens: number }
const totals = { input: 0, output: 0, reasoning: 0, calls: 0, failures: 0 };

async function post(path: string, body: unknown, token: string): Promise<{ status: number; json: any; ms: number }> {
  const started = Date.now();
  const res = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  let json: any = null;
  try { json = await res.json(); } catch { /* 本文なし */ }
  return { status: res.status, json, ms: Date.now() - started };
}

function record(label: string, r: { status: number; json: any; ms: number }, summary: string) {
  totals.calls += 1;
  const u: Usage | null = r.json?.usage ?? null;
  if (u) { totals.input += u.input_tokens; totals.output += u.output_tokens; totals.reasoning += u.reasoning_tokens; }
  const ok = r.status === 200;
  if (!ok) totals.failures += 1;
  console.log(`${ok ? "OK " : "NG "} ${label}  status=${r.status}  ${r.ms}ms  provider=${r.json?.provider ?? "-"}  model=${r.json?.model ?? "-"}` +
    (u ? `  tokens(in=${u.input_tokens} out=${u.output_tokens} reasoning=${u.reasoning_tokens})` : "") +
    (ok ? "" : `  error=${r.json?.error ?? "-"}`));
  if (summary) console.log(`     ${summary}`);
}

const uuid = () => crypto.randomUUID().toUpperCase();
const clip = (s: unknown, n = 120) => (typeof s === "string" ? (s.length > n ? `${s.slice(0, n)}…` : s) : "");

async function main() {
  const health = await (await fetch(`${BASE}/v1/health`)).json() as Record<string, unknown>;
  const mode = health.provider_mode as string | undefined;
  console.log(`health: openai_configured=${health.openai_configured} auth_configured=${health.auth_configured} provider_mode=${mode ?? "(不明: 古いサーバー)"}`);
  if (mode === "openai" && !ALLOW_REAL) {
    console.log("中止: サーバーは実通信モードです（OpenAI の利用料が発生します）。承認後に --allow-real を付けて実行してください。");
    process.exit(2);
  }
  if (mode === undefined && !ALLOW_UNKNOWN) {
    console.log("中止: サーバーのモードを確認できません（再起動で最新のコードにするか、STUB と確認済みなら --allow-unknown-mode）。");
    process.exit(2);
  }
  const token = loadToken();

  // 認証の確認（サーバーで拒否されるため OpenAI へは届かない）
  const unauth = await fetch(`${BASE}/v1/chat`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer wrong-token-0000000000" }, body: "{}" });
  console.log(`${unauth.status === 401 ? "OK " : "NG "} 認証: 誤ったトークンは ${unauth.status}（OpenAI へは送られない）`);
  if (unauth.status !== 401) totals.failures += 1;

  // もこりんの状況整理（3往復）
  const conversationId = uuid();
  const messages: Array<{ role: "user" | "assistant"; content: string }> = [{ role: "assistant", content: "こんにちは。今、緊張してる？" }];
  const current: { scene: string | null; conditions: string[]; tension: string | null } = { scene: null, conditions: [], tension: null };
  let step = "tension";
  for (const text of ["かなり緊張してる", "これから就活の面接なんだ", "さっき階段を上ってきた"]) {
    messages.push({ role: "user", content: text });
    const r = await post("/v1/context-assist", { schema_version: 1, request_id: uuid(), conversation_id: conversationId, locale: "ja-JP", step, messages, current }, token);
    const res = r.json?.result;
    record(`context-assist step=${step} 「${text}」`, r,
      res ? `→ scene=${res.scene_candidate} conditions=[${res.condition_candidates}] tension=${res.tension_candidate} clarify=${res.needs_clarification} emotion=${res.emotion} action=${res.action}\n     もこりん: ${clip(res.reply)}` : "");
    if (r.status !== 200 || !res) break;
    messages.push({ role: "assistant", content: res.reply });
    if (res.tension_candidate) current.tension = res.tension_candidate;
    if (res.scene_candidate) current.scene = res.scene_candidate;
    if (res.condition_candidates?.length) current.conditions = res.condition_candidates;
    step = current.scene === null ? "scene" : current.conditions.length === 0 ? "condition" : "review";
  }
  const expectedOk = current.scene === "interview" && current.conditions.includes("stairs");
  console.log(`${expectedOk ? "OK " : "要確認"} 整理結果: scene=${current.scene} conditions=[${current.conditions}] tension=${current.tension}（期待: interview / stairs）`);

  // AI 相談（2往復。2回目は1回目の内容を踏まえているか）
  const chatId = uuid();
  const chat: Array<{ role: "user" | "assistant"; content: string }> = [];
  for (const text of ["面接前で緊張しています", "さっき言っていた呼吸法を詳しく教えて"]) {
    chat.push({ role: "user", content: text });
    const r = await post("/v1/chat", {
      schema_version: 1, request_id: uuid(), conversation_id: chatId, locale: "ja-JP", messages: chat,
      context: { scene: "interview", measurement: null }, consent: { biometric_context_consented: false, consent_version: 1 },
    }, token);
    record(`chat 「${text}」`, r, r.json?.reply ? `もこりん: ${clip(r.json.reply.text, 160)}${r.json.reply.truncated ? "（出力上限で途中終了）" : ""}` : "");
    if (r.status !== 200 || !r.json?.reply) break;
    chat.push({ role: "assistant", content: r.json.reply.text });
  }

  const cost = (totals.input * PRICE_INPUT + totals.output * PRICE_OUTPUT) / 1_000_000;
  console.log(`\n合計: リクエスト ${totals.calls} 件 / 入力 ${totals.input} / 出力 ${totals.output}（うち推論 ${totals.reasoning}）トークン`);
  console.log(`概算料金: $${cost.toFixed(6)}（入力 $${PRICE_INPUT} / 出力 $${PRICE_OUTPUT} per 1M。キャッシュ入力 $${PRICE_CACHED} は未考慮のため上限側の見積もり。STUB では 0）`);
  process.exit(totals.failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(`失敗: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
});
