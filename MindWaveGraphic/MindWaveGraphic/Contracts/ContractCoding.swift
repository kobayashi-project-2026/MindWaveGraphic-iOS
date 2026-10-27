// ContractCoding.swift
// Contracts
//
// モジュール間・端末間・サーバー間でやり取りする JSON の共通ルール。
// 仕様の正本は docs/DATA_CONTRACTS.md。ここを変更したらドキュメントも更新すること。
//
// 共通ルール:
// - すべてのトップレベル文書は schema_version（整数）を持つ
// - キーは snake_case
// - 日時は ISO 8601（UTC・ミリ秒付き）例: "2026-10-28T04:35:12.123Z"
//   ※ 読み込みはミリ秒なし・UNIX秒（数値）も受け付ける（旧データ互換）
// - 単位: 心拍 bpm / HRV は SDNN の ms / スコア 0〜100 / 確からしさ 0〜1 / 時間は秒
// - 計測値の null は「未計測（値が存在しない）」を表す。0 で代用しない
// - is_mock = true のデータは実測として学習・分析に使わない

import Foundation

/// JSON 契約の共通設定
nonisolated enum MindWaveContract {

    /// 現在のスキーマバージョン。互換性のない変更をしたときだけ上げる。
    static let schemaVersion = 1

    /// 契約準拠の JSONEncoder（キー順固定で差分を安定させる）
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ContractDateFormatter.string(from: date))
        }
        return encoder
    }

    /// 契約準拠の JSONDecoder（ISO 8601 ミリ秒あり/なし・UNIX秒を受け付ける）
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let text = try container.decode(String.self)
            guard let date = ContractDateFormatter.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "ISO 8601 形式ではない日時: \(text)"
                )
            }
            return date
        }
        return decoder
    }

    /// schema_version が読み込み可能か（未来のバージョンは拒否する）
    static func isSupported(schemaVersion version: Int) -> Bool {
        version >= 1 && version <= schemaVersion
    }
}

/// 契約で使う日時フォーマッタ。ISO8601DateFormatter はスレッドセーフ。
nonisolated enum ContractDateFormatter {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func string(from date: Date) -> String {
        withFraction.string(from: date)
    }

    static func date(from text: String) -> Date? {
        withFraction.date(from: text) ?? withoutFraction.date(from: text)
    }
}

/// 契約の検証エラー
nonisolated enum ContractError: Error, Equatable, CustomStringConvertible {
    /// 読み込めない schema_version
    case unsupportedSchemaVersion(Int)
    /// 必須項目の欠落・型不一致
    case missingField(String)
    /// 値の範囲外
    case outOfRange(field: String, value: Double)
    /// 値の組み合わせが矛盾している
    case inconsistent(String)

    var description: String {
        switch self {
        case .unsupportedSchemaVersion(let v): return "unsupported schema_version=\(v)"
        case .missingField(let f):             return "missing field=\(f)"
        case .outOfRange(let f, let v):        return "out of range field=\(f) value=\(v)"
        case .inconsistent(let m):             return "inconsistent: \(m)"
        }
    }
}
