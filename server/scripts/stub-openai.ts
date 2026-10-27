// stub-openai.ts
// OpenAI Responses API の「ローカル専用」スタブ。APIキーなし・課金なしで通信処理を検証するために使う。
// 本番の Worker（src/index.ts）からは import しない。dev-server の --stub-openai とテストだけが使う。
//
// STUB_OPENAI_MODE で異常系を再現できる: ok（既定）/ timeout / http_500 / refusal / invalid_json / prohibited

import { FIXED_CAUTION } from "../src/contract.ts";

export type StubMode = "ok" | "timeout" | "http_500" | "refusal" | "invalid_json" | "prohibited";

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
  };
}

/** fetch 互換のスタブを作る。calls に受け取ったリクエストを記録する */
export function createStubFetch(mode: StubMode = "ok", calls: StubCall[] = []): typeof fetch {
  return (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    const headers = new Headers(init?.headers);
    calls.push({ url, authorization: headers.get("Authorization"), body: JSON.parse(String(init?.body ?? "{}")) });

    switch (mode) {
      case "timeout":
        // 呼び出し側の AbortController で中断されるまで待つ
        return await new Promise<Response>((_, reject) => {
          init?.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
        });
      case "http_500":
        return new Response(JSON.stringify({ error: { message: "stub failure", type: "server_error" } }), { status: 500 });
      case "refusal":
        return Response.json({
          status: "completed", model: "stub-model",
          output: [{ type: "message", content: [{ type: "refusal", refusal: "I can't help with that." }] }],
        });
      case "invalid_json":
        return Response.json(responsesApiBody("{not json"));
      case "prohibited":
        return Response.json(responsesApiBody(JSON.stringify({ ...STUB_INSIGHT, analysis: "自律神経が整いました。" })));
      case "ok":
      default:
        return Response.json(responsesApiBody(JSON.stringify(STUB_INSIGHT)));
    }
  }) as typeof fetch;
}
