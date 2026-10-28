// stub-openai.ts
// OpenAI Responses API の「ローカル専用」スタブ。APIキーなし・課金なしで通信処理を検証するために使う。
// 本番の Worker（src/index.ts）からは import しない。dev-server の --stub-openai とテストだけが使う。
//
// STUB_OPENAI_MODE で異常系を再現できる: ok（既定）/ timeout / http_500 / http_429 / http_401 / refusal / invalid_json / prohibited / invalid_candidate
//
// もこりんの状況整理（/v1/context-assist）の要求には、最後の発言のキーワードから候補を機械的に作って返す（AI の判断ではない）。
//
// 会話（/v1/chat）の要求には、受け取った履歴の件数・最初の相談・直前の質問を引用した返答を返す。
// これは「履歴が順番どおり届いているか」を確かめるための機械的な返答で、AI が生成した文章ではない。
// 返答の先頭には必ず「（スタブ応答…）」と付け、実際の AI の返答と取り違えないようにしている。

import { FIXED_CAUTION } from "../src/contract.ts";

export type StubMode = "ok" | "timeout" | "http_500" | "http_429" | "http_401" | "refusal" | "invalid_json" | "prohibited" | "invalid_candidate";

/** スタブの会話返答の先頭に必ず付ける文言 */
export const STUB_CHAT_PREFIX = "（スタブ応答・実際のAIではありません）";

function clip(s: string, n: number): string {
  const chars = [...s.replace(/\s+/g, " ").trim()];
  return chars.length > n ? `${chars.slice(0, n).join("")}…` : chars.join("");
}

const STUB_SCENE_WORDS: Array<[string, RegExp]> = [
  ["interview", /面接|面談|発表|プレゼン|スピーチ/], ["sports", /試合|大会|競技|レース/],
  ["important", /大切な|大事な|デート|約束/], ["work", /作業|仕事|勉強|集中/], ["calm", /安静|リラックス|のんびり/],
];
const STUB_CONDITION_WORDS: Array<[string, RegExp]> = [
  ["running", /走/], ["stairs", /階段|移動|歩いて/], ["smoking", /たばこ|タバコ|煙草|喫煙/],
  ["caffeine", /コーヒー|カフェイン|エナジードリンク/], ["sleep_lack", /寝不足|睡眠不足|眠れなかった/],
  ["after_meal", /食後|ご飯を食べ|食べた/], ["none", /特にない|特になし|座って/],
];

/** もこりんの状況整理の要求か */
function isContextRequest(body: Record<string, unknown>): boolean {
  const text = body.text as { format?: { name?: string } } | undefined;
  return text?.format?.name === "mokorin_context";
}

/** 最後の利用者の発言からキーワードで候補を作る（AI の判断ではない） */
export function stubContextResult(body: Record<string, unknown>): Record<string, unknown> {
  const input = Array.isArray(body.input) ? (body.input as Array<{ role?: string; content?: unknown }>) : [];
  const last = [...input].reverse().find((m) => m.role === "user" && typeof m.content === "string")?.content as string ?? "";
  const scene = STUB_SCENE_WORDS.find(([, re]) => re.test(last))?.[0] ?? null;
  let conds = STUB_CONDITION_WORDS.filter(([, re]) => re.test(last)).map(([c]) => c);
  if (conds.includes("none") && conds.length > 1) conds = conds.filter((c) => c !== "none");
  const needs = scene === null && conds.length === 0;
  return {
    reply: `${STUB_CHAT_PREFIX}キーワード判定: 場面=${scene ?? "なし"} / 身体状態=${conds.join(",") || "なし"}`,
    scene_candidate: scene,
    condition_candidates: conds,
    needs_clarification: needs,
    clarification_question: needs ? "（スタブ）どんな場面の前か教えてください" : null,
  };
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
    const context = isContextRequest(body);

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
      case "invalid_candidate":
        return Response.json(responsesApiBody(JSON.stringify({ ...stubContextResult(body), scene_candidate: "office_party" })));
      case "prohibited":
        return Response.json(responsesApiBody(chat
          ? `${STUB_CHAT_PREFIX}あなたは不安障害と診断します。`
          : JSON.stringify({ ...STUB_INSIGHT, analysis: "自律神経が整いました。" })));
      case "ok":
      default:
        if (context) return Response.json(responsesApiBody(JSON.stringify(stubContextResult(body))));
        return Response.json(responsesApiBody(chat ? stubChatReply(body) : JSON.stringify(STUB_INSIGHT)));
    }
  }) as typeof fetch;
}
