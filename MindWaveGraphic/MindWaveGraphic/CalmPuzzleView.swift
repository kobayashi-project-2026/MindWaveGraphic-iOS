import SwiftUI
import Combine

// MARK: - Level definitions

private let levels: [(size: Int, palette: [Color])] = [
    (3, [
        Color(red: 0.23, green: 0.49, blue: 0.65),
        Color(red: 0.29, green: 0.57, blue: 0.72),
        Color(red: 0.36, green: 0.64, blue: 0.79),
        Color(red: 0.49, green: 0.77, blue: 0.90),
    ]),
    (4, [
        Color(red: 0.29, green: 0.49, blue: 0.42),
        Color(red: 0.35, green: 0.57, blue: 0.50),
        Color(red: 0.42, green: 0.65, blue: 0.58),
        Color(red: 0.55, green: 0.80, blue: 0.75),
    ]),
    (4, [
        Color(red: 0.42, green: 0.35, blue: 0.54),
        Color(red: 0.49, green: 0.43, blue: 0.71),
        Color(red: 0.57, green: 0.52, blue: 0.84),
        Color(red: 0.73, green: 0.69, blue: 0.96),
    ]),
]

// MARK: - Shuffle helper

private func makeShuffledBoard(size: Int) -> (tiles: [Int], emptyIndex: Int) {
    let total = size * size
    var tiles = Array(1..<total) + [0]
    var empty = total - 1
    let n = size == 3 ? 80 : 160
    for _ in 0..<n {
        var nb: [Int] = []
        let r = empty / size, c = empty % size
        if r > 0        { nb.append(empty - size) }
        if r < size - 1 { nb.append(empty + size) }
        if c > 0        { nb.append(empty - 1) }
        if c < size - 1 { nb.append(empty + 1) }
        if let pick = nb.randomElement() {
            tiles.swapAt(pick, empty)
            empty = pick
        }
    }
    return (tiles, empty)
}

// MARK: - ViewModel

final class PuzzleGame: ObservableObject {
    @Published var tiles: [Int]
    @Published var emptyIndex: Int
    @Published var moves: Int = 0
    @Published var isComplete: Bool = false
    @Published var levelIndex: Int = 0
    @Published var animatingIndex: Int? = nil

    var size: Int { levels[levelIndex % levels.count].size }
    var total: Int { size * size }
    var palette: [Color] { levels[levelIndex % levels.count].palette }

    init() {
        let board = makeShuffledBoard(size: levels[0].size)
        self.tiles = board.tiles
        self.emptyIndex = board.emptyIndex
    }

    func reset() {
        let board = makeShuffledBoard(size: size)
        tiles = board.tiles
        emptyIndex = board.emptyIndex
        moves = 0
        isComplete = false
        animatingIndex = nil
    }

    func nextLevel() {
        levelIndex += 1
        let board = makeShuffledBoard(size: size)
        tiles = board.tiles
        emptyIndex = board.emptyIndex
        moves = 0
        isComplete = false
        animatingIndex = nil
    }

    func tryMove(at index: Int) {
        guard !isComplete, animatingIndex == nil else { return }
        let s = size
        let ar = index / s, ac = index % s
        let er = emptyIndex / s, ec = emptyIndex % s
        let adjacent = (abs(ar - er) == 1 && ac == ec) || (abs(ac - ec) == 1 && ar == er)
        guard adjacent else { return }

        animatingIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.tiles.swapAt(index, self.emptyIndex)
            self.emptyIndex = index
            self.moves += 1
            self.animatingIndex = nil
            self.isComplete = self.tiles.enumerated().allSatisfy { i, v in
                i == self.total - 1 ? v == 0 : v == i + 1
            }
        }
    }

    func tileColor(value: Int) -> Color {
        let pal = palette
        let ratio = Double(value - 1) / Double(max(total - 2, 1))
        let ci = min(Int(ratio * Double(pal.count - 1)), pal.count - 1)
        return pal[ci]
    }
}

// MARK: - Tile

private struct PuzzleTile: View {
    let value: Int
    let size: Int
    let color: Color
    let isAnimating: Bool
    let onTap: () -> Void

    var body: some View {
        Group {
            if value == 0 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .overlay(
                        Text("\(value)")
                            .font(.system(size: size == 3 ? 22 : 16, weight: .light))
                            .foregroundColor(.white.opacity(0.75))
                    )
                    .scaleEffect(isAnimating ? 0.88 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isAnimating)
                    .onTapGesture { onTap() }
            }
        }
    }
}

// MARK: - Guide Overlay

private struct PuzzleGuideOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.05, blue: 0.12).opacity(0.95).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(12)
                    }
                }
                .padding(.top, 16)
                .padding(.trailing, 8)

                Spacer()

                VStack(spacing: 32) {
                    Text("あそびかた")
                        .font(.system(size: 20, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.85))
                        .tracking(6)

                    VStack(spacing: 20) {
                        PuzzleGuideStep(icon: "hand.tap", text: "空きマスの隣にある\nタイルをタップ")
                        PuzzleGuideStep(icon: "arrow.up.arrow.down", text: "タイルをスライドさせて\n1から順に並べる")
                        PuzzleGuideStep(icon: "checkmark.circle", text: "すべて揃ったら\nクリア")
                    }

                    Text("手数が少ないほど上手です")
                        .font(.system(size: 12, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.28))
                        .tracking(2)
                }

                Spacer()

                Button(action: onClose) {
                    Text("はじめる")
                        .font(.system(size: 13, weight: .regular))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.70))
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        )
                }
                .padding(.bottom, 60)
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }
}

private struct PuzzleGuideStep: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.50))
                .frame(width: 32)
            Text(text)
                .font(.system(size: 14, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.70))
                .tracking(1)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Complete Overlay

private struct PuzzleCompleteOverlay: View {
    let moves: Int
    let onNext: () -> Void
    var body: some View {
        ZStack {
            Color(red: 0.031, green: 0.067, blue: 0.122).opacity(0.90).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("完成")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.88))
                    .tracking(8)
                Text("— \(moves) 手 —")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.white.opacity(0.32))
                    .tracking(4)
                Button(action: onNext) {
                    Text("次のレベル")
                        .font(.system(size: 13, weight: .regular))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.65))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                        )
                }
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Main View

struct CalmPuzzleView: View {
    @StateObject private var game = PuzzleGame()
    @State private var showGuide = false

    var body: some View {
        GeometryReader { geo in
            let boardSize = min(geo.size.width - 48, 318)
            let gap: CGFloat = game.size == 3 ? 8 : 6
            let tileSize = (boardSize - gap * CGFloat(game.size - 1)) / CGFloat(game.size)

            ZStack {
                Color(red: 0.031, green: 0.067, blue: 0.122).ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("MOVES")
                                .font(.system(size: 11))
                                .tracking(3)
                                .foregroundColor(.white.opacity(0.28))
                            Text("\(game.moves)")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer()
                        Button(action: { withAnimation { showGuide = true } }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.07))
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                    .frame(width: 34, height: 34)
                                Text("?")
                                    .font(.system(size: 15, weight: .ultraLight))
                                    .foregroundColor(.white.opacity(0.50))
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("LEVEL")
                                .font(.system(size: 11))
                                .tracking(3)
                                .foregroundColor(.white.opacity(0.28))
                            Text("\(game.levelIndex + 1)")
                                .font(.system(size: 22, weight: .light))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Board
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(tileSize), spacing: gap),
                            count: game.size
                        ),
                        spacing: gap
                    ) {
                        ForEach(0..<game.total, id: \.self) { idx in
                            let val = game.tiles[idx]
                            PuzzleTile(
                                value: val,
                                size: game.size,
                                color: val == 0 ? .clear : game.tileColor(value: val),
                                isAnimating: game.animatingIndex == idx,
                                onTap: { game.tryMove(at: idx) }
                            )
                            .frame(width: tileSize, height: tileSize)
                        }
                    }
                    .frame(width: boardSize, height: boardSize)

                    // Shuffle button
                    Button(action: { withAnimation { game.reset() } }) {
                        Text("シャッフル")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                            )
                    }
                    .padding(.top, 24)

                    Spacer()
                }

                if game.isComplete {
                    PuzzleCompleteOverlay(moves: game.moves) {
                        withAnimation { game.nextLevel() }
                    }
                }

                if showGuide {
                    PuzzleGuideOverlay { withAnimation { showGuide = false } }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    CalmPuzzleView()
}
