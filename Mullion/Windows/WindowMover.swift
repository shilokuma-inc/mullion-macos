//
//  WindowMover.swift
//  Mullion
//

import CoreGraphics

/// ショートカット「Mullion」を使って、ウィンドウ 1 枚を枠に動かす。
///
/// ショートカットは「手前から何番目のウィンドウか」でしかウィンドウを選べないため、操作のたびにウィンドウの一覧を読み直して番号を決め、
/// あわせて今の位置と大きさ（expected）を渡す。ショートカットは位置と大きさが一致したときだけ操作するので、
/// 途中でウィンドウが開閉されたり重なり順が変わったりしても、別のウィンドウを動かさない
nonisolated struct WindowMover: Sendable {
    enum Outcome: Equatable {
        /// 枠どおりに置けた
        case placed
        /// 動いたが、枠どおりにはならなかった。アプリの最小サイズや文字の大きさの刻み、
        /// macOS がウィンドウを画面内やメニューバーの下に収める調整などによる。値は実際の位置と大きさ
        case adjusted(CGRect)
        /// 動かしている間にウィンドウが閉じられた
        case disappeared
        /// 照らし合わせが合わないまま試す回数を超えた、または操作しても位置も大きさも変わらなかった
        case notMoved
    }

    enum Failure: Error, Equatable {
        /// ショートカットが想定外の返事をした。空のときは、初めての操作で macOS の許可の確認が出ていることがある
        case unexpectedReply(String)
    }

    /// ショートカットを実行して出力を返す
    var runShortcut: @Sendable (String) async throws -> String
    /// 手前から順のウィンドウ一覧（ショートカットの「ウィンドウを検索」と同じ並び）
    var readWindows: @Sendable () -> [WindowInfo]
    /// 操作のあと、ウィンドウサーバーの一覧に反映されるのを待つ時間
    var settleDelay: Duration = .milliseconds(150)
    /// 照らし合わせが合わなかったときに、一覧を読み直して試す回数
    var maxAttempts = 3
    /// 位置と大きさが「同じ」とみなす誤差（pt）
    var tolerance: CGFloat = 1

    func move(windowNumber: Int, to target: CGRect) async throws -> Outcome {
        guard let original = readWindows().first(where: { $0.number == windowNumber })?.frame else {
            return .disappeared
        }
        // 先に大きさを変えてから動かす（macOS は移動先を今の大きさで画面内に収めるため）。
        // 移動のときに画面の端で縮められることがあるので、最後にもう一度大きさをそろえる
        for operation in [ShortcutRequest.Operation.resize, .move, .resize] {
            if let outcome = try await perform(operation, windowNumber: windowNumber, target: target) {
                return outcome
            }
        }
        guard let window = readWindows().first(where: { $0.number == windowNumber }) else {
            return .disappeared
        }
        if isClose(window.frame.origin, target.origin), isClose(window.frame.size, target.size) {
            return .placed
        }
        return window.frame == original ? .notMoved : .adjusted(window.frame)
    }

    /// 1 つの操作を行う。続けられない結果になったときだけ Outcome を返す
    private func perform(_ operation: ShortcutRequest.Operation, windowNumber: Int, target: CGRect) async throws -> Outcome? {
        for _ in 0..<maxAttempts {
            let windows = readWindows()
            guard let index = windows.firstIndex(where: { $0.number == windowNumber }) else {
                return .disappeared
            }
            let current = windows[index].frame
            switch operation {
            case .resize where isClose(current.size, target.size), .move where isClose(current.origin, target.origin):
                return nil
            default:
                break
            }
            let request = ShortcutRequest.operate(operation, index: index + 1, expected: current, target: target)
            let output: String
            do {
                output = try await runShortcut(request)
            } catch {
                // 呼び出している間にウィンドウが閉じられると、番号が一覧の範囲を超えてショートカットがエラーになる
                if !readWindows().contains(where: { $0.number == windowNumber }) {
                    return .disappeared
                }
                throw error
            }
            switch ShortcutReply(output) {
            case .done:
                try await Task.sleep(for: settleDelay)
                return nil
            case .mismatch:
                // 一覧を読んでから呼び出すまでの間に、重なり順が変わった。読み直してもう一度試す
                try await Task.sleep(for: settleDelay)
            case let .unexpected(output):
                throw Failure.unexpectedReply(output)
            }
        }
        return .notMoved
    }

    private func isClose(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
    }

    private func isClose(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
