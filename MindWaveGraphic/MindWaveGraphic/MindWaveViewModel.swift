//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

// ─────────────────────────────────────────────────────────
// MindWaveViewModel
// 全データ経路の統括。Watch / HealthKit / Mock いずれも
// ingest(_ sample:) を経由して最新サンプルを保存し、
// selectActiveSample で有効ソースを選んで GraphicInput を更新する。
//
// データソース優先順位:
//   MockモードON                → Mock
//   MockモードOFF + Watch新鮮    → Watch（HRVなし時はHealthKitのHRVを補完）
//   MockモードOFF + Watch古い/なし → HealthKit
//   どちらもなし                 → unavailable
//
// グラフィック層は GraphicInput だけを参照する。
// ─────────────────────────────────────────────────────────
@MainActor
final class MindWaveViewModel: ObservableObject {

    // MARK: - ビルド識別ラベル

    let debugBuildLabel = "source-priority-v1"

    // MARK: - スコア計算の入力値（診断表示用）

    @Published var currentHeartRate: Double = 58
    @Published var averageHeartRate: Double = 65
    @Published var currentHRV: Double       = 52
    @Published var averageHRV: Double       = 45

    // MARK: - データ元・状態表示（診断用）

    @Published var isUsingDemoData: Bool        = true
    @Published var dataSourceLabel: String      = "デモデータで表示中"
    @Published var healthKitStatusLabel: String = "HealthKit：未許可"
    @Published var lastFetchMessage: String     = "まだ取得していません"
    @Published var lastFetchDate: Date?         = nil
    @Published var didFetchHeartRate: Bool      = false
    @Published var didFetchHRV: Bool            = false

    // MARK: - 新規サンプル判定（診断用）

    @Published var latestHeartRateSampleDate: Date? = nil
    @Published var latestHRVSampleDate: Date?       = nil
    @Published var isNewHeartRateSample: Bool       = false
    @Published var isNewHRVSample: Bool             = false
    @Published var sameSampleCount: Int             = 0
    @Published var livePulseTrigger: Int            = 0

    // MARK: - ライブ監視状態（診断用）

    @Published var isLiveMonitoring: Bool           = false
    @Published var liveUpdateInterval: TimeInterval = 5
    @Published var lastLiveUpdateDate: Date?        = nil
    @Published var liveUpdateCount: Int             = 0
    @Published var liveMonitoringMessage: String    = "停止中"

    let healthKitSamplingNote = "Apple Watchの記録・同期タイミングにより、値は数秒ごとに必ず変化するとは限りません。"

    // MARK: - Watch ライブ心拍（診断用）

    @Published var latestWatchHeartRate: Double?      = nil
    @Published var latestWatchHeartRateDate: Date?    = nil
    @Published var watchMessageCount: Int             = 0
    @Published var watchConnectionStatusLabel: String = "未接続"
    @Published var lastWatchMessage: String           = "---"

    // MARK: - グラフィックパイプライン

    /// グラフィックチームへ渡す唯一の入力。reevaluateActiveSource() 経由でのみ更新される。
    @Published var graphicInput: GraphicInput = .neutral
    /// 最新の解析結果（診断用）
    @Published var lastAnalysisResult: MindAnalysisResult? = nil

    // MARK: - データソース仲裁（診断用）

    /// 現在 GraphicInput を生成しているデータソース
    @Published private(set) var activeDataSource: MindDataSource = .mock
    /// GraphicInput が最後に更新された時刻
    @Published private(set) var lastGraphicUpdateDate: Date? = nil

    // MARK: - Mockモード

    @Published var isMockMode: Bool       = true
    @Published var mockScore: Double      = 50
    @Published var mockConfidence: Double = 0.8
    @Published var isMockAutoUpdate: Bool = false

    /// Watch ライブデータの有効期限（秒）。1か所で管理する。
    static let watchLiveExpirySeconds: TimeInterval = 15

    // MARK: - Watch 鮮度 Computed

    /// 最新Watch受信からの経過時間（秒）。未受信の場合 nil。
    var watchSampleAge: TimeInterval? {
        guard let s = latestWatchSample else { return nil }
        return Date().timeIntervalSince(s.timestamp)
    }

    /// 最新Watch受信が watchLiveExpirySeconds 以内かどうか。
    var isWatchSampleFresh: Bool {
        guard let age = watchSampleAge else { return false }
        return age <= Self.watchLiveExpirySeconds
    }

    // MARK: - Computed: スコア計算（診断表示用）

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
    private let hkManager     = HealthKitManager()
    private var liveMonitoringTask:  Task<Void, Never>?
    private var mockAutoUpdateTask:  Task<Void, Never>?
    /// Watch有効期限監視タスク。新しいWatch受信時に前タスクをキャンセルして再生成する。
    private var watchExpiryTask:     Task<Void, Never>?

    private var lastHeartRateSampleIdentifier: String? = nil
    private var lastHRVSampleIdentifier: String?       = nil

    // MARK: - 最新サンプル保持

    private var latestMockSample:      MindWaveSample? = nil
    private var latestWatchSample:     MindWaveSample? = nil
    private var latestHealthKitSample: MindWaveSample? = nil

    // MARK: - Init

    init() {
        loadDemoScenario(index: 0)
        subscribeToWatchHeartRate()
    }

    // MARK: - ▼ ingest: 全データ経路の共通入口 ▼

    /// Watch / HealthKit / Mock いずれのデータもここを通す。
    /// sourceごとに最新サンプルを保存し、selectActiveSample で有効ソースを選んで
    /// GraphicInput を更新する。グラフィックViewからこのメソッドを呼ばないこと。
    func ingest(_ sample: MindWaveSample) {
        switch sample.source {
        case .mock:
            latestMockSample = sample
        case .watchLive:
            latestWatchSample = sample
            scheduleWatchExpiry(at: sample.timestamp)
        case .healthKit:
            latestHealthKitSample = sample
        case .unavailable:
            break
        }
        reevaluateActiveSource(now: Date())
    }

    // MARK: - ▼ selectActiveSample: 有効サンプル選択 ▼

    /// 現時刻 now を基に有効なサンプルを1つ選ぶ。nil = unavailable。
    private func selectActiveSample(now: Date) -> MindWaveSample? {
        if isMockMode {
            return latestMockSample
        }
        if let watch = latestWatchSample,
           now.timeIntervalSince(watch.timestamp) <= Self.watchLiveExpirySeconds {
            // WatchにHRVがなく、HealthKitにHRVがあれば補完（sourceはwatchLiveを維持）
            if watch.hrv == nil, let hkHrv = latestHealthKitSample?.hrv {
                return MindWaveSample(
                    heartRate: watch.heartRate,
                    hrv: hkHrv,
                    contextScore: nil,
                    source: .watchLive,
                    timestamp: watch.timestamp
                )
            }
            return watch
        }
        if let hk = latestHealthKitSample {
            return hk
        }
        return nil
    }

    // MARK: - ▼ reevaluateActiveSource: 仲裁・GraphicInput更新 ▼

    private func reevaluateActiveSource(now: Date) {
        guard let sample = selectActiveSample(now: now) else {
            activeDataSource = .unavailable
            dataSourceLabel  = "データなし"
            isUsingDemoData  = false
            print("[Arbiter] source=unavailable")
            return
        }

        if let hr  = sample.heartRate { currentHeartRate = hr }
        if let hrv = sample.hrv       { currentHRV       = hrv }

        let rawScore: Double
        if let ctx = sample.contextScore {
            rawScore = ctx
        } else {
            rawScore = StressScoreCalculator.calculate(
                currentHeartRate: currentHeartRate,
                averageHeartRate: averageHeartRate,
                currentHRV: currentHRV,
                averageHRV: averageHRV
            ).stressScore
        }
        let tensionScore = min(100, max(0, rawScore))
        let confidence   = min(1,   max(0, computeConfidence(sample: sample)))
        let state        = MindState.from(score: tensionScore)

        #if DEBUG
        assert(tensionScore >= 0 && tensionScore <= 100)
        assert(confidence >= 0 && confidence <= 1)
        #endif

        let analysis = MindAnalysisResult(
            tensionScore: tensionScore,
            confidence: confidence,
            state: state,
            timestamp: sample.timestamp
        )
        lastAnalysisResult    = analysis
        graphicInput          = GraphicInput(
            score:      analysis.tensionScore,
            confidence: analysis.confidence,
            state:      analysis.state
        )
        activeDataSource      = sample.source
        lastGraphicUpdateDate = now

        switch sample.source {
        case .mock:
            dataSourceLabel = "Mockモード"
            isUsingDemoData = true
        case .watchLive:
            dataSourceLabel      = "Watchライブ心拍"
            isUsingDemoData      = false
            didFetchHeartRate    = true
            healthKitStatusLabel = "Watch：ライブ計測中"
        case .healthKit:
            dataSourceLabel      = "HealthKitデータ"
            isUsingDemoData      = false
            healthKitStatusLabel = "HealthKit：接続中"
        case .unavailable:
            break
        }
        print("[Arbiter] source=\(sample.source.rawValue) score=\(String(format: "%.1f", tensionScore))")
    }

    // MARK: - ▼ scheduleWatchExpiry: Watch有効期限の自動再評価 ▼

    private func scheduleWatchExpiry(at sampleTimestamp: Date) {
        watchExpiryTask?.cancel()
        watchExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.watchLiveExpirySeconds))
            } catch { return }
            guard let self else { return }
            // 同じタイムスタンプのWatch受信のみ処理（新しい受信があれば別タスクが担当）
            guard self.latestWatchSample?.timestamp == sampleTimestamp else { return }
            print("[Arbiter] Watch sample expired, re-evaluating")
            self.reevaluateActiveSource(now: Date())
        }
    }

    // MARK: - Mockモード操作

    /// Mockモードのスコアを ingest を通して反映する。
    func sendMockSample() {
        let sample = MindWaveSample(
            heartRate: nil,
            hrv: nil,
            contextScore: mockScore,
            source: .mock,
            timestamp: Date()
        )
        ingest(sample)
    }

    func setMockMode(_ enabled: Bool) {
        isMockMode = enabled
        if enabled {
            sendMockSample()
        } else {
            // Mock OFFへ切替: Watch/HealthKit/unavailableを即時再評価
            reevaluateActiveSource(now: Date())
        }
    }

    func toggleMockAutoUpdate() {
        isMockAutoUpdate ? stopMockAutoUpdate() : startMockAutoUpdate()
    }

    private func startMockAutoUpdate() {
        guard isMockMode else { return }
        isMockAutoUpdate = true
        mockAutoUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                self?.sendMockSample()
            }
        }
    }

    private func stopMockAutoUpdate() {
        mockAutoUpdateTask?.cancel()
        mockAutoUpdateTask = nil
        isMockAutoUpdate   = false
    }

    // MARK: - Watch ライブ心拍 コールバック登録

    private func subscribeToWatchHeartRate() {
        WatchConnectivityManager.shared.onHeartRateReceived = { [weak self] hr, date in
            self?.applyWatchHeartRate(hr, sampleDate: date)
        }
    }

    // MARK: - Watch ライブ心拍 反映

    func applyWatchHeartRate(_ heartRate: Double, sampleDate: Date) {
        // 常に更新：Watch受信診断情報（Mockモードでも記録する）
        latestWatchHeartRate       = heartRate
        latestWatchHeartRateDate   = sampleDate
        watchMessageCount          = WatchConnectivityManager.shared.watchMessageCount
        watchConnectionStatusLabel = WatchConnectivityManager.shared.watchConnectionStatusLabel
        lastWatchMessage           = WatchConnectivityManager.shared.lastWatchMessage

        latestHeartRateSampleDate = sampleDate
        isNewHeartRateSample      = true
        sameSampleCount           = 0
        livePulseTrigger         += 1
        didFetchHeartRate         = true
        lastFetchMessage          = "Watchライブ心拍を受信"
        print("[MindWave] Watch心拍受信: \(String(format: "%.0f", heartRate)) bpm")

        // MockモードON中もWatchサンプルを保存する。
        // selectActiveSample内でMockが優先されるため、GraphicInputはMock値のまま維持される。
        ingest(MindWaveSample(
            heartRate: heartRate,
            hrv: currentHRV > 0 ? currentHRV : nil,
            contextScore: nil,
            source: .watchLive,
            timestamp: sampleDate
        ))
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

        // MockモードON時のみ GraphicInput を更新する。
        // MockモードOFF時はベースライン値の更新のみ行い、GraphicInputはWatch/HealthKitが管理する。
        if isMockMode {
            ingest(MindWaveSample(
                heartRate: s.currentHeartRate,
                hrv: s.currentHRV,
                contextScore: nil,
                source: .mock,
                timestamp: Date()
            ))
        }
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

    // MARK: - HealthKit 単発取得

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
            } catch { break }
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

    // MARK: - Private: HealthKit取得値を反映

    private func applyFetchedValues(
        hrResult: HealthMetricFetchResult,
        avgHR: Double?,
        hrvResult: HealthMetricFetchResult,
        avgHRV: Double?
    ) {
        // ── 心拍サンプルの新旧判定 ──────────────────────────────────
        if hrResult.isSuccess {
            let newId = hrResult.sampleIdentifier
            if let newId, newId == lastHeartRateSampleIdentifier {
                isNewHeartRateSample  = false
                sameSampleCount      += 1
                liveMonitoringMessage = "取得中：HealthKitに新規サンプルなし（\(sameSampleCount)回連続）"
                print("[Live] no new HealthKit sample (same UUID, count: \(sameSampleCount))")
            } else {
                isNewHeartRateSample          = true
                sameSampleCount               = 0
                lastHeartRateSampleIdentifier = newId
                livePulseTrigger             += 1
                liveMonitoringMessage         = "新しい心拍データを取得"
                print("[Live] new HealthKit sample! HR: \(String(format: "%.1f", hrResult.value ?? 0))")
            }
            latestHeartRateSampleDate = hrResult.sampleDate
        } else {
            isNewHeartRateSample  = false
            liveMonitoringMessage = "心拍データ未取得"
        }

        if hrvResult.isSuccess {
            let newHrvId = hrvResult.sampleIdentifier
            if let newHrvId, newHrvId == lastHRVSampleIdentifier {
                isNewHRVSample = false
            } else {
                isNewHRVSample          = true
                lastHRVSampleIdentifier = newHrvId
            }
            latestHRVSampleDate = hrvResult.sampleDate
        } else {
            isNewHRVSample = false
        }

        // ── HealthKit値をingestパイプラインへ ─────────────────────
        if let hr = hrResult.value, let avg = avgHR {
            averageHeartRate = avg
            if let hrv = hrvResult.value, let avgH = avgHRV {
                averageHRV           = avgH
                healthKitStatusLabel = "HealthKit：接続中"
                lastFetchMessage     = "心拍・HRV 取得成功"
                print("[MindWave] HealthKit HR+HRV 取得: \(String(format: "%.1f", hr)) / \(String(format: "%.1f", hrv))")
            } else {
                healthKitStatusLabel = "HealthKit：部分接続"
                lastFetchMessage     = "心拍: 成功 / HRV: \(hrvResult.message)"
            }
            ingest(MindWaveSample(
                heartRate: hr,
                hrv: hrvResult.value,
                contextScore: nil,
                source: .healthKit,
                timestamp: hrResult.sampleDate ?? Date()
            ))
        } else {
            // HealthKit取得失敗 → デモフォールバックなし。Watch or unavailable で継続
            healthKitStatusLabel = "HealthKit：データなし"
            lastFetchMessage     = "心拍未取得: \(hrResult.message)"
            print("[MindWave] HealthKit取得失敗、sourceを再評価")
            reevaluateActiveSource(now: Date())
        }
    }

    // MARK: - Private: confidence 計算

    private func computeConfidence(sample: MindWaveSample) -> Double {
        switch sample.source {
        case .mock:        return mockConfidence
        case .watchLive:   return currentHRV > 0 ? 0.75 : 0.50
        case .healthKit:   return sample.hrv != nil ? 0.65 : 0.40
        case .unavailable: return 0.0
        }
    }
}
