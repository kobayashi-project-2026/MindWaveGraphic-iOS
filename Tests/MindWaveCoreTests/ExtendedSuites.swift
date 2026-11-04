// ExtendedSuites.swift
// フェーズC以降で追加したテストスイートの登録場所

import Foundation

func runExtendedSuites() async {
    PipelineTests.run()
    await InsightTests.run()
    await ChatTests.run()
    await MokorinTests.run()
    await MokorinAITests.run()
    await MokorinVoiceTests.run()
}
