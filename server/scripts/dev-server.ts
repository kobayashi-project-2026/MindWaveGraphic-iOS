// dev-server.ts
// Worker（src/index.ts）を Node の http サーバーで動かすローカル開発用サーバー（wrangler 不要）。
//
//   node scripts/dev-server.ts                # .dev.vars / 環境変数の OPENAI_API_KEY で実際に OpenAI を呼ぶ
//   node scripts/dev-server.ts --stub-openai  # OpenAI を呼ばずスタブ応答（APIキー不要・課金なし）
//
// PORT（既定 8787）で待ち受ける。iOS シミュレーターからは http://127.0.0.1:8787 で接続できる。

import { createServer } from "node:http";
import { existsSync, readFileSync } from "node:fs";
import { createHandler, type Env } from "../src/index.ts";
import { createStubFetch, type StubMode } from "./stub-openai.ts";

function loadDevVars(): Record<string, string> {
  const path = new URL("../.dev.vars", import.meta.url);
  if (!existsSync(path)) return {};
  const vars: Record<string, string> = {};
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m && m[1] && m[2] !== undefined && !line.trim().startsWith("#")) vars[m[1]] = m[2];
  }
  return vars;
}

const useStub = process.argv.includes("--stub-openai");
const fileVars = loadDevVars();
const env: Env = {
  OPENAI_API_KEY: process.env.OPENAI_API_KEY ?? fileVars.OPENAI_API_KEY,
  OPENAI_MODEL: process.env.OPENAI_MODEL ?? fileVars.OPENAI_MODEL,
  OPENAI_BASE_URL: process.env.OPENAI_BASE_URL ?? fileVars.OPENAI_BASE_URL,
  OPENAI_TIMEOUT_MS: process.env.OPENAI_TIMEOUT_MS ?? fileVars.OPENAI_TIMEOUT_MS,
  CLIENT_TOKENS: process.env.CLIENT_TOKENS ?? fileVars.CLIENT_TOKENS,
  OPENAI_REASONING_EFFORT: process.env.OPENAI_REASONING_EFFORT ?? fileVars.OPENAI_REASONING_EFFORT,
  OPENAI_CHAT_MODEL: process.env.OPENAI_CHAT_MODEL ?? fileVars.OPENAI_CHAT_MODEL,
  CHAT_MAX_OUTPUT_TOKENS: process.env.CHAT_MAX_OUTPUT_TOKENS ?? fileVars.CHAT_MAX_OUTPUT_TOKENS,
  CHAT_MAX_MESSAGES: process.env.CHAT_MAX_MESSAGES ?? fileVars.CHAT_MAX_MESSAGES,
  CHAT_MAX_USER_CHARS: process.env.CHAT_MAX_USER_CHARS ?? fileVars.CHAT_MAX_USER_CHARS,
  CHAT_MAX_TOTAL_CHARS: process.env.CHAT_MAX_TOTAL_CHARS ?? fileVars.CHAT_MAX_TOTAL_CHARS,
  CHAT_ALLOW_MEASUREMENT_CONTEXT: process.env.CHAT_ALLOW_MEASUREMENT_CONTEXT ?? fileVars.CHAT_ALLOW_MEASUREMENT_CONTEXT,
  RATE_LIMIT_PER_MINUTE: process.env.RATE_LIMIT_PER_MINUTE ?? fileVars.RATE_LIMIT_PER_MINUTE,
};

if (useStub) {
  // スタブ時は実キーを使わない（誤って課金リクエストを送らないため）
  env.OPENAI_API_KEY = "stub-key-not-a-real-secret";
  console.warn("[dev-server] STUB MODE: OpenAI へは送信しません（STUB_OPENAI_MODE=%s）", process.env.STUB_OPENAI_MODE ?? "ok");
}
if (!useStub && env.OPENAI_API_KEY) {
  console.warn("[dev-server] REAL MODE: OpenAI API へ実際に送信します（API 利用料が発生します）。モデル=%s", env.OPENAI_CHAT_MODEL || env.OPENAI_MODEL || "gpt-6-luna");
}
if (!env.CLIENT_TOKENS) {
  console.warn("[dev-server] CLIENT_TOKENS が未設定のため /v1/insights は全て 401 になります");
}

const handler = createHandler({
  fetchImpl: useStub ? createStubFetch((process.env.STUB_OPENAI_MODE as StubMode) ?? "ok") : undefined,
  // スタブ時は provider を "openai-stub" にし、アプリ側で「実際のAIではない」と表示させる
  providerName: useStub ? "openai-stub" : "openai",
});

const port = Number(process.env.PORT ?? 8787);
createServer(async (req, res) => {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const body = Buffer.concat(chunks);
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
  const request = new Request(`http://127.0.0.1:${port}${req.url ?? "/"}`, {
    method: req.method,
    headers,
    body: req.method === "GET" || req.method === "HEAD" ? undefined : body,
  });
  const response = await handler(request, env);
  res.writeHead(response.status, Object.fromEntries(response.headers.entries()));
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(port, "127.0.0.1", () => {
  console.log(`[dev-server] listening on http://127.0.0.1:${port} (stub=${useStub})`);
});
