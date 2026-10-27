# Mind Wave Graphic データ契約（JSON 仕様） v1

モジュール間・端末間・サーバー間でやり取りするデータの正式仕様。
実装の正本は `MindWaveGraphic/MindWaveGraphic/Contracts/*.swift`、サーバー側は `server/src/contract.ts`。
**仕様を変えるときは、Swift・TypeScript・このドキュメント・テスト（`Tests/MindWaveCoreTests/ContractTests.swift`、`server/test/`）を同時に更新すること。**

---

## 1. 共通ルール

| 項目 | ルール |
|---|---|
| バージョン | トップレベル文書は `schema_version`（整数）を持つ。現在は `1`。読み込み側は `1 ≤ v ≤ 自分の対応版` のみ受け付け、未来の版は拒否する |
| キー | `snake_case`（Watch 辞書のみ既存互換のため camelCase。§2） |
| 日時 | ISO 8601・UTC・ミリ秒付き（例 `2026-10-28T04:35:12.123Z`）。読み込みはミリ秒なし・UNIX 秒（数値）も受け付ける |
| 単位 | 心拍 `bpm`／HRV は SDNN の `ms`／スコア `0〜100`／確からしさ `0〜1`／時間は秒 |
| 未計測 | 計測値の `null` は「未計測（値が存在しない）」。**0 や平均値で代用しない**。計測値フィールドは null でもキーを省略せず出力する（読み込みはキー欠落も null と同じ扱い） |
| Mock | `is_mock: true` のデータは実測として履歴分析・AI学習・外部送信に使わない。`source` が `mock` のとき、かつそのときに限り `is_mock` は true |
| 診断 | スコアは医学的診断ではない参考値。分析結果の `is_medical_diagnosis` は常に `false` |

### 列挙値

| 型 | 値 |
|---|---|
| `source`（データソース） | `mock` / `watch_live` / `health_kit` / `unavailable` |
| `state`（状態） | `under_aroused`（CALM, 0–32）/ `optimal_tension`（READY, 33–69）/ `over_tense`（ALERT, 70–100）。閾値は `Domain/MindState.swift` が正 |
| `hrv_status` | `measured`（鮮度内の実測）/ `missing`（実測なし）/ `stale`（古いためスコアに不使用）/ `not_applicable`（Mock） |
| `baseline_status` | `personal`（本人の実測から算出）/ `provisional`（実測不足。暫定の参照値で、個人の平常値ではない）/ `not_applicable`（Mock） |
| `scene`（計測コンテキスト） | `calm` / `interview` / `sports` / `important` / `work` / `other` |
| `body_conditions` | `running` / `stairs` / `smoking` / `caffeine` / `sleep_lack` / `after_meal`（「特になし」は空配列） |
| `scene`（ガイド） | `interview` / `study` / `sports` / `social` / `daily` / `other` / `meeting` / `speech` |
| `exercise` | `breathing478` / `box` / `breathing214` |
| `self_report_*` | `0` 落ち着いている / `1` 少し緊張 / `2` かなり緊張 / `3` 強く緊張 / `null` 未入力 |

---

## 2. Watch → iPhone 心拍データ（WatchConnectivity 辞書）

WCSession は plist 辞書を送るため、この契約だけ JSON ではなく辞書。キーは**既存の camelCase を維持**する。

```text
{ "type": "heartRate", "heartRate": 78.0, "timestamp": 1761626112.123, "schemaVersion": 1 }
```

| キー | 型 | 必須 | 説明 |
|---|---|---|---|
| `type` | String | ✓ | 固定値 `"heartRate"` |
| `heartRate` | Double | ✓ | bpm |
| `timestamp` | Double | ✓ | Watch での計測時刻（UNIX 秒） |
| `schemaVersion` | Int | – | v1 で追加。**キーなしは v0（旧 Watch アプリ）として受け付ける** |

- 送信: `WorkoutManager.sendHeartRateToiPhone`（sendMessage → 失敗時 transferUserInfo、＋ updateApplicationContext の3チャネル）
- 受信: `WatchConnectivityManager.handleIncomingMessage` → `WatchHeartRatePayload.decode`
- 重複: 3チャネルで同じパケットが届くため、`MindWaveViewModel.applyWatchHeartRate` が `timestamp` の単調増加で重複・逆順を破棄する
- HRV は Watch から送っていない（HealthKit 経由で iPhone が取得）

---

## 3. 計測サンプル `MeasurementSampleDTO`

```json
{"schema_version":1,"source":"watch_live","is_mock":false,"measured_at":"2026-10-28T04:35:12.123Z",
 "heart_rate_bpm":78,"hrv_sdnn_ms":null,"heart_rate_measured_at":"2026-10-28T04:35:12.123Z",
 "hrv_measured_at":null,"mock_score":null}
```

| キー | 型 | 説明 |
|---|---|---|
| `source` | enum | §1 |
| `is_mock` | Bool | `source == mock` と一致すること |
| `measured_at` | 日時 | サンプルの代表時刻 |
| `heart_rate_bpm` | Double? | 0 < x ≤ 250。null = 未計測 |
| `hrv_sdnn_ms` | Double? | 0 < x ≤ 500。null = 未計測 |
| `heart_rate_measured_at` / `hrv_measured_at` | 日時? | 各サンプル自体の記録時刻 |
| `mock_score` | Double? | Mock のときだけ 0〜100。実測では必ず null |

ドメイン型: `MindWaveSample`（`MeasurementSampleDTO(sample:)` / `.domainSample`）

## 4. 測定コンテキスト `MeasurementContextDTO`

```json
{"scene":"interview","body_conditions":["caffeine"],"total_score_offset":-4.5}
```

`total_score_offset` は参考出力。読み込み時は `scene`・`body_conditions` から再計算する。未知の値は `calm`／特になしに倒す。

## 5. 分析結果 `AnalysisResultDTO`

```json
{"schema_version":1,"analyzer_id":"stress-score-v1","analyzer_version":"1.0",
 "analyzed_at":"2026-10-28T04:35:12.123Z","source":"watch_live","is_mock":false,
 "tension_score":52.4,"confidence":0.5,"state":"optimal_tension",
 "inputs":{"heart_rate_bpm":78,"hrv_sdnn_ms":null,"hrv_status":"missing",
           "baseline_status":"provisional","baseline_heart_rate_bpm":65,"baseline_hrv_sdnn_ms":null},
 "context":{"scene":"calm","body_conditions":[],"total_score_offset":0},
 "is_medical_diagnosis":false}
```

- `analyzer_id` / `analyzer_version` で算出方式を識別する（評価方式を差し替えても結果を区別できる）
- `inputs.baseline_status = provisional` のスコアは「個人の平常値との比較」ではない
- `confidence` の現行規則（変更なし）: Mock はスライダー値／Watch＋HRV 0.75／Watch のみ 0.50／HealthKit＋HRV 0.65／HealthKit のみ 0.40。ベースラインの状態は `baseline_status` で別途示す

## 6. グラフィック入力 `GraphicInputDTO`

```json
{"schema_version":1,"score":52.4,"confidence":0.5,"state":"optimal_tension"}
```

グラフィックチームが受け取るのはこの3項目だけ（Swift では `GraphicInput`）。範囲外の値は読み込み時に clamp する。

## 7. ガイドセッション記録 `GuideSessionRecordDTO`

```json
{"id":"3F2B...","started_at":"2026-10-28T04:30:00.000Z","scene":"interview","exercise":"breathing478",
 "duration_seconds":180,
 "before":{"captured_at":"...","score":72,"confidence":0.75,"state":"over_tense","heart_rate_bpm":96,
           "hrv_sdnn_ms":null,"is_mock":false,"heart_rate_measured_at":"...","hrv_measured_at":null,"source":"watch_live"},
 "after":{...同形式... } または null,
 "hrv_updated":true,"emotion_memo":"少し楽になった","self_report_before":2,"self_report_after":1,
 "ai_insight":{"title":"...","summary":"...","recommendation":"...","engine_version":"local-1.1"} または省略}
```

- スナップショットの `source` は v1 で追加。旧データは null（`is_mock` で Mock 判定は可能）
- `before.is_mock` または `after.is_mock` が true の記録は「Mock を含む記録」として傾向分析から除外する

## 8. 履歴文書 `GuideHistoryDocument`

```json
{"schema_version":1,"saved_at":"2026-10-28T04:40:00.000Z","records":[ GuideSessionRecordDTO, ... ]}
```

保存先（UserDefaults）:

| キー | 形式 | 扱い |
|---|---|---|
| `mindwave.guideHistory.v3.json` | 本文書の JSON（Data） | **正本**。読み込みはこちらを優先 |
| `mindwave.guideHistory.v2` | 旧形式の辞書配列 | 互換用。他メンバーのブランチのビルドでも読めるよう、移行期間中は同時に書き込む。削除しない |

読み込み手順: v3 を decode → 失敗またはキーなしなら v2 を読み、v3 を生成（v2 は残す）。
壊れた1件は読み飛ばし（`skipped` をログ出力）、未知の場面・エクササイズの記録も読み飛ばす（クラッシュしない）。

## 9. 個人ベースライン（参考：保存形式）

UserDefaults `mindwave.personalBaseline.v1`（JSON）。実測（Watch／HealthKit）のみで更新し、Mock は除外する。

```json
{"schema_version":1,"heart_rate_samples":[{"value":64,"measured_at":"..."}],"hrv_samples":[{"value":48.5,"measured_at":"..."}]}
```

- 直近 14 日・最大 500 件を保持
- 個人値とみなす最小件数: 心拍 30 件以上かつ 3 日以上／HRV 5 件以上
- 不足時は既存の参照値（心拍 65 bpm／HRV 45 ms）を使ってスコアを算出するが、`baseline_status = provisional` を付け、画面・JSON で個人値と区別する

---

## 10. AIインサイト API（iOS ⇄ 自前サーバー）

OpenAI API は**サーバーだけ**が呼ぶ。詳細は `docs/OPENAI_SETUP.md`。

### POST `/v1/insights` リクエスト `InsightRequestDTO`

```json
{"schema_version":1,"request_id":"6F1C2D3E-4B5A-4C6D-8E7F-9A0B1C2D3E4F","locale":"ja-JP",
 "consent":{"external_ai_consented":true,"consent_version":1},
 "session":{"scene":"interview","exercise":"breathing478","duration_seconds":180,"completed":true,
            "before":{"state":"over_tense","score":72,"heart_rate_bpm":96},
            "after":{"state":"optimal_tension","score":48,"heart_rate_bpm":84},
            "hrv_trend":"up","self_report_before":2,"self_report_after":1,"confidence":0.8}}
```

**データ最小化**: 送るのはガイド1回分の丸めた要約だけ。メモ本文・日時・HRV 実数値・時系列・端末 ID・氏名・メールは送らない。Mock を含むセッションはクライアントが送信を拒否する。`hrv_trend` は `up` / `down` / `flat` / `unknown`。

ヘッダー: `Authorization: Bearer <クライアントトークン>`、`Content-Type: application/json`

### 200 レスポンス `InsightResponseDTO`

```json
{"schema_version":1,"request_id":"6F1C2D3E-4B5A-4C6D-8E7F-9A0B1C2D3E4F","provider":"openai","model":"gpt-4o-mini",
 "generated_at":"2026-10-28T04:40:00.000Z",
 "insight":{"title":"呼吸でペースが整いました","summary":"ガイド後に心拍が下がりました。",
  "analysis":"面接前の場面で4-7-8呼吸を3分行い、状態が高緊張から中間域へ移りました。",
  "recommendation":"本番の5分前にもう1セット行うと落ち着いて臨めます。","next_action":"次回は再測定まで行い変化を記録しましょう。",
  "caution":"これは医療的な診断ではなく、セルフケアの参考情報です。","confidence_label":"確からしさ: 中","tone":"focus"}}
```

| フィールド | 最大文字数 |
|---|---|
| title | 40 |
| summary | 160 |
| analysis | 300 |
| recommendation | 200 |
| next_action | 120 |
| caution | 160 |
| confidence_label | 40 |

`tone`: `calm` / `focus` / `alert` / `ovld`。
禁止表現（サーバー・クライアント双方で検証）: 診断結果, と診断, 治療, 病気, 疾患, 障害, うつ病, 不安障害, パニック, 処方, 服薬, 副交感神経, 自律神経。
`request_id` はリクエストと一致しなければならない。

### エラーレスポンス `InsightErrorDTO`

```json
{"schema_version":1,"request_id":"... または null","error":"consent_required","message":"..."}
```

| HTTP | error | 意味 | クライアントの動作 |
|---|---|---|---|
| 400 | `invalid_request` | 契約違反 | ローカルAIへフォールバック |
| 401 | `unauthorized` | トークン不正 | 同上 |
| 403 | `consent_required` | 同意なし | 同上（本来クライアントが送らない） |
| 413 | `payload_too_large` | 本文 16KB 超 | 同上 |
| 502 | `upstream_error` / `invalid_upstream_response` | OpenAI 失敗・応答が契約違反 | 同上 |
| 503 | `not_configured` | サーバーに API キー未設定 | 同上 |
| 504 | `upstream_timeout` | OpenAI タイムアウト | 同上 |

---

## 11. テスト

- iOS: `scripts/run_ios_core_tests.sh`（往復変換・null・後方互換・旧履歴の移行・検証規則・本書の例の読み込み）
- サーバー: `cd server && npm test`
