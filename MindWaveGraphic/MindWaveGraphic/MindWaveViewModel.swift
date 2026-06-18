//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

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

    // MARK: - 新規サンプル判定（診断用）

    @Published var latestHeartRateSampleDate: Date? = nil
    @Published var latestHRVSampleDate: Date?       = nil
    @Published var isNewHeartRateSample: Bool       = false
    @Published var isNewHRVSample: Bool             = false
    @Published var sameSampleCount: Int             = 0
    @Published var livePulseTrigger: Int            = 0

    // MARK: - HRV Observer 状態（診断用）

    @Published private(set) var isHRVObserverActive: Bool  = false
    @Published private(set) var lastHRVObserverDate: Date? = nil
    @Published private(set) var hrvObserverUpdateCount: Int = 0

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
        MindWaveDebugLogger.log(.graphic, "input updated score=\(String(format: "%.1f", tensionScore)) confidence=\(String(format: "%.2f", confidence)) state=\(state.rawValue)")
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
        hrvObserverStarted   = true
        isHRVObserverActive  = true
        hkManager.startHRVObserver { [weak self] result in
            Task { @MainActor [weak self] in
                self?.applyNewHRVSample(result)
            }
        }
        MindWaveDebugLogger.log(.healthKit, "HRV observer registered")
    }

    /// HealthKit に新しい HRV サンプルが保存されたときに呼ばれる（MainActor）。
    ///
    /// - 同一UUIDのサンプルは重複処理しない
    /// - HRV更新時は最新Watch心拍を使用する。Watchが有効期限内なら watchLive source、
    ///   そうでなければ healthKit source で ingest する
    /// - サンプル時刻は HRV サンプルの記録時刻を使う
    func applyNewHRVSample(_ result: HealthMetricFetchResult) {
        guard let newValue = result.value else {
            MindWaveDebugLogger.log(.healthKit, "HRV observer fired but no value")
            return
        }

        // 重複チェック：同じ UUID のサンプルは処理しない
        if let newId = result.sampleIdentifier, newId == lastHRVSampleIdentifier {
            MindWaveDebugLogger.log(.healthKit, "HRV observer: same sample skipped id=\(newId.prefix(8))")
            return
        }

        // 新しいサンプルを記録
        lastHRVSampleIdentifier = result.sampleIdentifier
        isNewHRVSample          = true
        latestHRVSampleDate     = result.sampleDate
        lastHRVObserverDate     = Date()
        hrvObserverUpdateCount += 1

        let dateStr = result.sampleDate.map { d in
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
        } ?? "?"
        MindWaveDebugLogger.log(.healthKit,
            "HRV observer: new sample value=\(String(format: "%.1f", newValue))ms " +
            "date=\(dateStr) id=\(result.sampleIdentifier?.prefix(8) ?? "nil")")

        // HRV更新時は最新Watch心拍と結合する
        let now = Date()
        let heartRate: Double?
        let source: MindDataSource
        if isWatchSampleFresh, let watchHR = latestWatchSample?.heartRate {
            heartRate = watchHR
            source    = .watchLive
            MindWaveDebugLogger.log(.healthKit, "HRV observer: combining with watchLive HR=\(String(format: "%.0f", watchHR))")
        } else {
            heartRate = currentHeartRate > 0 ? currentHeartRate : nil
            source    = .healthKit
            MindWaveDebugLogger.log(.healthKit, "HRV observer: Watch stale, using healthKit source")
        }

        ingest(MindWaveSample(
            heartRate: heartRate,
            hrv: newValue,
            contextScore: nil,
            source: source,
            timestamp: result.sampleDate ?? now
        ))
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
        MindWaveDebugLogger.log(.watch, "heart rate received bpm=\(Int(heartRate)) mockMode=\(isMockMode)")

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
            MindWaveDebugLogger.log(.healthKit, "authorization requested")
            healthKitStatusLabel = "HealthKit：許可済み"
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
            await self?.runLiveMonitoringLoop()
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
        isLiveMonitoring ? stopLiveMonitoring() : startLiveMonitoring()
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
                MindWaveDebugLogger.log(.healthKit, "new sample HR=\(String(format: "%.1f", hrResult.value ?? 0))")
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
                MindWaveDebugLogger.log(.healthKit, "HR+HRV fetched HR=\(String(format: "%.1f", hr)) HRV=\(String(format: "%.1f", hrv)); passing to ingest")
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
            MindWaveDebugLogger.log(.healthKit, "fetch failed; re-evaluating source")
            reevaluateActiveSource(now: Date())
        }
    }

    // MARK: - Private: confidence 計算

    /// データソース種別に応じた推定確からしさ（0〜1）を返す。
    /// Mock: mockConfidence スライダー値、Watch: HRVあり0.75/なし0.50、HealthKit: HRVあり0.65/なし0.40。
    private func computeConfidence(sample: MindWaveSample) -> Double {
        switch sample.source {
        case .mock:        return mockConfidence
        case .watchLive:   return currentHRV > 0 ? 0.75 : 0.50
        case .healthKit:   return sample.hrv != nil ? 0.65 : 0.40
        case .unavailable: return 0.0
        }
    }
}
