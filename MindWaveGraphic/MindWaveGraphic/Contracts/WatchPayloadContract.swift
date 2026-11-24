// WatchPayloadContract.swift
// Contracts
//
// Apple Watch → iPhone の心拍送信データ（WatchConnectivity の辞書）。
//
// 既存の通信形式（schema v0）と完全互換:
//   { "type": "heartRate", "heartRate": <Double bpm>, "timestamp": <UNIX秒 Double> }
// schema v1 では任意キー "schemaVersion": 1 を追加する（旧iPhoneアプリは未知キーを無視するため互換）。
// WCSession は [String: Any]（plist 型）を送るため、このデータだけは JSON ではなく辞書で表現する。
// キー名は既存の camelCase を維持する（変更すると旧Watchアプリと通信できなくなる）。

import Foundation

/// Watch から届く1件の心拍データ
nonisolated struct WatchHeartRatePayload: Equatable, Sendable {

    /// メッセージ種別（既存値 "heartRate" 固定）
    static let messageType = "heartRate"

    /// 辞書キー（既存の名前を変更しないこと）
    enum Key {
        static let type          = "type"
        static let heartRate     = "heartRate"
        static let timestamp     = "timestamp"
        static let schemaVersion = "schemaVersion"
    }

    /// 心拍数 bpm
    let heartRateBpm: Double
    /// Watch 側の計測時刻（UNIX 秒）
    let measuredAt: Date
    /// 送信側の schema version（キーなし = 0 = 旧Watchアプリ）
    let schemaVersion: Int

    init(heartRateBpm: Double, measuredAt: Date, schemaVersion: Int = MindWaveContract.schemaVersion) {
        self.heartRateBpm  = heartRateBpm
        self.measuredAt    = measuredAt
        self.schemaVersion = schemaVersion
    }

    /// 受信辞書の検証結果
    enum DecodeFailure: Error, Equatable {
        case typeMissingOrNotHeartRate
        case heartRateMissingOrWrongType
        case timestampMissingOrWrongType
        case unsupportedSchemaVersion(Int)
    }

    /// WCSession の辞書から復元する。数値は NSNumber/Double を受け付ける。
    static func decode(_ message: [String: Any]) -> Result<WatchHeartRatePayload, DecodeFailure> {
        guard let type = message[Key.type] as? String, type == messageType else {
            return .failure(.typeMissingOrNotHeartRate)
        }
        guard let hr = number(message[Key.heartRate]) else {
            return .failure(.heartRateMissingOrWrongType)
        }
        guard let ts = number(message[Key.timestamp]) else {
            return .failure(.timestampMissingOrWrongType)
        }
        let version = number(message[Key.schemaVersion]).map { Int($0) } ?? 0
        guard version >= 0 && version <= MindWaveContract.schemaVersion else {
            return .failure(.unsupportedSchemaVersion(version))
        }
        return .success(WatchHeartRatePayload(
            heartRateBpm: hr,
            measuredAt: Date(timeIntervalSince1970: ts),
            schemaVersion: version
        ))
    }

    /// WCSession 送信用の辞書（v1）
    var dictionary: [String: Any] {
        [
            Key.type:          Self.messageType,
            Key.heartRate:     heartRateBpm,
            Key.timestamp:     measuredAt.timeIntervalSince1970,
            Key.schemaVersion: schemaVersion
        ]
    }

    /// 生理的にあり得る範囲か（既存の受信処理は範囲外も警告ログのみで受け入れる方針。ここでも判定だけ行う）
    var isPlausible: Bool {
        heartRateBpm > 0 && heartRateBpm <= 250
    }

    /// 数値を読む。WCSession 経由の値は NSNumber（`as? Double` で読める）だが、
    /// プロセス内で組み立てた辞書の Swift Int は `as? Double` で読めないため Int も受け付ける。
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d.isFinite ? d : nil }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
