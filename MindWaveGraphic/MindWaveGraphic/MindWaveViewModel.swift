//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

// ─────────────────────────────────────────────────────────
// MindWaveViewModel
// HealthKit実データとデモデータを切り替えながら、
// スコア計算・波形制御・取得状態をすべて管理する。
// UIはこのViewModelのみを参照する。
// ─────────────────────────────────────────────────────────
@MainActor
final class MindWaveViewModel: ObservableObject {

    // MARK: - ビルド識別ラベル（実機で最新ビルドか確認するために使う）
    let debugBuildLabel = "watch-live-hr-v1"

    // MARK: - スコア計算の入力値

    @Published var currentHeartRate: Double = 58
    @Published var averageHeartRate: Double = 65
    @Published var currentHRV: Double       = 52
    @Published var averageHRV: Double       = 45

    // MARK: - データ元・状態表示

    @Published var isUsingDemoData: Bool        = true
    @Published var dataSourceLabel: String      = "デモデータで表示中"
    @Published var healthKitStatusLabel: String = "HealthKit：未許可"
    @Published var lastFetchMessage: String     = "まだ取得していません"
    @Published var lastFetchDate: Date?         = nil
    @Published var didFetchHeartRate: Bool      = false
    @Published var didFetchHRV: Bool            = false

    // MARK: - 新規サンプル判定（サンプルUUIDで比較する）

    /// 最新心拍サンプルの記録時刻（HealthKit内のサンプル自体の時刻）
    @Published var latestHeartRateSampleDate: Date? = nil
    /// 最新HRVサンプルの記録時刻
    @Published var latestHRVSampleDate: Date?       = nil
    /// 前回と比べて新しい心拍サンプルが来たか
    @Published var isNewHeartRateSample: Bool       = false
    /// 前回と比べて新しいHRVサンプルが来たか
    @Published var isNewHRVSample: Bool             = false
    /// 同じサンプルが連続して来た回数（HealthKitに新規データがない証拠）
    @Published var sameSampleCount: Int             = 0
    /// 新規サンプルが来るたびにインクリメントする。LiveWaveViewの波形パルスに使う。
    @Published var livePulseTrigger: Int            = 0

    // MARK: - ライブ監視状態

    @Published var isLiveMonitoring: Bool          = false
    @Published var liveUpdateInterval: TimeInterval = 5
    @Published var lastLiveUpdateDate: Date?        = nil
    @Published var liveUpdateCount: Int             = 0
    @Published var liveMonitoringMessage: String    = "停止中"

    /// HealthKitのサンプリング特性の注意書き（画面に小さく表示する）
    let healthKitSamplingNote = "Apple Watchの記録・同期タイミングにより、値は数秒ごとに必ず変化するとは限りません。"

    // MARK: - Watch ライブ心拍（WatchConnectivity受信）

    /// Watchから受信した最新心拍数（nil = 未受信）
    @Published var latestWatchHeartRate: Double?      = nil
    /// 最新Watch心拍の記録時刻
    @Published var latestWatchHeartRateDate: Date?    = nil
    /// Watch心拍受信回数（増えていれば正常にWatch → iPhoneが通信している）
    @Published var watchMessageCount: Int             = 0
    /// WCSession接続状態ラベル
    @Published var watchConnectionStatusLabel: String = "未接続"
    /// 最後に受信したWatch心拍のサマリー
    @Published var lastWatchMessage: String           = "---"

    // MARK: - Computed: スコア計算

    var stressResult: StressScoreResult {
        StressScoreCalculator.calculate(
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            currentHRV: currentHRV,
            averageHRV: averageHRV
        )
    }

    // MARK: - Private

    private let forceDemoMode = false
    private let hkManager = HealthKitManager()
    private var liveMonitoringTask: Task<Void, Never>?

    // 前回の心拍・HRVサンプルのUUID（新旧判定のために保持する）
    private var lastHeartRateSampleIdentifier: String? = nil
    private var lastHRVSampleIdentifier: String?       = nil

    // MARK: - Init

    init() {
        loadDemoScenario(index: 0)
        // WatchConnectivityManagerのコールバックを設定して、
        // Watch心拍受信時に即時 applyWatchHeartRate を呼び出す。
        subscribeToWatchHeartRate()
    }

    // MARK: - Watch ライブ心拍 コールバック登録

    private func subscribeToWatchHeartRate() {
        // WatchConnectivityManager（シングルトン）のコールバックにViewModelを接続する。
        // Watch側から心拍が届くたびにこのクロージャが MainActor で呼ばれる。
        WatchConnectivityManager.shared.onHeartRateReceived = { [weak self] hr, date in
            self?.applyWatchHeartRate(hr, sampleDate: date)
        }
        // WCSession接続状態の変化を直接バインドする（Combineの代わりに手動同期）
        // ※表示はHomeViewがWatchConnectivityManager.shared.watchConnectionStatusLabelを参照
    }

    // MARK: - Watch ライブ心拍 反映

    /// Apple Watch側から WatchConnectivity 経由で心拍数を受信したときに呼ぶ。
    /// currentHeartRate を即時更新し、波形パルスを発火する。
    /// HealthKit ポーリングより優先される。
    func applyWatchHeartRate(_ heartRate: Double, sampleDate: Date) {
        currentHeartRate          = heartRate
        latestHeartRateSampleDate = sampleDate
        latestWatchHeartRate      = heartRate
        latestWatchHeartRateDate  = sampleDate
        watchMessageCount         = WatchConnectivityManager.shared.watchMessageCount
        watchConnectionStatusLabel = WatchConnectivityManager.shared.watchConnectionStatusLabel
        lastWatchMessage          = WatchConnectivityManager.shared.lastWatchMessage
        isNewHeartRateSample      = true
        sameSampleCount           = 0
        livePulseTrigger         += 1
        didFetchHeartRate         = true
        isUsingDemoData           = false
        dataSourceLabel           = "Watchライブ心拍 / HealthKit HRV"
        lastFetchMessage          = "Watchライブ心拍を受信"
        healthKitStatusLabel      = "Watch：ライブ計測中"
        print("[MindWave] Watch心拍反映: \(String(format: "%.0f", heartRate)) bpm")
    }

    // MARK: - Demo Data

    func loadDemoScenario(index: Int) {
        guard index < MindSampleScenario.allScenarios.count else { return }
        let s = MindSampleScenario.allScenarios[index]
        currentHeartRate = s.currentHeartRate
        averageHeartRate = s.averageHeartRate
        currentHRV       = s.currentHRV
        averageHRV       = s.averageHRV
        isUsingDemoData  = true
        dataSourceLabel  = "デモデータで表示中"
    }

    // MARK: - HealthKit Authorization

    func requestHealthKitAuthorization() async {
        guard HealthKitManager.isAvailable else {
            healthKitStatusLabel = "HealthKit：このデバイスでは利用不可"
            return
        }
        do {
            try await hkManager.requestAuthorization()
            print("[MindWave] HealthKit authorization requested")
            healthKitStatusLabel = "HealthKit：許可済み"
            if !forceDemoMode { await fetchHealthKitData() }
        } catch {
            healthKitStatusLabel = "HealthKit：許可リクエスト失敗"
            print("[MindWave] authorization error: \(error)")
        }
    }

    // MARK: - HealthKit 単発取得（1回だけ）

    func fetchHealthKitData() async {
        guard HealthKitManager.isAvailable, !forceDemoMode else { return }

        let hrResult  = await hkManager.fetchBestCurrentHeartRate()
        let avgHR     = await hkManager.fetchAverageHeartRate(days: 7)
        let hrvResult = await hkManager.fetchBestCurrentHRV()
        let avgHRV    = await hkManager.fetchAverageHRV(days: 7)

        didFetchHeartRate = hrResult.isSuccess
        didFetchHRV       = hrvResult.isSuccess
        lastFetchDate     = Date()

        applyFetchedValues(hrResult: hrResult, avgHR: avgHR,
                           hrvResult: hrvResult, avgHRV: avgHRV)
    }

    // MARK: - ライブ監視 開始 / 停止 / トグル

    /// HealthKitを5秒ごとに再取得するライブ監視を開始する。
    /// 二重起動を防ぐ。タブを移動しても停止しない（明示的に停止が必要）。
    func startLiveMonitoring() {
        guard !isLiveMonitoring else { return }
        guard HealthKitManager.isAvailable else {
            liveMonitoringMessage = "HealthKit利用不可"
            return
        }
        isLiveMonitoring      = true
        liveUpdateCount       = 0
        sameSampleCount       = 0
        liveMonitoringMessage = "ライブ取得中"
        print("[Live] start monitoring (interval: \(Int(liveUpdateInterval))s)")

        liveMonitoringTask = Task { [weak self] in
            await self?.runLiveMonitoringLoop()
        }
    }

    func stopLiveMonitoring() {
        liveMonitoringTask?.cancel()
        liveMonitoringTask    = nil
        isLiveMonitoring      = false
        liveMonitoringMessage = "停止しました"
        print("[Live] stop monitoring")
    }

    func toggleLiveMonitoring() {
        isLiveMonitoring ? stopLiveMonitoring() : startLiveMonitoring()
    }

    // MARK: - Private: ライブ監視ループ

    private func runLiveMonitoringLoop() async {
        while !Task.isCancelled {
            liveUpdateCount += 1
            print("[Live] fetch tick \(liveUpdateCount)")

            await fetchLiveData()
            lastLiveUpdateDate = Date()

            do {
                try await Task.sleep(for: .seconds(liveUpdateInterval))
            } catch {
                break  // CancellationErrorでループ終了
            }
        }
    }

    private func fetchLiveData() async {
        guard !forceDemoMode else { return }

        let hrResult  = await hkManager.fetchBestCurrentHeartRate()
        let avgHR     = await hkManager.fetchAverageHeartRate(days: 7)
        let hrvResult = await hkManager.fetchBestCurrentHRV()
        let avgHRV    = await hkManager.fetchAverageHRV(days: 7)

        didFetchHeartRate = hrResult.isSuccess
        didFetchHRV       = hrvResult.isSuccess
        lastFetchDate     = Date()

        applyFetchedValues(hrResult: hrResult, avgHR: avgHR,
                           hrvResult: hrvResult, avgHRV: avgHRV)
    }

    // MARK: - Private: 取得値をViewModelに反映する共通処理

    private func applyFetchedValues(
        hrResult: HealthMetricFetchResult,
        avgHR: Double?,
        hrvResult: HealthMetricFetchResult,
        avgHRV: Double?
    ) {
        // ── 心拍サンプルの新旧判定 ──────────────────────────────────
        // UUID（sampleIdentifier）を比較して「前回と同じサンプルか」を判定する。
        // UUIDがない（平均値の場合）は値で比較する。
        if hrResult.isSuccess {
            let newId = hrResult.sampleIdentifier
            if let newId, newId == lastHeartRateSampleIdentifier {
                // 同じUUID = 同じサンプルを再読み → HealthKitに新規サンプルなし
                isNewHeartRateSample  = false
                sameSampleCount      += 1
                liveMonitoringMessage = "取得中：HealthKitに新規サンプルなし（\(sameSampleCount)回連続）"
                print("[Live] no new HealthKit sample (same UUID, count: \(sameSampleCount))")
            } else {
                // 新しいUUID または 初回 = 新規サンプル到着
                isNewHeartRateSample         = true
                sameSampleCount              = 0
                lastHeartRateSampleIdentifier = newId
                livePulseTrigger            += 1  // 波形パルスを発火する
                liveMonitoringMessage         = "新しい心拍データを取得"
                print("[Live] new HealthKit sample! HR: \(String(format: "%.1f", hrResult.value ?? 0))")
            }
            latestHeartRateSampleDate = hrResult.sampleDate
        } else {
            isNewHeartRateSample  = false
            liveMonitoringMessage = "心拍データ未取得"
        }

        // ── HRVサンプルの新旧判定 ────────────────────────────────────
        if hrvResult.isSuccess {
            let newHrvId = hrvResult.sampleIdentifier
            if let newHrvId, newHrvId == lastHRVSampleIdentifier {
                isNewHRVSample = false
            } else {
                isNewHRVSample       = true
                lastHRVSampleIdentifier = newHrvId
            }
            latestHRVSampleDate = hrvResult.sampleDate
        } else {
            isNewHRVSample = false
        }

        // ── 値をViewModelに反映する ──────────────────────────────────
        if let hr = hrResult.value, let avg = avgHR {
            currentHeartRate = hr
            averageHeartRate = avg

            if let hrv = hrvResult.value, let avgH = avgHRV {
                // 心拍・HRV 両方取得 → 完全HealthKitモード
                currentHRV           = hrv
                averageHRV           = avgH
                isUsingDemoData      = false
                dataSourceLabel      = "HealthKitデータで表示中"
                healthKitStatusLabel = "HealthKit：接続中"
                lastFetchMessage     = "心拍・HRV 取得成功"
                let score = stressResult.stressScore
                print("[MindWave] score updated: \(String(format: "%.1f", score))")
            } else {
                // 心拍のみ → 部分接続モード
                isUsingDemoData      = false
                dataSourceLabel      = "心拍：HealthKit / HRV：デモ"
                healthKitStatusLabel = "HealthKit：部分接続"
                lastFetchMessage     = "心拍: 成功 / HRV: \(hrvResult.message)"
            }
        } else {
            // 心拍取得失敗 → デモフォールバック
            // HealthKitの心拍は Apple Watch → iPhone 同期が必要。
            // 未装着・未同期の場合は取得できないためデモデータで継続する。
            loadDemoScenario(index: 0)
            healthKitStatusLabel = "HealthKit：データなし"
            lastFetchMessage     = "心拍未取得: \(hrResult.message)"
            print("[MindWave] Fallback to demo data: \(hrResult.message)")
        }
    }
}
