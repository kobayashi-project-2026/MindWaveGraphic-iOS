// MokorinGalleryView.swift
// Mokorin
//
// DEBUG 専用: もこりんの表情（happy / calm / sad / sleepy）と動作（wave / jump / nod）を一覧で確認する画面。
// 起動: MW_MOKORIN_GALLERY=1（AppRootView）。本番ビルドには含まれない。

#if DEBUG
import SwiftUI

struct MokorinGalleryView: View {
    @State private var actionPose = MokorinPose(emotion: .happy)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LaunchStarfieldBG().ignoresSafeArea()
            VStack(spacing: 18) {
                Text("もこりん 表情・動作の確認（DEBUG）")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(MokorinEmotion.allCases, id: \.self) { e in
                        VStack(spacing: 4) {
                            MokorinAvatarView(size: 120, pose: MokorinPose(emotion: e))
                            Text(e.rawValue).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(MokorinAction.allCases, id: \.self) { a in
                        Button(a.rawValue) { actionPose = actionPose.with(actionPose.emotion, a) }
                            .buttonStyle(.bordered)
                    }
                }
                MokorinAvatarView(size: 120, pose: actionPose)
            }
            .padding()
        }
        .task {
            // 起動直後に動作を順番に再生する（スクリーンショット確認用）
            for a in MokorinAction.allCases {
                try? await Task.sleep(for: .seconds(1.2))
                actionPose = actionPose.with(actionPose.emotion, a)
            }
        }
    }
}
#endif
