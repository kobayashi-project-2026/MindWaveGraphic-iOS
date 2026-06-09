//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

// ─────────────────────────────────────────────────────────
// MindWaveViewModel
// HealthKit実データとデモデータを切り替えながら、
// スコア計算の入力値・波形制御値・取得状態をすべて管理する。
//
// UIはこのViewModelのみを参照する。
// データがHealthKitから来るかデモから来るかをUIは意識しない。
// ─────────────────────────────────────────────────────────
@MainActor
final class MindWaveViewModel: ObservableObject {

    // MARK: - Published: スコア計算の入力値

    /// 現在（直近）の心拍数（bpm）
    @Published var currentHeartRate: Double = 58
    /// 個人の平常時平均心拍数（bpm）。過去7日平均をHealthKitから取得する。
    @Published var averageHeartRate: Double = 65
    /// 現在（直近）のHRV・SDNN（ms）
    @Published var currentHRV: Double       = 52
    /// 個人の平常時平均HRV（ms）。過去7日平均をHealthKitから取得する。
    @Published var averageHRV: Double       = 45

    // MARK: - Published: データ元・状態表示

    @Published var isUsingDemoData: Bool    = true
    @Published var dataSourceLabel: String  = "デモデータで表示中"
    @Published var healthKitStatusLabel: String = "HealthKit：未許可"

    // MARK: - Published: 単発取得の診断

    @Published var lastFetchMessage: String = "まだ取得していません"
    @Published var lastFetchDate: Date?     = nil
    @Published var didFetchHeartRate: Bool  = false
    @Published var didFetchHRV: Bool        = false

    // MARK: - Published: ライブ監視状態

    /// ライブ自動取得が動作中か
    @Published var isLiveMonitoring: Bool   = false
    /// 取得間隔（秒）。Apple Watchの同期頻度を考慮して5秒が上限目安。
    @Published var liveUpdateInterval: TimeInterval = 5
    /// ライブ取得の最終実行時刻
    @Published var lastLiveUpdateDate: Date? = nil
    /// ライブ取得の実行回数（Debug表示用）
    @Published var liveUpdateCount: Int      = 0
    /// ライブ監視の状態メッセージ
    @Published var liveMonitoringMessage: String = "停止中"
    /// HealthKitのサンプリング特性の注意書き（画面に小さく表示する）
    let healthKitSamplingNote = "Apple Watchの記録・同期タイミングにより、値は数秒ごとに必ず変化するとは限りません。"

    // MARK: - Computed: スコア計算

    /// StressScoreCalculator を使って緊張不安定度（0〜100）を算出する。
    /// 計算式は docs/FORMULA.md 参照。
    var stressResult: StressScoreResult {
        StressScoreCalculator.calculate(
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            currentHRV: currentHRV,
            averageHRV: averageHRV
        )
    }

    // MARK: - Private

    // デモ優先フラグ
    // false: HealthKit実データを取得する（本番モード）
    // true:  実データを取得せずデモデータで動作する（デモ安定確認用）
    private let forceDemoMode = false

    private let hkManager = HealthKitManager()

    // ライブ監視タスク（キャンセル可能なTaskで管理する）
    private var liveMonitoringTask: Task<Void, Never>?

    // 前回の心拍数（変化を検出するために保持する）
    private var lastFetchedHR: Double? = nil

    // MARK: - Init

    init() {
        // 起動時はデモデータ（平常時シナリオ）で表示する。
        // HealthKit接続はユーザーが許可ボタンを押した後に行う。
        loadDemoScenario(index: 0)
    }

    // MARK: - Demo Data

    /// デモシナリオを読み込む。
    /// HealthKitデータが取れない場合のフォールバックにも使用する。
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

    /// HealthKitの読み取り許可をリクエストする。
    /// 許可後、forceDemoMode=false であれば即座にデータ取得を試みる。
    func requestHealthKitAuthorization() async {
        guard HealthKitManager.isAvailable else {
            healthKitStatusLabel = "HealthKit：このデバイスでは利用不可"
            print("[MindWave] HealthKit利用不可デバイス")
            return
        }
        do {
            try await hkManager.requestAuthorization()
            print("[MindWave] HealthKit authorization requested")
            if forceDemoMode {
                healthKitStatusLabel = "HealthKit：許可済み（デモモード）"
            } else {
                healthKitStatusLabel = "HealthKit：許可済み"
                await fetchHealthKitData()
            }
        } catch {
            healthKitStatusLabel = "HealthKit：許可リクエスト失敗"
            print("[MindWave] authorization error: \(error)")
        }
    }

    // MARK: - HealthKit 単発取得

    /// HealthKitから心拍数とHRVを1回取得して波形に反映する。
    ///
    /// データの組み合わせに応じて以下のように動作する：
    ///   心拍数○ + HRV○ → 完全HealthKitモード
    ///   心拍数○ + HRV✗ → 心拍はリアル、HRVはデモ値を維持（部分接続）
    ///   心拍数✗         → 完全デモフォールバック
    func fetchHealthKitData() async {
        guard HealthKitManager.isAvailable else {
            lastFetchMessage = "HealthKit利用不可"
            return
        }
        guard !forceDemoMode else {
            lastFetchMessage = "デモモード中（forceDemoMode=true）"
            return
        }

        // 現在心拍数：最新1件 → 直近1分 → 5分 → 30分の順でフォールバック
        let hrResult  = await hkManager.fetchBestCurrentHeartRate()
        // 個人ベースライン：過去7日の平均心拍数
        let avgHR     = await hkManager.fetchAverageHeartRate(days: 7)
        // 現在HRV：直近30分 → 24時間 → 最新値の順でフォールバック
        let hrvResult = await hkManager.fetchBestCurrentHRV()
        // 個人ベースライン：過去7日の平均HRV
        let avgHRV    = await hkManager.fetchAverageHRV(days: 7)

        didFetchHeartRate = hrResult.isSuccess
        didFetchHRV       = hrvResult.isSuccess
        lastFetchDate     = Date()

        applyFetchedValues(hrResult: hrResult, avgHR: avgHR,
                           hrvResult: hrvResult, avgHRV: avgHRV)
    }

    // MARK: - ライブ監視 開始 / 停止 / 切り替え

    /// HealthKitを定期的に再取得するライブ監視を開始する。
    /// 既に起動中の場合は何もしない（二重起動を防ぐ）。
    ///
    /// HealthKitは完全なリアルタイムストリームではないため、
    /// 第1段階では一定間隔でポーリングして最新値を取得する方式をとる。
    /// Apple Watch側で新しい心拍データが記録・同期されていない場合、値は変化しない。
    func startLiveMonitoring() {
        guard !isLiveMonitoring else { return }
        guard HealthKitManager.isAvailable else {
            liveMonitoringMessage = "HealthKit利用不可のためライブ取得できません"
            return
        }
        isLiveMonitoring     = true
        liveUpdateCount      = 0
        liveMonitoringMessage = "ライブ取得中"
        print("[Live] start monitoring (interval: \(Int(liveUpdateInterval))s)")

        // Taskでライブ監視ループを起動する。
        // [weak self] でメモリリークを防ぐ。
        // Task.isCancelledでキャンセルを安全に検出する。
        liveMonitoringTask = Task { [weak self] in
            await self?.runLiveMonitoringLoop()
        }
    }

    /// ライブ監視を停止する。Taskをキャンセルしてnilにする。
    func stopLiveMonitoring() {
        liveMonitoringTask?.cancel()
        liveMonitoringTask    = nil
        isLiveMonitoring      = false
        liveMonitoringMessage = "停止しました"
        print("[Live] stop monitoring")
    }

    /// ライブ監視の開始・停止をトグルする。
    func toggleLiveMonitoring() {
        if isLiveMonitoring {
            stopLiveMonitoring()
        } else {
            startLiveMonitoring()
        }
    }

    // MARK: - Private: ライブ監視ループ

    /// 一定間隔でHealthKitからデータを取得し続けるループ。
    /// Task.isCancelledをチェックして安全に終了する。
    private func runLiveMonitoringLoop() async {
        while !Task.isCancelled {
            liveUpdateCount += 1
            print("[Live] fetch tick \(liveUpdateCount)")

            // HealthKitから最新値を取得する
            await fetchLiveData()

            lastLiveUpdateDate = Date()

            // 次の取得まで待機する。キャンセル時はループを抜ける。
            do {
                try await Task.sleep(for: .seconds(liveUpdateInterval))
            } catch {
                // CancellationError が来たらループを終了する
                break
            }
        }
    }

    /// ライブ監視ループから呼ばれる取得処理。
    /// 最新1件を優先し、前回と同じ値の場合もアプリは落ちない。
    private func fetchLiveData() async {
        guard !forceDemoMode else { return }

        // 現在心拍：最新の1件を優先する（ポーリングなのでできるだけ最新を使う）
        let hrResult  = await hkManager.fetchBestCurrentHeartRate()
        let avgHR     = await hkManager.fetchAverageHeartRate(days: 7)
        let hrvResult = await hkManager.fetchBestCurrentHRV()
        let avgHRV    = await hkManager.fetchAverageHRV(days: 7)

        didFetchHeartRate = hrResult.isSuccess
        didFetchHRV       = hrvResult.isSuccess
        lastFetchDate     = Date()

        // 前回と同じ心拍値の場合は「新規サンプルなし」と記録する
        if let hr = hrResult.value, hr == lastFetchedHR {
            liveMonitoringMessage = "新規サンプルなし（前回と同じ値: \(String(format: "%.0f", hr)) bpm）"
            print("[Live] no new HealthKit sample (HR unchanged: \(String(format: "%.1f", hr)))")
        }

        applyFetchedValues(hrResult: hrResult, avgHR: avgHR,
                           hrvResult: hrvResult, avgHRV: avgHRV)
    }

    // MARK: - Private: 取得値をViewModelに反映する共通処理

    /// 取得した心拍・HRV値をViewModelのプロパティに反映する。
    /// データの組み合わせに応じて動作モードを切り替える。
    private func applyFetchedValues(
        hrResult: HealthMetricFetchResult,
        avgHR: Double?,
        hrvResult: HealthMetricFetchResult,
        avgHRV: Double?
    ) {
        if let hr = hrResult.value, let avg = avgHR {
            // ── 心拍数が取得できた場合 ───────────────────────
            currentHeartRate = hr
            averageHeartRate = avg
            lastFetchedHR    = hr

            if let hrv = hrvResult.value, let avgH = avgHRV {
                // 心拍数・HRV 両方取得できた → 完全にHealthKitデータで動作
                currentHRV           = hrv
                averageHRV           = avgH
                isUsingDemoData      = false
                dataSourceLabel      = "HealthKitデータで表示中"
                healthKitStatusLabel = "HealthKit：接続中"
                lastFetchMessage     = "心拍・HRV 取得成功"
                liveMonitoringMessage = isLiveMonitoring ? "ライブ取得中 ✓" : liveMonitoringMessage
                let score = stressResult.stressScore
                print("[MindWave] score updated: \(String(format: "%.1f", score))")

            } else {
                // HRVのみ取得できず → 心拍はリアル、HRVはデモ値を維持
                isUsingDemoData      = false
                dataSourceLabel      = "心拍：HealthKit / HRV：デモ"
                healthKitStatusLabel = "HealthKit：部分接続"
                lastFetchMessage     = "心拍: 成功 / HRV: \(hrvResult.message)"
                print("[MindWave] Partial HealthKit - HRV fallback: \(hrvResult.message)")
            }

        } else {
            // ── 心拍数が取得できない → 完全デモフォールバック ────
            // HealthKitの心拍は Apple Watch → iPhone 同期が必要。
            // 未装着・未同期の場合は取得できないためデモデータで継続する。
            loadDemoScenario(index: 0)
            healthKitStatusLabel = "HealthKit：データなし"
            lastFetchMessage     = "心拍未取得: \(hrResult.message)"
            liveMonitoringMessage = "データなし（\(hrResult.message)）"
            print("[MindWave] Fallback to demo data: \(hrResult.message)")
        }
    }
}
