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
};

if (useStub) {
  // スタブ時は実キーを使わない（誤って課金リクエストを送らないため）
  env.OPENAI_API_KEY = "stub-key-not-a-real-secret";
  console.warn("[dev-server] STUB MODE: OpenAI へは送信しません（STUB_OPENAI_MODE=%s）", process.env.STUB_OPENAI_MODE ?? "ok");
}
if (!env.CLIENT_TOKENS) {
  console.warn("[dev-server] CLIENT_TOKENS が未設定のため /v1/insights は全て 401 になります");
}

const handler = createHandler({
  fetchImpl: useStub ? createStubFetch((process.env.STUB_OPENAI_MODE as StubMode) ?? "ok") : undefined,
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
