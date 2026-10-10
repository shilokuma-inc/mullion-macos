//
//  WindowMoverTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

/// ウィンドウの一覧とショートカット「Mullion」を、テストのためにまねる
nonisolated private final class FakeDesktop: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [WindowInfo]
    private(set) var requests: [[String: Any]] = []
    /// 次の呼び出しの直前に、手前の 2 枚の重なり順を入れ替える回数（一覧を読んでから呼び出すまでの間に順番が変わった場合）
    var reorderBeforeCalls = 0
    /// macOS がウィンドウを置ける上端（メニューバーの下に収める調整）
    var minimumY: CGFloat = 0
    /// これより小さくできないアプリ
    var minimumWidth: CGFloat = 0
    /// 呼ばれたら、このウィンドウを閉じる
    var closesWindowOnCall: Int?

    /// 番号が一覧の範囲を超えたとき（ショートカットの「リストから項目を取得」のエラーにあたる）
    struct IndexOutOfRange: Error {}
    /// ショートカットの返事を上書きする
    var reply: String?

    init(_ windows: [WindowInfo]) {
        self.windows = windows
    }

    func read() -> [WindowInfo] {
        lock.withLock { windows }
    }

    func frame(of number: Int) -> CGRect? {
        read().first { $0.number == number }?.frame
    }

    func run(_ input: String) throws -> String {
        try lock.withLock {
            let request = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? [:]
            requests.append(request)
            if reorderBeforeCalls > 0, windows.count >= 2 {
                reorderBeforeCalls -= 1
                windows.swapAt(0, 1)
            }
            if let number = closesWindowOnCall {
                windows.removeAll { $0.number == number }
            }
            if let reply {
                return reply
            }
            guard let index = request["index"] as? Int, windows.indices.contains(index - 1) else { throw IndexOutOfRange() }
            let window = windows[index - 1]
            let actual = ShortcutRequest.frameText(window.frame)
            guard actual == request["expected"] as? String else { return "mismatch|\(actual)" }
            var frame = window.frame
            if request["mode"] as? String == "move" {
                frame.origin = CGPoint(x: request["x"] as? Int ?? 0, y: max(Int(minimumY), request["y"] as? Int ?? 0))
            } else {
                frame.size = CGSize(width: max(Int(minimumWidth), request["width"] as? Int ?? 0), height: request["height"] as? Int ?? 0)
            }
            windows[index - 1] = WindowInfo(number: window.number, ownerPID: window.ownerPID, ownerName: window.ownerName, frame: frame)
            return "ok"
        }
    }
}

struct WindowMoverTests {
    private let target = CGRect(x: 1728, y: 30, width: 365, height: 331)

    private func makeDesktop() -> FakeDesktop {
        FakeDesktop([
            WindowInfo(number: 10, ownerPID: 1, ownerName: "Claude", frame: CGRect(x: 636, y: 319, width: 600, height: 600)),
            WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: CGRect(x: 185, y: 83, width: 656, height: 422))
        ])
    }

    private func makeMover(_ desktop: FakeDesktop) -> WindowMover {
        var mover = WindowMover(runShortcut: { try desktop.run($0) }, readWindows: { desktop.read() })
        mover.settleDelay = .zero
        return mover
    }

    /// サイズ変更 → 移動の順に、毎回いまの番号と位置・大きさを添えて頼む。大きさがそろえば 2 回目のサイズ変更は省く
    @Test
    func resizesThenMoves() async throws {
        let desktop = makeDesktop()
        let outcome = try await makeMover(desktop).move(windowNumber: 20, to: target)
        #expect(outcome == .placed)
        #expect(desktop.frame(of: 20) == target)
        #expect(desktop.frame(of: 10) == CGRect(x: 636, y: 319, width: 600, height: 600))
        #expect(desktop.requests.map { $0["mode"] as? String } == ["resize", "move"])
        #expect(desktop.requests.first?["index"] as? Int == 2)
        #expect(desktop.requests.first?["expected"] as? String == "185|83|656|422")
        #expect(desktop.requests.last?["expected"] as? String == "185|83|365|331")
    }

    /// すでに枠どおりなら、何も頼まない
    @Test
    func skipsWindowAlreadyInPlace() async throws {
        let desktop = FakeDesktop([WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: target)])
        #expect(try await makeMover(desktop).move(windowNumber: 20, to: target) == .placed)
        #expect(desktop.requests.isEmpty)
    }

    /// 一覧を読んでから呼び出すまでに重なり順が変わっても、別のウィンドウは動かさずに読み直して続ける
    @Test
    func retriesWhenOrderChanges() async throws {
        let desktop = makeDesktop()
        desktop.reorderBeforeCalls = 1
        let outcome = try await makeMover(desktop).move(windowNumber: 20, to: target)
        #expect(outcome == .placed)
        #expect(desktop.frame(of: 10) == CGRect(x: 636, y: 319, width: 600, height: 600))
        #expect(desktop.requests.map { $0["index"] as? Int } == [2, 1, 1])
    }

    /// 照らし合わせが合わないまま試す回数を超えたら、動かさずにあきらめる
    @Test
    func givesUpAfterRepeatedMismatches() async throws {
        let desktop = makeDesktop()
        desktop.reorderBeforeCalls = 10
        #expect(try await makeMover(desktop).move(windowNumber: 20, to: target) == .notMoved)
        #expect(desktop.requests.count == 3)
    }

    /// macOS がメニューバーの下に収めるなどで枠どおりにならなかったら、実際の位置と大きさを返す
    @Test
    func reportsAdjustedFrame() async throws {
        let desktop = makeDesktop()
        desktop.minimumY = 50
        desktop.minimumWidth = 400
        let outcome = try await makeMover(desktop).move(windowNumber: 20, to: target)
        #expect(outcome == .adjusted(CGRect(x: 1728, y: 50, width: 400, height: 331)))
        // 大きさがそろわないので、移動のあとにもう一度サイズ変更を頼む
        #expect(desktop.requests.map { $0["mode"] as? String } == ["resize", "move", "resize"])
    }

    /// 動かしている間に閉じられたウィンドウは、エラーにせずに飛ばす
    @Test
    func reportsClosedWindow() async throws {
        let desktop = makeDesktop()
        desktop.closesWindowOnCall = 20
        #expect(try await makeMover(desktop).move(windowNumber: 20, to: target) == .disappeared)
        #expect(try await makeMover(desktop).move(windowNumber: 99, to: target) == .disappeared)
    }

    /// 空の返事は、初めての実行で許可の確認が出ていることがあるので、続けずに止める
    @Test
    func stopsOnUnexpectedReply() async {
        let desktop = makeDesktop()
        desktop.reply = ""
        await #expect(throws: WindowMover.Failure.unexpectedReply("")) {
            try await makeMover(desktop).move(windowNumber: 20, to: target)
        }
    }
}
