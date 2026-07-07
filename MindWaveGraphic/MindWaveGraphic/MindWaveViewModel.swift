//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

// ─────────────────────────────────────────────────────────
// HRVUpdateSource
// HRV状態更新の経路を識別するenum。診断カウンターと経路ログに使用。
// ─────────────────────────────────────────────────────────
enum HRVUpdateSource: String {
    case none              = "---"
    case initialFetch      = "初回取得"
    case periodicFetch     = "定期取得"
    case anchoredInitial   = "Anchored初回"
    case anchoredUpdate    = "Anchored更新"
    case diagnostic        = "診断クエリ"
    case aggregateFallback = "集計フォールバック"
}

// ─────────────────────────────────────────────────────────
// MindWaveViewModel
// Watch / HealthKit / Mock の3ソースを統括する ViewModel。
// いずれも ingest(_ sample:) を経由して最新サンプルを保存し、
// selectActiveSample で有効ソースを1つ選択する。
// StressScoreCalculator で tensionScore を算出して
// MindAnalysisResult → GraphicInput へ変換する。
//
// データソース優先順位:
//   Mock ON                     → Mock
//   Mock OFF + Watch 15秒以内   → Watch（HRVなし時はHealthKitで補完）
//   Mock OFF + Watch 古い/なし  → HealthKit
//   いずれもなし                → unavailable → GraphicInput.neutral
//
// グラフィック層は GraphicInput だけを受け取る。
// HealthKit・WatchConnectivity の型は一切参照しない。
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

    /// 測定コンテキスト。AppFlowStateから設定され、StressScoreCalculatorへ渡される。
    @Published var measurementContext: MeasurementContext = .default

    // MARK: - 新規サンプル判定（診断用）

    @Published var latestHeartRateSampleDate: Date? = nil
    @Published var latestHRVSampleDate: Date?       = nil
    @Published var isNewHeartRateSample: Bool       = false
    @Published var isNewHRVSample: Bool             = false
    @Published var sameSampleCount: Int             = 0
    @Published var livePulseTrigger: Int            = 0

    // MARK: - HRV 状態（診断用）

    @Published private(set) var isHRVObserverActive: Bool = false

    // ── 表示状態 ──
    @Published private(set) var lastHRVUpdateSource: HRVUpdateSource = .none
    @Published private(set) var lastHRVDisplayUpdateDate: Date? = nil
    @Published private(set) var hrvDisplayUpdateCount: Int = 0

    // ── 通常取得採用数（updateHRVState通過） ──
    @Published private(set) var hrvInitialFetchAcceptedCount: Int  = 0
    @Published private(set) var hrvPeriodicFetchAcceptedCount: Int = 0

    // ── Anchored Query callback（呼ばれた回数・時刻） ──
    @Published private(set) var hrvAnchoredInitialCallbackCount: Int      = 0
    @Published private(set) var hrvAnchoredUpdateCallbackCount: Int       = 0
    @Published private(set) var lastHRVAnchoredInitialCallbackDate: Date? = nil
    @Published private(set) var lastHRVAnchoredUpdateCallbackDate: Date?  = nil
    @Published private(set) var lastHRVAnchoredRawSampleCount: Int        = 0
    /// 直近callbackでHealthKitManager.acceptSampleを通過した件数（表示採用とは別）
    @Published private(set) var lastHRVAnchoredHKMAcceptedCount: Int      = 0
    /// 現在のQueryエラー（正常callbackで nil にリセット）
    @Published private(set) var lastHRVQueryError: String?                = nil

    // ── Anchored Query 表示採用数（updateHRVState通過・画面状態を更新した件数） ──
    @Published private(set) var hrvAnchoredInitialAcceptedCount: Int = 0
    @Published private(set) var hrvAnchoredUpdateAcceptedCount: Int  = 0

    // ── 除外数（HKMレベル・VMレベルを分離） ──
    /// HealthKitManager内でacceptSampleが除外した重複数（Anchoredのみ）
    @Published private(set) var hrvHKMDuplicateCount: Int = 0
    /// HealthKitManager内でacceptSampleが除外した古値数（Anchoredのみ）
    @Published private(set) var hrvHKMStaleCount: Int     = 0
    /// ViewModel内updateHRVStateがUUID重複で除外した数（全経路）
    @Published private(set) var hrvVMDuplicateCount: Int  = 0
    /// ViewModel内updateHRVStateが古値・同時刻で除外した数（全経路）
    @Published private(set) var hrvVMStaleCount: Int      = 0

    // ── 集計フォールバック ──
    /// 実サンプルなしで集計値を表示した回数（採用カウンターに含まない）
    @Published private(set) var fallbackAggregateHRVDisplayCount: Int = 0

    /// GraphicInputを最後に更新したデータ経路（"heartRate" / "hrv" / "healthKit" / "mock"）
    @Published private(set) var lastGraphicUpdateTrigger: String = "---"

    // MARK: - HRV 詳細情報（診断用）

    /// 最新HRVサンプルのSource名（例："Apple Watch"）
    @Published private(set) var latestHRVSourceName: String? = nil
    /// 最新HRVサンプルの終了時刻
    @Published private(set) var latestHRVEndDate: Date? = nil
    /// 最新HRVサンプルのBundle Identifier
    @Published private(set) var latestHRVBundleID: String? = nil
    /// 初回HRV Queryの状態（"未実行" / "クエリ中" / "0件" / "成功" / "エラー"）
    @Published private(set) var hrvInitialQueryStatus: String = "未実行"
    /// 診断Query結果（DebugDiagnosticsView専用）
    @Published private(set) var hrvDiagnosticSamples: [HRVDiagnosticSample] = []
    @Published private(set) var hrvDiagnosticError: String? = nil

    // MARK: - ライブ監視状態（診断用）

    @Published var isLiveMonitoring: Bool           = false
    @Published var liveUpdateInterval: TimeInterval = 5
    @Published var lastLiveUpdateDate: Date?        = nil
    @Published var liveUpdateCount: Int             = 0
    @Published var liveMonitoringMessage: String    = "停止中"

    let healthKitSamplingNote = "Apple Watchの記録・同期タイミングにより、値は数秒ごとに必ず変化するとは限りません。"

    // MARK: - Watch ライブ心拍（診断用）

    @Published var latestWatchHeartRate: Double?      = nil
    /// Watch から最後に心拍を受信した日時。診断表示用。
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

    /// 現在 GraphicInput を生成しているデータソース。
    @Published private(set) var activeDataSource: MindDataSource = .mock
    /// GraphicInput が最後に更新された時刻。
    @Published private(set) var lastGraphicUpdateDate: Date? = nil

    // MARK: - Mockモード

    /// true のとき selectActiveSample は常に Mock を優先する。
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
    private var hrvObserverStarted                     = false
    /// 実HRVサンプル（discreteSample）をいずれかの経路で一度でも採用済みか。
    /// .initialFetch / .periodicFetch の分類基準。全実サンプル経路で true にする。
    private var hasAcceptedAnyDiscreteHRVSample = false
    /// WatchConnectivity 3チャネル重複・古いパケットを弾くためのタイムスタンプ管理。
    private var lastAppliedWatchTimestamp: TimeInterval = 0

    // MARK: - 最新サンプル保持

    /// ingest を通じて保存された最新の Mock サンプル。
    private var latestMockSample:      MindWaveSample? = nil
    /// ingest を通じて保存された最新の Watch サンプル。Mock ON 中でも更新される。
    private var latestWatchSample:     MindWaveSample? = nil
    /// ingest を通じて保存された最新の HealthKit サンプル。現時点では期限切れ判定なし。
    private var latestHealthKitSample: MindWaveSample? = nil

    // MARK: - Init

    /// ViewModelを初期化する。シナリオ0のデモデータをロードし、Watch心拍コールバックを登録する。
    /// Mock ON 状態からスタートし、最初のデモサンプルを ingest する。
    init() {
        loadDemoScenario(index: 0)
        subscribeToWatchHeartRate()
        MindWaveDebugLogger.log(.lifecycle, "MindWaveViewModel initialized")
    }

    // MARK: - ▼ ingest: 全データ経路の共通入口 ▼

    /// Watch / HealthKit / Mock いずれのデータもここを通す。
    /// sourceごとに最新サンプルを保存し、reevaluateActiveSource で GraphicInput を更新する。
    /// グラフィックViewからこのメソッドを呼ばないこと。
    func ingest(_ sample: MindWaveSample) {
        MindWaveDebugLogger.log(.pipeline, "sample received source=\(sample.source.rawValue) hr=\(sample.heartRate.map { String(format: "%.0f", $0) } ?? "nil") hrv=\(sample.hrv != nil ? "present" : "nil") context=\(sample.contextScore.map { String(format: "%.1f", $0) } ?? "nil")")
        switch sample.source {
        case .mock:
            latestMockSample = sample
            MindWaveDebugLogger.log(.pipeline, "latest Mock sample stored")
        case .watchLive:
            latestWatchSample = sample
            scheduleWatchExpiry(at: sample.timestamp)
            MindWaveDebugLogger.log(.pipeline, "latest Watch sample stored")
        case .healthKit:
            latestHealthKitSample = sample
            MindWaveDebugLogger.log(.pipeline, "latest HealthKit sample stored")
        case .unavailable:
            break
        }
        reevaluateActiveSource(now: Date())
    }

    // MARK: - ▼ selectActiveSample: 有効サンプル選択 ▼

    /// 現時刻 now を基に有効なサンプルを1つ選ぶ。nil = unavailable。
    /// Mock ON なら問答無用で latestMockSample を返す。
    /// Watch が watchLiveExpirySeconds 以内なら Watch を返す（HRV補完あり）。
    /// それ以外は latestHealthKitSample、なければ nil。
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

    /// selectActiveSample の結果を元に GraphicInput を更新する。
    /// サンプルなし → GraphicInput.neutral にリセット。
    /// サンプルあり → StressScoreCalculator で解析し、activeDataSource と graphicInput を更新する。
    /// ingest と scheduleWatchExpiry の Task からのみ呼ばれる。
    private func reevaluateActiveSource(now: Date) {
        guard let sample = selectActiveSample(now: now) else {
            activeDataSource      = .unavailable
            graphicInput          = .neutral
            lastAnalysisResult    = nil
            lastGraphicUpdateDate = now
            dataSourceLabel       = "データなし"
            isUsingDemoData       = false
            MindWaveDebugLogger.log(.source, "no active sample; GraphicInput reset to neutral")
            return
        }

        if let hr  = sample.heartRate { currentHeartRate = hr }
        if let hrv = sample.hrv       { currentHRV       = hrv }

        let rawScore: Double
        if let ctx = sample.contextScore {
            // Mock: contextScore を直接使用（デモ値として明示）
            rawScore = ctx
        } else {
            // 非Mock: sample.hrv が nil の場合は実測HRVなし。
            // avgHRV=0 を渡すと StressScoreCalculator の guard averageHRV > 0 が失敗し
            // stressScore=50（中立）が返る。架空の currentHRV を使用しない。
            rawScore = StressScoreCalculator.calculate(
                currentHeartRate: currentHeartRate,
                averageHeartRate: averageHeartRate,
                currentHRV:    sample.hrv ?? 0.0,
                averageHRV:    sample.hrv != nil ? averageHRV : 0.0,
                context:       measurementContext
            ).stressScore
        }
        let tensionScore = min(100, max(0, rawScore))
        let confidence   = min(1,   max(0, computeConfidence(sample: sample)))
        MindWaveDebugLogger.log(.pipeline,
            "rebuild trigger=\(lastGraphicUpdateTrigger) " +
            "hr=\(sample.heartRate.map { String(format: "%.0f", $0) } ?? "nil") " +
            "hrv=\(sample.hrv.map { String(format: "%.0f", $0) } ?? "nil") " +
            "score=\(String(format: "%.1f", tensionScore))")
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
        let previousSource    = activeDataSource
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

        if sample.source != previousSource {
            MindWaveDebugLogger.log(.source, "active source changed \(previousSource.rawValue) -> \(sample.source.rawValue)")
        }
        MindWaveDebugLogger.log(.analysis, "score=\(String(format: "%.1f", tensionScore)) confidence=\(String(format: "%.2f", confidence)) state=\(state.rawValue)")
        MindWaveDebugLogger.log(.graphic, "[Pipeline] graphic input updated source=\(sample.source.rawValue) trigger=\(lastGraphicUpdateTrigger) score=\(String(format: "%.1f", tensionScore)) confidence=\(String(format: "%.2f", confidence)) state=\(state.rawValue)")
    }

    // MARK: - ▼ scheduleWatchExpiry: Watch有効期限の自動再評価 ▼

    /// Watch受信から watchLiveExpirySeconds 秒後に reevaluateActiveSource を呼ぶ Task を作る。
    /// 新しいWatch受信があれば古いタスクをキャンセルして再生成する（タイムスタンプ一致で制御）。
    private func scheduleWatchExpiry(at sampleTimestamp: Date) {
        watchExpiryTask?.cancel()
        MindWaveDebugLogger.log(.watch, "expiry task scheduled (previous cancelled if any)")
        watchExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.watchLiveExpirySeconds))
            } catch { return }
            guard let self else { return }
            // 同じタイムスタンプのWatch受信のみ処理（新しい受信があれば別タスクが担当）
            guard self.latestWatchSample?.timestamp == sampleTimestamp else {
                MindWaveDebugLogger.log(.watch, "expiry task skipped: newer sample received")
                return
            }
            MindWaveDebugLogger.log(.watch, "sample expired after \(Int(Self.watchLiveExpirySeconds))s, re-evaluating source")
            self.reevaluateActiveSource(now: Date())
        }
    }

    // MARK: - Mockモード操作

    /// Mock スコアを ingest を通して反映する。Mock ON 時のみ GraphicInput に反映される。
    func sendMockSample() {
        lastGraphicUpdateTrigger = "mock"
        MindWaveDebugLogger.log(.mock, "sample sent score=\(String(format: "%.1f", mockScore))")
        let sample = MindWaveSample(
            heartRate: nil,
            hrv: nil,
            contextScore: mockScore,
            source: .mock,
            timestamp: Date()
        )
        ingest(sample)
    }

    /// Mock モードを切り替える。ON → sendMockSample で即時反映、OFF → 他ソースを再評価。
    func setMockMode(_ enabled: Bool) {
        isMockMode = enabled
        MindWaveDebugLogger.log(.mock, enabled ? "mode ON" : "mode OFF")
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

    /// 5秒ごとに sendMockSample を呼ぶ自動更新 Task を起動する。Mock ON 時のみ有効。
    private func startMockAutoUpdate() {
        guard isMockMode else { return }
        isMockAutoUpdate = true
        MindWaveDebugLogger.log(.mock, "auto-update started interval=5s")
        mockAutoUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                self?.sendMockSample()
            }
        }
    }

    /// Mock 自動更新 Task をキャンセルして停止する。
    private func stopMockAutoUpdate() {
        mockAutoUpdateTask?.cancel()
        mockAutoUpdateTask = nil
        isMockAutoUpdate   = false
        MindWaveDebugLogger.log(.mock, "auto-update stopped")
    }

    // MARK: - HealthKit HRV Observer

    /// HealthKit HRV observer を開始する。
    /// requestHealthKitAuthorization の完了後に1回だけ呼ぶ。
    /// 初回の fetchHealthKitData で lastHRVSampleIdentifier が設定された後に開始することで
    /// 既存サンプルの重複処理を防ぐ。
    private func startHRVObserver() {
        guard !hrvObserverStarted else { return }
        guard HealthKitManager.isAvailable else {
            MindWaveDebugLogger.log(.healthKit, "HRV observer: HealthKit not available, skipping")
            return
        }
        hrvObserverStarted  = true
        isHRVObserverActive = true
        hkManager.startHRVObserver { [weak self] batch in
            Task { @MainActor [weak self] in
                self?.applyHRVObserverBatch(batch)
            }
        }
        MindWaveDebugLogger.log(.healthKit, "HRV observer registered")
    }

    // MARK: - HRV 手動診断（Debug画面から呼ぶ）

    /// HealthKit内のHRVサンプルを全期間診断し、結果をViewModelへ反映する。
    /// 0件・エラー・サンプルありを明確に区別する。
    /// 診断Queryが成功した場合は最新サンプルをGraphicInputへ反映する。
    func runHRVDiagnostic() async {
        guard HealthKitManager.isAvailable else {
            MindWaveDebugLogger.log(.healthKit, "HRV diagnostic: HealthKit not available")
            return
        }
        MindWaveDebugLogger.log(.healthKit, "HRV diagnostic triggered from Debug")
        let (samples, err) = await hkManager.diagnoseHRVSamples(limit: 20)
        hrvDiagnosticSamples = samples
        hrvDiagnosticError   = err

        if let err {
            MindWaveDebugLogger.log(.error, "HRV diagnostic failed: \(err)")
            hrvInitialQueryStatus = "エラー: \(err)"
            return
        }

        hrvInitialQueryStatus = samples.isEmpty ? "0件" : "成功 \(samples.count)件"

        // 最新サンプルが存在する場合、ViewModelへ反映してGraphicInputを再計算する
        if let latest = samples.first {
            let result = HealthMetricFetchResult(
                value:                  latest.valueMilliseconds,
                source:                 "診断クエリ",
                message:                "診断取得: \(String(format: "%.1f", latest.valueMilliseconds))ms",
                sampleDate:             latest.startDate,
                sampleIdentifier:       latest.uuid.uuidString,
                sampleEndDate:          latest.endDate,
                sourceName:             latest.sourceName,
                sourceBundleIdentifier: latest.sourceBundleIdentifier,
                kind:                   .discreteSample
            )
            updateHRVState(result: result, source: .diagnostic)
            reevaluateActiveSource(now: Date())
            MindWaveDebugLogger.log(.healthKit, "[HRV] diagnostic applied to ViewModel")
        }
    }

    /// HRV observer を停止し、isHRVObserverActive を false に戻す。
    func stopHRVObserver() {
        hkManager.stopHRVObserver()
        isHRVObserverActive = false
        MindWaveDebugLogger.log(.healthKit, "HRV observer stopped from ViewModel")
    }

    // MARK: - HRV状態の統一更新

    /// HRV状態更新の共通処理。実HRVサンプル（discreteSample）のみを採用対象とする。
    /// aggregateFallback は applyFetchedValues で別途処理するため、ここでは除外する。
    ///
    /// - Parameters:
    ///   - result: HealthKitから得たHRV結果（kind == .discreteSample のみ処理する）
    ///   - source: 呼び出し経路を示す HRVUpdateSource
    /// - Returns: 状態を実際に更新した場合 true（除外・非対象は false）
    @discardableResult
    private func updateHRVState(result: HealthMetricFetchResult, source: HRVUpdateSource) -> Bool {
        // 実サンプル以外は採用しない（集計値を新規サンプルとして数えない）
        guard result.kind == .discreteSample else {
            MindWaveDebugLogger.log(.healthKit,
                "[HRV] updateHRVState: non-discrete kind=\(result.kind) skipped source=\(source.rawValue)")
            return false
        }

        guard let newValue = result.value else {
            MindWaveDebugLogger.log(.healthKit, "[HRV] update: no value source=\(source.rawValue)")
            return false
        }

        // UUID重複チェック（全経路で共有する lastHRVSampleIdentifier を使用）
        if let newId = result.sampleIdentifier, newId == lastHRVSampleIdentifier {
            hrvVMDuplicateCount += 1
            MindWaveDebugLogger.log(.healthKit, "[HRV] VM duplicate rejected source=\(source.rawValue)")
            isNewHRVSample = false
            return false
        }

        // endDate 古値チェック（latestHRVEndDate が非nilのとき比較）
        // sampleEndDateのみを基準とし、sampleDate は代替として使わない
        if let existEnd = latestHRVEndDate, let newEnd = result.sampleEndDate {
            if newEnd < existEnd {
                hrvVMStaleCount += 1
                MindWaveDebugLogger.log(.healthKit, "[HRV] VM stale rejected source=\(source.rawValue)")
                isNewHRVSample = false
                return false
            }
            if newEnd == existEnd {
                hrvVMStaleCount += 1
                MindWaveDebugLogger.log(.healthKit, "[HRV] VM same-time conflict rejected source=\(source.rawValue)")
                isNewHRVSample = false
                return false
            }
        }

        // ── 実HRVサンプルとして状態を更新 ───────────────────────────
        lastHRVSampleIdentifier  = result.sampleIdentifier
        latestHRVSampleDate      = result.sampleDate
        latestHRVEndDate         = result.sampleEndDate
        latestHRVSourceName      = result.sourceName
        latestHRVBundleID        = result.sourceBundleIdentifier
        isNewHRVSample           = true
        didFetchHRV              = true
        currentHRV               = newValue
        lastHRVUpdateSource      = source
        lastHRVDisplayUpdateDate = Date()
        hrvDisplayUpdateCount   += 1
        // いずれかの経路で実サンプルを採用済みとしてマーク
        hasAcceptedAnyDiscreteHRVSample = true

        // latestHealthKitSample.hrv を直接更新する。
        // HR取得の有無に依存せず selectActiveSample の Watch+HRV補完ロジックが使用する。
        latestHealthKitSample = MindWaveSample(
            heartRate: latestHealthKitSample?.heartRate,
            hrv: newValue,
            contextScore: nil,
            source: .healthKit,
            timestamp: result.sampleDate ?? Date()
        )

        // 経路別採用カウンター（集計フォールバックは含まない）
        switch source {
        case .anchoredInitial:
            hrvAnchoredInitialAcceptedCount += 1
        case .anchoredUpdate:
            hrvAnchoredUpdateAcceptedCount  += 1
        case .initialFetch:
            hrvInitialFetchAcceptedCount  += 1
        case .periodicFetch:
            hrvPeriodicFetchAcceptedCount += 1
        case .diagnostic, .none, .aggregateFallback:
            break
        }

        MindWaveDebugLogger.log(.healthKit, "[HRV] display accepted source=\(source.rawValue)")
        return true
    }

    /// HKAnchoredObjectQuery の1 callback（resultsHandler / updateHandler）全体を Batch として受け取る。
    /// サンプル0件・全除外・エラー時も callback カウンターを更新する。
    func applyHRVObserverBatch(_ batch: HRVObserverBatch) {
        // 1. callback診断（採否に関係なく必ず更新）
        switch batch.phase {
        case .initial:
            hrvAnchoredInitialCallbackCount   += 1
            lastHRVAnchoredInitialCallbackDate  = batch.callbackDate
        case .update:
            hrvAnchoredUpdateCallbackCount    += 1
            lastHRVAnchoredUpdateCallbackDate   = batch.callbackDate
        }
        lastHRVAnchoredRawSampleCount  = batch.rawSampleCount
        lastHRVAnchoredHKMAcceptedCount = batch.acceptedResults.count
        // HKMレベル除外をHKMカウンターへ加算（VM側の除外はupdateHRVState内で別途計上）
        hrvHKMDuplicateCount += batch.duplicateRejectedCount
        hrvHKMStaleCount     += batch.staleRejectedCount
        // Queryエラー状態を更新（エラーなし=nil, エラーあり=errorDescription）
        lastHRVQueryError = batch.errorDescription

        MindWaveDebugLogger.log(.healthKit,
            "[HRV] batch phase=\(batch.phase.rawValue) rawCount=\(batch.rawSampleCount) acceptedCount=\(batch.acceptedResults.count) error=\(batch.errorDescription != nil)")

        // 2. 採用済み結果を処理
        var anyUpdated = false
        let source: HRVUpdateSource = batch.phase == .initial ? .anchoredInitial : .anchoredUpdate
        for result in batch.acceptedResults {
            if updateHRVState(result: result, source: source) {
                anyUpdated = true
            }
        }

        // 3. 実際に更新があった場合のみ再評価
        if anyUpdated {
            lastGraphicUpdateTrigger = "hrv"
            reevaluateActiveSource(now: Date())
            MindWaveDebugLogger.log(.healthKit,
                "[HRV] display refreshed source=\(source.rawValue) watchFresh=\(isWatchSampleFresh)")
        }
    }

    // MARK: - Watch ライブ心拍 コールバック登録

    /// WatchConnectivityManager.shared からの心拍コールバックを applyWatchHeartRate に接続する。
    /// init から1回だけ呼ばれる。
    private func subscribeToWatchHeartRate() {
        WatchConnectivityManager.shared.onHeartRateReceived = { [weak self] hr, date in
            self?.applyWatchHeartRate(hr, sampleDate: date)
        }
    }

    // MARK: - Watch ライブ心拍 反映

    /// WatchConnectivityManager 経由で心拍を受信したときのコールバック。
    /// Mock ON 中でも常に Watch サンプルを ingest し、watchLive 受信履歴を更新する。
    /// selectActiveSample で Mock が優先されるため、GraphicInput は Mock 値を維持する。
    func applyWatchHeartRate(_ heartRate: Double, sampleDate: Date) {
        // 古いパケット・同一タイムスタンプの重複チャネル配信を無視する
        // 3チャネル戦略（sendMessage / updateApplicationContext / transferUserInfo）で
        // 同じパケットが複数届いた場合も最初の1件だけ処理する。
        let ts = sampleDate.timeIntervalSince1970
        guard ts > lastAppliedWatchTimestamp else {
            MindWaveDebugLogger.log(.watch, "[ViewModel] stale payload ignored ts=\(String(format: "%.3f", ts))")
            return
        }
        lastAppliedWatchTimestamp = ts

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
        MindWaveDebugLogger.log(.watch, "[ViewModel] watch heart rate accepted mockMode=\(isMockMode)")

        // HRVはWatchサンプルに埋め込まず、selectActiveSampleの補完ロジック
        // (latestHealthKitSample?.hrv) に委ねる。
        // これにより、HRV observer 更新時に latestWatchSample.timestamp を
        // 書き換えずに最新HRVを即時反映できる。
        lastGraphicUpdateTrigger = "heartRate"
        ingest(MindWaveSample(
            heartRate: heartRate,
            hrv: nil,
            contextScore: nil,
            source: .watchLive,
            timestamp: sampleDate
        ))
    }

    // MARK: - Demo Data

    /// インデックスで指定したデモシナリオのベースライン値を設定する。
    /// Mock ON 時のみ ingest を呼んで GraphicInput を更新する。
    /// Mock OFF 時はベースライン値の初期化のみ行い、GraphicInput はWatch/HealthKitが管理する。
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
            MindWaveDebugLogger.log(.healthKit, "authorization request completed")
            healthKitStatusLabel = "HealthKit：権限要求完了"
            if !forceDemoMode { await fetchHealthKitData() }
            startHRVObserver()
        } catch {
            healthKitStatusLabel = "HealthKit：許可リクエスト失敗"
            MindWaveDebugLogger.log(.error, "HealthKit authorization error: \(error)")
        }
    }

    // MARK: - HealthKit 単発取得

    /// HealthKit から最新の心拍・HRV を非同期で取得し、applyFetchedValues に渡す。
    /// forceDemoMode が true のときは何もしない。
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

    /// HealthKit の定期取得ループを開始する。すでに監視中の場合は何もしない。
    /// HealthKit 非対応デバイスでは開始せずメッセージを更新する。
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
        MindWaveDebugLogger.log(.lifecycle, "start live monitoring interval=\(Int(liveUpdateInterval))s")

        liveMonitoringTask = Task { [weak self] in
            guard let self else { return }
            // HealthKit認可がまだであれば権限ダイアログを表示し、初回取得とHRV Observerを開始する。
            // 既に認可済みの場合は即座に完了する（iOS挙動）。
            await self.requestHealthKitAuthorization()
            await self.runLiveMonitoringLoop()
        }
    }

    /// HealthKit の定期取得ループを停止し、liveMonitoringTask をキャンセルする。
    func stopLiveMonitoring() {
        liveMonitoringTask?.cancel()
        liveMonitoringTask    = nil
        isLiveMonitoring      = false
        liveMonitoringMessage = "停止しました"
        MindWaveDebugLogger.log(.lifecycle, "stop live monitoring")
    }

    func toggleLiveMonitoring() {
        if isLiveMonitoring {
            stopLiveMonitoring()
        } else {
            // ライブ取得開始時にMockモードを自動解除する。
            // これにより実データがGraphicInputへ流れるようになる。
            if isMockMode {
                MindWaveDebugLogger.log(.mock, "mock mode auto-disabled on live monitoring start")
                setMockMode(false)
            }
            startLiveMonitoring()
        }
    }

    // MARK: - Private: ライブ監視ループ

    private func runLiveMonitoringLoop() async {
        while !Task.isCancelled {
            liveUpdateCount += 1
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

    /// HealthKit 取得結果を評価してサンプルの新旧を判定し、ingest パイプラインへ渡す。
    /// 取得失敗時はデモデータへフォールバックせず、reevaluateActiveSource を呼んで現状ソースで継続する。
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
            } else {
                isNewHeartRateSample          = true
                sameSampleCount               = 0
                lastHeartRateSampleIdentifier = newId
                livePulseTrigger             += 1
                liveMonitoringMessage         = "新しい心拍データを取得"
                MindWaveDebugLogger.log(.healthKit, "[HR] new sample")
            }
            latestHeartRateSampleDate = hrResult.sampleDate
        } else {
            isNewHeartRateSample  = false
            liveMonitoringMessage = "心拍データ未取得"
        }

        // HRV状態を統一経路で更新（latestHealthKitSample.hrv・currentHRV・診断変数を一括更新）
        switch hrvResult.kind {
        case .discreteSample:
            // 実サンプル：採用カウンター・UUID・endDate を更新する
            let fetchSource: HRVUpdateSource = hasAcceptedAnyDiscreteHRVSample ? .periodicFetch : .initialFetch
            updateHRVState(result: hrvResult, source: fetchSource)
            hrvInitialQueryStatus = "成功（実サンプル）"
        case .aggregateFallback:
            // 集計値：採用カウンター・UUID・endDate は変更しない
            fallbackAggregateHRVDisplayCount += 1
            lastHRVUpdateSource = .aggregateFallback
            // 実サンプル未取得の場合のみ currentHRV を集計値で補完（スコア計算のみ）
            if !hasAcceptedAnyDiscreteHRVSample, let v = hrvResult.value {
                currentHRV = v
                didFetchHRV = true
            }
            MindWaveDebugLogger.log(.healthKit, "[HRV] aggregate fallback displayed")
            hrvInitialQueryStatus = "集計フォールバック"
        case .unavailable:
            isNewHRVSample = false
            hrvInitialQueryStatus = "0件"
            MindWaveDebugLogger.log(.healthKit, "[HRV] fetch result: no value")
        }

        // ── HealthKit値をingestパイプラインへ ─────────────────────
        // HR+HRV合算サンプルをingestする。HR取得失敗時はHRV単体更新のみ（上で実施済み）。
        lastGraphicUpdateTrigger = "healthKit"
        if let hr = hrResult.value, let avg = avgHR {
            averageHeartRate = avg
            if let _ = hrvResult.value, let avgH = avgHRV {
                averageHRV           = avgH
                healthKitStatusLabel = "HealthKit：接続中"
                lastFetchMessage     = "心拍・HRV 取得成功"
                MindWaveDebugLogger.log(.healthKit, "[HR+HRV] fetched, passing to ingest")
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
            // HR取得失敗 → HRVは updateHRVState 経由で更新済みのため latestHealthKitSample.hrv はセット済み。
            // Watch+HRV補完のために reevaluateActiveSource を呼ぶ。
            healthKitStatusLabel = "HealthKit：データなし"
            lastFetchMessage     = "心拍未取得: \(hrResult.message)"
            MindWaveDebugLogger.log(.healthKit, "HR fetch failed; re-evaluating source")
            reevaluateActiveSource(now: Date())
        }
    }

    // MARK: - Private: confidence 計算

    /// データソース種別に応じた推定確からしさ（0〜1）を返す。
    /// Mock: mockConfidence スライダー値、Watch: HRVあり0.75/なし0.50、HealthKit: HRVあり0.65/なし0.40。
    /// データソース種別に応じた推定確からしさ（0〜1）を返す。
    /// watchLive: sample.hrv が実測値ありなら0.75、なし（HRV未取得）なら0.50。
    /// currentHRV（デモ初期値含む）は使用しない。
    private func computeConfidence(sample: MindWaveSample) -> Double {
        switch sample.source {
        case .mock:        return mockConfidence
        case .watchLive:   return sample.hrv != nil ? 0.75 : 0.50
        case .healthKit:   return sample.hrv != nil ? 0.65 : 0.40
        case .unavailable: return 0.0
        }
    }
}
