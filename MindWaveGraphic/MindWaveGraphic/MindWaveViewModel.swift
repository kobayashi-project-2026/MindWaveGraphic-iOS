//
//  MindWaveViewModel.swift
//  MindWaveGraphic
//

import Foundation
import Combine

// ─────────────────────────────────────────────────────────
// MindWaveViewModel
// HealthKit実データとデモデータを切り替えながら、
// スコア計算の入力値と画面表示状態を管理する。
//
// UIはこのViewModelのみを参照する。
// データがHealthKitから来るかデモから来るかをUIは意識しない。
// ─────────────────────────────────────────────────────────
@MainActor
final class MindWaveViewModel: ObservableObject {

    // MARK: - Published: スコア計算の入力値

    /// 現在（直近）の心拍数（bpm）
    @Published var currentHeartRate: Double = 58
    /// 個人の平常時平均心拍数（bpm）。過去7日の平均をHealthKitから取得する。
    @Published var averageHeartRate: Double = 65
    /// 現在（直近）のHRV・SDNN（ms）
    @Published var currentHRV: Double       = 52
    /// 個人の平常時平均HRV（ms）。過去7日の平均をHealthKitから取得する。
    @Published var averageHRV: Double       = 45

    // MARK: - Published: データ元・状態表示

    /// デモデータで動作中か否か
    @Published var isUsingDemoData: Bool = true
    /// 画面下部に表示するデータ元ラベル
    @Published var dataSourceLabel: String = "デモデータで表示中"
    /// HealthKit接続状態ラベル（ホーム画面に表示）
    @Published var healthKitStatusLabel: String = "HealthKit：未許可"

    // MARK: - Published: 診断表示用

    /// 最後にHealthKit取得を試みた結果のメッセージ
    @Published var lastFetchMessage: String = "まだ取得していません"
    /// 最後にHealthKit取得を試みた日時（nilは未取得）
    @Published var lastFetchDate: Date? = nil
    /// 心拍数が取得できたか
    @Published var didFetchHeartRate: Bool = false
    /// HRVが取得できたか
    @Published var didFetchHRV: Bool = false

    // MARK: - Computed: スコア計算

    /// StressScoreCalculator を使って緊張不安定度（0〜100）を算出する。
    /// 計算式は FORMULA.md 参照。
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
    // iPhone実機での波形確認が完了したため false に設定している。
    // 再度デモ固定に戻したい場合は true に変更する。
    private let forceDemoMode = false

    private let hkManager = HealthKitManager()

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
    /// 許可が得られた場合、forceDemoMode=false であれば即座にデータ取得を試みる。
    func requestHealthKitAuthorization() async {
        guard HealthKitManager.isAvailable else {
            // iOSシミュレータなどHealthKitが使えないデバイス
            healthKitStatusLabel = "HealthKit：このデバイスでは利用不可"
            print("[MindWave] HealthKit利用不可デバイス")
            return
        }
        do {
            try await hkManager.requestAuthorization()
            print("[MindWave] HealthKit authorization requested")
            if forceDemoMode {
                // デモモード中は許可だけ行い実データは取得しない
                healthKitStatusLabel = "HealthKit：許可済み（デモモード）"
            } else {
                healthKitStatusLabel = "HealthKit：許可済み"
                // 許可取得直後にデータ取得を試みる
                await fetchHealthKitData()
            }
        } catch {
            healthKitStatusLabel = "HealthKit：許可リクエスト失敗"
            print("[MindWave] authorization error: \(error)")
        }
    }

    // MARK: - HealthKit Fetch

    /// HealthKitから心拍数とHRVを取得して波形に反映する。
    ///
    /// データの組み合わせに応じて以下のように動作する：
    ///   心拍数○ + HRV○ → 完全HealthKitモード
    ///   心拍数○ + HRV✗ → 心拍はリアル、HRVはデモ値を維持（部分接続）
    ///   心拍数✗         → 完全デモフォールバック
    ///
    /// HealthKitのデータはApple Watchで記録され、iPhoneのヘルスケアアプリに
    /// 同期されている必要がある。データが存在しない場合はデモに戻る。
    func fetchHealthKitData() async {
        // HealthKit非対応デバイスでは何もしない
        guard HealthKitManager.isAvailable else {
            lastFetchMessage = "HealthKit利用不可"
            return
        }
        // デモモードフラグが立っている場合は取得しない
        guard !forceDemoMode else {
            lastFetchMessage = "デモモード中（forceDemoMode=true）"
            return
        }

        print("[MindWave] HealthKit取得開始 ─────────────")

        // 直近30分の平均心拍数（現在値として使用）
        let hrResult    = await hkManager.fetchRecentHeartRate(minutes: 30)
        // 過去7日の平均心拍数（個人ベースラインとして使用）
        let avgHR       = await hkManager.fetchAverageHeartRate(days: 7)
        // HRV: 直近30分→24時間→最新値 の順でフォールバック取得
        let hrvResult   = await hkManager.fetchRecentHRV()
        // 過去7日の平均HRV（個人ベースラインとして使用）
        let avgHRV      = await hkManager.fetchAverageHRV(days: 7)

        // 取得結果を診断用フラグに反映する
        didFetchHeartRate = hrResult.value != nil
        didFetchHRV       = hrvResult.value != nil
        lastFetchDate     = Date()

        print("[MindWave] 取得結果 HR:\(hrResult.value.map{String(format:"%.1f",$0)} ?? "nil") HRV:\(hrvResult.value.map{String(format:"%.1f",$0)} ?? "nil")")

        // ──────────────────────────────────────────────
        // 心拍数（現在値・平均）が取得できた場合
        // ──────────────────────────────────────────────
        if let hr = hrResult.value, let avg = avgHR {
            currentHeartRate = hr
            averageHeartRate = avg

            if let hrv = hrvResult.value, let avgH = avgHRV {
                // 心拍数・HRV 両方取得できた → 完全にHealthKitデータで動作
                currentHRV      = hrv
                averageHRV      = avgH
                isUsingDemoData = false
                dataSourceLabel = "HealthKitデータで表示中"
                healthKitStatusLabel = "HealthKit：接続中"
                lastFetchMessage = "心拍・HRV 取得成功"
                print("[MindWave] Using HealthKit data ✓")

            } else {
                // HRVのみ取得できず → 心拍はリアル、HRVはデモ値を維持
                // HRVはApple WatchのHRV測定がないと記録されないため取得できない場合がある
                isUsingDemoData = false
                dataSourceLabel = "心拍：HealthKit / HRV：デモ"
                healthKitStatusLabel = "HealthKit：部分接続"
                lastFetchMessage = "心拍: 成功 / HRV: \(hrvResult.message)"
                print("[MindWave] Partial HealthKit - HRV fallback: \(hrvResult.message)")
            }

        } else {
            // ──────────────────────────────────────────────
            // 心拍数が取得できない → 完全デモデータにフォールバック
            // HealthKitの心拍は Apple Watch → iPhone 同期が必要。
            // 未装着・未同期の場合は取得できないためデモデータで継続する。
            // ──────────────────────────────────────────────
            loadDemoScenario(index: 0)
            healthKitStatusLabel = "HealthKit：データなし"
            lastFetchMessage = "心拍未取得: \(hrResult.message)"
            print("[MindWave] Fallback to demo data: \(hrResult.message)")
        }

        print("[MindWave] ────────────── 取得完了")
    }
}
