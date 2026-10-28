// stub-openai.ts
// OpenAI Responses API の「ローカル専用」スタブ。APIキーなし・課金なしで通信処理を検証するために使う。
// 本番の Worker（src/index.ts）からは import しない。dev-server の --stub-openai とテストだけが使う。
//
// STUB_OPENAI_MODE で異常系を再現できる: ok（既定）/ timeout / http_500 / http_429 / http_401 / refusal / invalid_json / prohibited
//
// 会話（/v1/chat）の要求には、受け取った履歴の件数・最初の相談・直前の質問を引用した返答を返す。
// これは「履歴が順番どおり届いているか」を確かめるための機械的な返答で、AI が生成した文章ではない。
// 返答の先頭には必ず「（スタブ応答…）」と付け、実際の AI の返答と取り違えないようにしている。

import { FIXED_CAUTION } from "../src/contract.ts";

export type StubMode = "ok" | "timeout" | "http_500" | "http_429" | "http_401" | "refusal" | "invalid_json" | "prohibited";

/** スタブの会話返答の先頭に必ず付ける文言 */
export const STUB_CHAT_PREFIX = "（スタブ応答・実際のAIではありません）";

function clip(s: string, n: number): string {
  const chars = [...s.replace(/\s+/g, " ").trim()];
  return chars.length > n ? `${chars.slice(0, n).join("")}…` : chars.join("");
}

/** 会話の要求か（単発インサイトは json_schema を指定している） */
function isChatRequest(body: Record<string, unknown>): boolean {
  const text = body.text as { format?: { type?: string } } | undefined;
  return text?.format?.type !== "json_schema";
}

/** 受け取った会話履歴から機械的な返答を作る（AI の生成ではない） */
export function stubChatReply(body: Record<string, unknown>): string {
  const input = Array.isArray(body.input) ? (body.input as Array<{ role?: string; content?: unknown }>) : [];
  const users = input.filter((m) => m.role === "user" && typeof m.content === "string").map((m) => m.content as string);
  const assistants = input.filter((m) => m.role === "assistant").length;
  const scene = input.find((m) => m.role === "developer" && typeof m.content === "string")?.content as string | undefined;
  const first = users[0] ?? "";
  const last = users[users.length - 1] ?? "";
  const lines = [
    `${STUB_CHAT_PREFIX}受け取った履歴: 利用者 ${users.length} 件・AI ${assistants} 件。`,
    users.length > 1 ? `最初のご相談「${clip(first, 30)}」の続きとして受け付けました。` : `ご相談「${clip(first, 30)}」を受け付けました。`,
    `直前の質問:「${clip(last, 40)}」`,
  ];
  if (scene) lines.push(`補足情報: ${clip(scene.split("\n")[0] ?? "", 40)}`);
  return lines.join("\n");
}

export interface StubCall {
  url: string;
  authorization: string | null;
  body: Record<string, unknown>;
}

/** スタブが返す固定のインサイト（契約を満たす） */
export const STUB_INSIGHT = {
  title: "呼吸でペースが整いました",
  summary: "ガイドの前後で状態の変化を確認できました。",
  analysis: "今回の呼吸ガイドを最後まで行い、再測定まで完了しました。",
  recommendation: "大事な場面の5分前にも、同じ呼吸を1セット試してみてください。",
  next_action: "次回も再測定まで行い、変化を記録しましょう。",
  caution: FIXED_CAUTION,
  confidence_label: "確からしさ: 中",
  tone: "focus",
};

export function responsesApiBody(outputText: string, model = "stub-model"): Record<string, unknown> {
  return {
    id: "resp_stub",
    object: "response",
    status: "completed",
    model,
    output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text: outputText }] }],
    usage: { input_tokens: 0, output_tokens: 0, output_tokens_details: { reasoning_tokens: 0 }, total_tokens: 0 },
  };
}

/** fetch 互換のスタブを作る。calls に受け取ったリクエストを記録する */
export function createStubFetch(mode: StubMode = "ok", calls: StubCall[] = []): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const headers = new Headers(init?.headers);
    const body = JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>;
    calls.push({ url, authorization: headers.get("Authorization"), body });
    const chat = isChatRequest(body);

    switch (mode) {
      case "timeout":
        // 呼び出し側の AbortController で中断されるまで待つ
        return await new Promise<Response>((_, reject) => {
          init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
        });
      case "http_500":
        return new Response(JSON.stringify({ error: { message: "stub failure", type: "server_error" } }), { status: 500 });
      case "http_429":
        return new Response(JSON.stringify({ error: { message: "stub rate limit", type: "rate_limit_exceeded" } }), { status: 429 });
      case "http_401":
        return new Response(JSON.stringify({ error: { message: "stub invalid key", type: "invalid_request_error" } }), { status: 401 });
      case "refusal":
        return Response.json({
          status: "completed", model: "stub-model",
          output: [{ type: "message", content: [{ type: "refusal", refusal: "I can't help with that." }] }],
        });
      case "invalid_json":
        return chat ? new Response("{not json", { status: 200 }) : Response.json(responsesApiBody("{not json"));
      case "prohibited":
        return Response.json(responsesApiBody(chat
          ? `${STUB_CHAT_PREFIX}あなたは不安障害と診断します。`
          : JSON.stringify({ ...STUB_INSIGHT, analysis: "自律神経が整いました。" })));
      case "ok":
      default:
        return Response.json(responsesApiBody(chat ? stubChatReply(body) : JSON.stringify(STUB_INSIGHT)));
    }
  }) as typeof fetch;
}
