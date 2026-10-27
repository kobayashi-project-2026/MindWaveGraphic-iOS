// TestHarness.swift
// XCTest ターゲットを追加せずにロジックを検証するための最小テストハーネス。
// scripts/run_ios_core_tests.sh からアプリのソースと一緒にビルドされる。

import Foundation

enum TestHarness {
    static var passed = 0
    static var failed = 0
    static var failures: [String] = []
    private static var currentTest = ""
    private static var currentFailed = false

    static func suite(_ name: String) {
        print("\n=== \(name) ===")
    }

    static func test(_ name: String, _ body: () throws -> Void) {
        begin(name)
        do { try body() } catch { fail("unexpected error: \(error)") }
        end()
    }

    static func test(_ name: String, _ body: () async throws -> Void) async {
        begin(name)
        do { try await body() } catch { fail("unexpected error: \(error)") }
        end()
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String,
                       file: StaticString = #fileID, line: UInt = #line) {
        if !condition() { fail("\(message) (\(file):\(line))") }
    }

    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "",
                                          file: StaticString = #fileID, line: UInt = #line) {
        if a != b { fail("expected \(b) but got \(a) \(message) (\(file):\(line))") }
    }

    static func expectThrows(_ message: String, file: StaticString = #fileID, line: UInt = #line,
                             _ body: () throws -> Void) {
        do { try body(); fail("expected error: \(message) (\(file):\(line))") } catch {}
    }

    static func fail(_ message: String) {
        currentFailed = true
        failures.append("\(currentTest): \(message)")
        print("    ✗ \(message)")
    }

    private static func begin(_ name: String) {
        currentTest = name
        currentFailed = false
    }

    private static func end() {
        if currentFailed { failed += 1; print("  FAIL \(currentTest)") }
        else { passed += 1; print("  ok   \(currentTest)") }
    }

    /// 日時の比較（JSON はミリ秒精度のため 1ms 以内を同一とみなす）
    static func sameInstant(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return abs(x.timeIntervalSince(y)) < 0.001
        default: return false
        }
    }

    /// テスト専用の UserDefaults（実行ごとに空にする）
    static func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "mindwave.tests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }
}
