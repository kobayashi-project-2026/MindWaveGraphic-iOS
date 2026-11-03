// smoke.ts
// 起動中のサーバー（dev-server）に対して、もこりんの状況整理（/v1/context-assist）3往復と
// AI 相談（/v1/chat）2往復を実行し、結果・トークン使用量・概算料金を表示する。
//
//   node scripts/smoke.ts --base http://127.0.0.1:8787              # STUB サーバーの確認（無料）
//   node scripts/smoke.ts --base http://127.0.0.1:8787 --allow-real # 実通信（課金あり。承認後のみ）
//
// 少しずつ確認する（実通信の件数を厳密に管理する）:
//   --phase first --state <file>   状況整理の1件目だけを送り、会話の状態を保存する
//   --phase rest  --state <file>   保存した状態から続け、状況整理の残り2件と相談2件を送る
//   --budget-file <file> --budget N  実行をまたいで送信件数を数え、N 件を超えて送らない（送る前に数える）
// どの段階でも、失敗したら以降は送らない（自動で再送しない）
//
// 安全のための動作:
// - 最初に /v1/health を確認し、実通信モードなら --allow-real がない限り何も送らずに終了する
// - クライアントトークンは環境変数 SMOKE_CLIENT_TOKEN または server/.dev.vars の CLIENT_TOKENS（先頭）から読み、表示しない
// - OpenAI へ届くリクエストは最大 5 件（状況整理 3 + 相談 2）。料金は応答の usage から計算する
// - 心拍・HRV などの計測データは送らない

import { existsSync, readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const flag = (name: string) => args.includes(name);
const option = (name: string, fallback: string) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1]! : fallback;
};

const BASE = option("--base", "http://127.0.0.1:8787").replace(/\/$/, "");
const ALLOW_REAL = flag("--allow-real");
const ALLOW_UNKNOWN = flag("--allow-unknown-mode");
const PHASE = option("--phase", "all");            // all | first | rest
const STATE_FILE = option("--state", "");
const BUDGET_FILE = option("--budget-file", "");
const BUDGET = Number(option("--budget", "5"));
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

/** 送信件数の予算。送る前に数え、上限を超える送信はしない（実行をまたいで記録する） */
function consumeBudget(label: string): void {
  if (!BUDGET_FILE) return;
  const used = existsSync(BUDGET_FILE) ? Number(readFileSync(BUDGET_FILE, "utf8").trim() || "0") : 0;
  if (used + 1 > BUDGET) {
    console.log(`中止: 送信件数の上限（${BUDGET} 件）に達するため「${label}」は送りません（使用済み ${used} 件）`);
    process.exit(3);
  }
  writeFileSync(BUDGET_FILE, String(used + 1));
  console.log(`   [送信 ${used + 1}/${BUDGET}] ${label}`);
}

let stopped = false;
function stopIfFailed(r: { status: number }): boolean {
  if (r.status !== 200) {
    stopped = true;
    console.log("   失敗したため、以降のリクエストは送りません（自動で再送しません）");
  }
  return stopped;
}

async function post(path: string, body: unknown, token: string): Promise<{ status: number; json: any; ms: number }> {
  consumeBudget(path);
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

  // もこりんの状況整理（3往復）。--phase first は1件目だけ、--phase rest は保存した状態から続ける
  type ContextState = { conversationId: string; messages: Array<{ role: "user" | "assistant"; content: string }>;
    current: { scene: string | null; conditions: string[]; tension: string | null }; step: string; turn: number };
  let state: ContextState = {
    conversationId: uuid(), messages: [{ role: "assistant", content: "こんにちは。今、緊張してる？" }],
    current: { scene: null, conditions: [], tension: null }, step: "tension", turn: 0,
  };
  if (PHASE === "rest") {
    if (!STATE_FILE || !existsSync(STATE_FILE)) throw new Error("--phase rest には --state の保存ファイルが必要です");
    state = JSON.parse(readFileSync(STATE_FILE, "utf8")) as ContextState;
  }
  const userTurns = ["かなり緊張してる", "これから就活の面接なんだ", "さっき階段を上ってきた"];
  const lastTurn = PHASE === "first" ? 1 : userTurns.length;
  for (let i = state.turn; i < lastTurn && !stopped; i++) {
    const text = userTurns[i]!;
    state.messages.push({ role: "user", content: text });
    const r = await post("/v1/context-assist", { schema_version: 1, request_id: uuid(), conversation_id: state.conversationId,
      locale: "ja-JP", step: state.step, messages: state.messages, current: state.current }, token);
    const res = r.json?.result;
    record(`context-assist step=${state.step} 「${text}」`, r,
      res ? `→ scene=${res.scene_candidate} conditions=[${res.condition_candidates}] tension=${res.tension_candidate} clarify=${res.needs_clarification} q=${res.clarification_question ?? "null"} emotion=${res.emotion} action=${res.action}\n     もこりん: ${res.reply}` : "");
    if (stopIfFailed(r) || !res) break;
    // アプリ（ContextAssistContracts.swift）と同じ規則で値を確認する
    const scenes = ["calm", "interview", "sports", "important", "work", "other"];
    const conds = ["running", "stairs", "smoking", "caffeine", "sleep_lack", "after_meal", "none"];
    const schemaOk = typeof res.reply === "string" && res.reply.length > 0 && res.reply.length <= 160
      && (res.scene_candidate === null || scenes.includes(res.scene_candidate))
      && Array.isArray(res.condition_candidates) && res.condition_candidates.every((c: string) => conds.includes(c))
      && ["calm", "slight", "high", null].includes(res.tension_candidate)
      && ["happy", "calm", "sad", "sleepy"].includes(res.emotion) && ["wave", "jump", "nod"].includes(res.action);
    console.log(`     アプリのスキーマとの一致: ${schemaOk ? "OK" : "NG"}`);
    state.messages.push({ role: "assistant", content: res.reply });
    if (res.tension_candidate) state.current.tension = res.tension_candidate;
    if (res.scene_candidate) state.current.scene = res.scene_candidate;
    if (res.condition_candidates?.length) state.current.conditions = res.condition_candidates;
    state.step = state.current.scene === null ? "scene" : state.current.conditions.length === 0 ? "condition" : "review";
    state.turn = i + 1;
  }
  if (STATE_FILE) writeFileSync(STATE_FILE, JSON.stringify(state));
  if (PHASE !== "first") {
    const expectedOk = state.current.scene === "interview" && state.current.conditions.includes("stairs") && state.current.tension === "high";
    console.log(`${expectedOk ? "OK " : "要確認"} 整理結果: scene=${state.current.scene} conditions=[${state.current.conditions}] tension=${state.current.tension}（期待: interview / stairs / high）`);
  }

  // AI 相談（2往復。2回目は1回目の内容を踏まえているか）
  const chatId = uuid();
  const chat: Array<{ role: "user" | "assistant"; content: string }> = [];
  const chatTurns = ["明日、大事な発表があって緊張しています", "さっき話した発表のことなんだけど、どう準備すればいい？"];
  for (const text of PHASE === "first" ? [] : chatTurns) {
    if (stopped) break;
    chat.push({ role: "user", content: text });
    const r = await post("/v1/chat", {
      schema_version: 1, request_id: uuid(), conversation_id: chatId, locale: "ja-JP", messages: chat,
      context: { scene: null, measurement: null }, consent: { biometric_context_consented: false, consent_version: 1 },
    }, token);
    record(`chat 「${text}」`, r, r.json?.reply ? `もこりん（${[...r.json.reply.text].length}文字）: ${r.json.reply.text}${r.json.reply.truncated ? "（出力上限で途中終了）" : ""}` : "");
    if (stopIfFailed(r) || !r.json?.reply) break;
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
