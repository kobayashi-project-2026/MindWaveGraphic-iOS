// テスト共通のリクエスト例（docs/DATA_CONTRACTS.md §10 と同じ）
import type { InsightRequest } from "../src/contract.ts";

export const TOKEN = "test-client-token-0123456789";

export function validRequest(): InsightRequest {
  return {
    schema_version: 1,
    request_id: "6F1C2D3E-4B5A-4C6D-8E7F-9A0B1C2D3E4F",
    locale: "ja-JP",
    consent: { external_ai_consented: true, consent_version: 1 },
    session: {
      scene: "interview",
      exercise: "breathing478",
      duration_seconds: 180,
      completed: true,
      before: { state: "over_tense", score: 72, heart_rate_bpm: 96 },
      after: { state: "optimal_tension", score: 48, heart_rate_bpm: 84 },
      hrv_trend: "up",
      self_report_before: 2,
      self_report_after: 1,
      confidence: 0.8,
    },
  };
}
