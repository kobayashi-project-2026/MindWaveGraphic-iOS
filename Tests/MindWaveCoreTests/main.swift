// main.swift
// テスト実行エントリポイント

import Foundation

print("MindWave core tests")

ContractTests.run()
HistoryStoreTests.run()
NavigationTests.run()
await runExtendedSuites()

print("\n----------------------------------------")
print("RESULT passed=\(TestHarness.passed) failed=\(TestHarness.failed)")
if !TestHarness.failures.isEmpty {
    print("FAILURES:")
    TestHarness.failures.forEach { print("  - \($0)") }
}
exit(TestHarness.failed == 0 ? 0 : 1)
