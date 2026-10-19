//
//  SystemEventsWindowMover.swift
//  Mullion
//

import CoreGraphics

/// System Events を使って、ウィンドウ 1 枚を枠に動かす。
///
/// ショートカット「Mullion」の「ウインドウを移動」は負の座標を受け付けないため、メイン画面より左か上にある画面にはこちらで動かす。
/// System Events の座標もウィンドウサーバーと同じくメイン画面の左上が原点で、負の値も使える。
/// 操作のたびにウィンドウサーバーから今の位置と大きさを読み、プロセスのウィンドウのうちそれと一致するものを System Events に選ばせるので、
/// 途中でウィンドウが開閉されたり重なり順が変わったりしても、別のウィンドウを動かさない
nonisolated struct SystemEventsWindowMover: Sendable {
    typealias Outcome = WindowMover.Outcome

    enum Operation: Equatable, Sendable {
        case resize
        case move
    }

    enum Failure: Error, Equatable {
        /// 「オートメーション」で Mullion から System Events を操作することが許可されていない
        case automationNotPermitted
        /// 「アクセシビリティ」で Mullion が許可されていない
        case accessibilityNotPermitted
        /// System Events が動いていない。起動して送り直しても届かなかったときに投げる
        case systemEventsUnavailable
        /// 決まった時間内に終わらなかった（許可の確認が出たままのことがある）
        case timedOut
        /// 指定に合うウィンドウ（またはプロセス）が無い
        case noSuchWindow
        /// それ以外のエラー
        case failed(String)

        /// Apple Events のエラー番号から分類する
        static func from(code: Int, message: String) -> Failure {
            switch code {
            case -1743, -1744: .automationNotPermitted // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            case -1719, -25211: .accessibilityNotPermitted // errAEIllegalIndex / kAXErrorAPIDisabled。-1719 は合うウィンドウが無いときにも返る（move で見分ける）
            case -600, -609: .systemEventsUnavailable // procNotFound / connectionInvalid
            case -1712: .timedOut // errAETimeout
            case -1728: .noSuchWindow // errAENoSuchObject
            default: .failed(message.isEmpty ? "エラー \(code)" : message)
            }
        }
    }

    /// System Events への頼みごと。テストでは差し替える
    struct Client: Sendable {
        /// プロセスのウィンドウの位置と大きさを返す
        var windowFrames: @Sendable (pid_t) async throws -> [CGRect]
        /// プロセスのウィンドウのうち、位置と大きさが expected のものに操作を行い、大きさか位置を target にそろえる。
        /// 合うウィンドウが無ければ Failure.noSuchWindow を投げる
        var perform: @Sendable (_ operation: Operation, _ pid: pid_t, _ expected: CGRect, _ target: CGRect) async throws -> Void
    }

    var client: Client
    /// 手前から順のウィンドウ一覧
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
        for operation in [Operation.resize, .move, .resize] {
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
    private func perform(_ operation: Operation, windowNumber: Int, target: CGRect) async throws -> Outcome? {
        for _ in 0..<maxAttempts {
            guard let window = readWindows().first(where: { $0.number == windowNumber }) else {
                return .disappeared
            }
            let current = window.frame
            switch operation {
            case .resize where isClose(current.size, target.size), .move where isClose(current.origin, target.origin):
                return nil
            default:
                break
            }
            do {
                try await client.perform(operation, window.ownerPID, current, target)
                try await Task.sleep(for: settleDelay)
                return nil
            } catch let failure as Failure where failure == .noSuchWindow || failure == .accessibilityNotPermitted {
                // -1719 は「合うウィンドウが無い」ときにも「アクセシビリティの許可が無い」ときにも返るため、読み直して見分ける
                if !readWindows().contains(where: { $0.number == windowNumber }) {
                    return .disappeared
                }
                // 許可が無ければ、ここで同じ分類のエラーが投げられる
                _ = try await client.windowFrames(window.ownerPID)
                // 読めたなら、一覧を読んでから頼むまでの間に位置や大きさが変わった。読み直してもう一度試す
                try await Task.sleep(for: settleDelay)
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
