//
//  SystemEventsWindowMoverTests.swift
//  MullionTests
//

import AppKit
import CoreGraphics
@testable import Mullion
import Testing

/// ウィンドウの一覧と System Events を、テストのためにまねる
nonisolated private final class FakeSystemEvents: @unchecked Sendable {
    typealias Operation = SystemEventsWindowMover.Operation
    typealias Failure = SystemEventsWindowMover.Failure

    struct Request: Equatable {
        let operation: Operation
        let pid: pid_t
        let expected: CGRect
        let target: CGRect
    }

    private let lock = NSLock()
    private var windows: [WindowInfo]
    private(set) var requests: [Request] = []
    /// 次の操作の直前に、動かそうとしているウィンドウを少しずらす回数（一覧を読んでから頼むまでの間に、ユーザーが動かした場合）
    var nudgeBeforeCalls = 0
    /// macOS がウィンドウを置ける上端（メニューバーの下に収める調整）
    var minimumY: CGFloat = -.infinity
    /// これより小さくできないアプリ
    var minimumWidth: CGFloat = 0
    /// 呼ばれたら、このウィンドウを閉じる
    var closesWindowOnCall: Int?
    /// 操作のときに投げるエラー
    var performError: Failure?
    /// 一覧を読むときに投げるエラー
    var readError: Failure?
    /// 画面の一覧には出ないが System Events の window には含まれるウィンドウ（しまってあるもの）
    var minimizedFrames: [pid_t: [CGRect]] = [:]
    /// 移動のときに macOS がこの大きさまで縮める（画面の端に収める調整）
    var shrinksOnMoveTo: CGSize?

    init(_ windows: [WindowInfo]) {
        self.windows = windows
    }

    func read() -> [WindowInfo] {
        lock.withLock { windows }
    }

    func frame(of number: Int) -> CGRect? {
        read().first { $0.number == number }?.frame
    }

    func windowFrames(pid: pid_t) throws -> [CGRect] {
        try lock.withLock {
            if let readError { throw readError }
            return windows.filter { $0.ownerPID == pid }.map(\.frame) + minimizedFrames[pid, default: []]
        }
    }

    func perform(_ operation: Operation, pid: pid_t, expected: CGRect, target: CGRect) throws {
        try lock.withLock {
            requests.append(Request(operation: operation, pid: pid, expected: expected, target: target))
            if let number = closesWindowOnCall {
                windows.removeAll { $0.number == number }
            }
            if let performError { throw performError }
            if nudgeBeforeCalls > 0, let index = windows.firstIndex(where: { $0.ownerPID == pid && $0.frame == expected }) {
                nudgeBeforeCalls -= 1
                let window = windows[index]
                windows[index] = WindowInfo(
                    number: window.number,
                    ownerPID: window.ownerPID,
                    ownerName: window.ownerName,
                    frame: window.frame.offsetBy(dx: 40, dy: 0)
                )
            }
            // System Events はプロセスの中から、位置と大きさが一致するウィンドウを選ぶ
            guard let index = windows.firstIndex(where: { $0.ownerPID == pid && $0.frame == expected }) else {
                throw Failure.noSuchWindow
            }
            let window = windows[index]
            var frame = window.frame
            switch operation {
            case .move:
                frame.origin = CGPoint(x: target.minX, y: max(minimumY, target.minY))
                if let shrinksOnMoveTo { frame.size = shrinksOnMoveTo }
            case .resize: frame.size = CGSize(width: max(minimumWidth, target.width), height: target.height)
            }
            windows[index] = WindowInfo(number: window.number, ownerPID: window.ownerPID, ownerName: window.ownerName, frame: frame)
        }
    }
}

struct SystemEventsWindowMoverTests {
    /// メイン画面の左にある画面の左半分
    private let target = CGRect(x: -1728, y: 32, width: 864, height: 1085)
    private let other = CGRect(x: 636, y: 319, width: 600, height: 600)

    private func makeSystemEvents() -> FakeSystemEvents {
        FakeSystemEvents([
            WindowInfo(number: 10, ownerPID: 1, ownerName: "Claude", frame: other),
            WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: CGRect(x: 185, y: 83, width: 656, height: 422))
        ])
    }

    private func makeMover(_ systemEvents: FakeSystemEvents) -> SystemEventsWindowMover {
        let client = SystemEventsWindowMover.Client(
            windowFrames: { try systemEvents.windowFrames(pid: $0) },
            perform: { try systemEvents.perform($0, pid: $1, expected: $2, target: $3) }
        )
        var mover = SystemEventsWindowMover(client: client, readWindows: { systemEvents.read() })
        mover.settleDelay = .zero
        return mover
    }

    /// サイズ変更 → 移動の順に、毎回いまの位置と大きさを添えて頼む。負の座標にも置ける。大きさがそろえば 2 回目のサイズ変更は省く
    @Test
    func resizesThenMovesToNegativeOrigin() async throws {
        let systemEvents = makeSystemEvents()
        let outcome = try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        #expect(outcome == .placed)
        #expect(systemEvents.frame(of: 20) == target)
        #expect(systemEvents.frame(of: 10) == other)
        #expect(systemEvents.requests == [
            .init(operation: .resize, pid: 2, expected: CGRect(x: 185, y: 83, width: 656, height: 422), target: target),
            .init(operation: .move, pid: 2, expected: CGRect(x: 185, y: 83, width: 864, height: 1085), target: target)
        ])
    }

    /// すでに枠どおりなら、何も頼まない
    @Test
    func skipsWindowAlreadyInPlace() async throws {
        let systemEvents = FakeSystemEvents([WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: target)])
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .placed)
        #expect(systemEvents.requests.isEmpty)
    }

    /// 同じ位置と大きさのウィンドウがほかのアプリにあっても、動かすウィンドウのプロセスにだけ頼む
    @Test
    func asksOnlyOwnerProcess() async throws {
        let frame = CGRect(x: 185, y: 83, width: 656, height: 422)
        let systemEvents = FakeSystemEvents([
            WindowInfo(number: 10, ownerPID: 1, ownerName: "Claude", frame: frame),
            WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: frame)
        ])
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .placed)
        #expect(systemEvents.frame(of: 10) == frame)
        #expect(systemEvents.requests.allSatisfy { $0.pid == 2 })
    }

    /// 一覧を読んでから頼むまでに位置が変わって合うウィンドウが無かったら、何も動かさずに読み直して続ける
    @Test
    func retriesWhenFrameChanges() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.nudgeBeforeCalls = 1
        let outcome = try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        #expect(outcome == .placed)
        #expect(systemEvents.frame(of: 10) == other)
        #expect(systemEvents.requests.map(\.expected) == [
            CGRect(x: 185, y: 83, width: 656, height: 422),
            CGRect(x: 225, y: 83, width: 656, height: 422),
            CGRect(x: 225, y: 83, width: 864, height: 1085)
        ])
    }

    /// 合うウィンドウが見つからないまま試す回数を超えたら、動かさずに諦める
    @Test
    func givesUpWhenNeverMatches() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.performError = .noSuchWindow
        let outcome = try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        #expect(outcome == .notMoved)
        #expect(systemEvents.requests.count == 3)
        #expect(systemEvents.frame(of: 20) == CGRect(x: 185, y: 83, width: 656, height: 422))
    }

    /// 動かしている間にウィンドウが閉じられたら、閉じられたと返す
    @Test
    func reportsWindowClosedDuringMove() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.closesWindowOnCall = 20
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .disappeared)
        #expect(systemEvents.frame(of: 10) == other)
    }

    /// アプリの最小サイズやメニューバーの下に収める調整で枠どおりにならなかったら、実際の位置と大きさを返す
    @Test
    func reportsAdjustedFrame() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.minimumWidth = 900
        systemEvents.minimumY = 40
        let outcome = try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        #expect(outcome == .adjusted(CGRect(x: -1728, y: 40, width: 900, height: 1085)))
    }

    /// アクセシビリティの許可が無いと分かったら、動かす前にそのエラーを投げる
    @Test
    func throwsWhenAccessibilityIsDenied() async {
        let systemEvents = makeSystemEvents()
        systemEvents.readError = .accessibilityNotPermitted
        await #expect(throws: SystemEventsWindowMover.Failure.accessibilityNotPermitted) {
            try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        }
        #expect(systemEvents.requests.isEmpty)
    }

    /// 同じプロセスに同じ位置と大きさのウィンドウがほかにもあると、どれが動くか分からないので動かさない
    @Test
    func refusesWhenSameFrameWindowsOverlap() async throws {
        let frame = CGRect(x: 185, y: 83, width: 656, height: 422)
        let systemEvents = FakeSystemEvents([
            WindowInfo(number: 20, ownerPID: 2, ownerName: "テキストエディット", frame: frame),
            WindowInfo(number: 21, ownerPID: 2, ownerName: "テキストエディット", frame: frame)
        ])
        #expect(try await makeMover(systemEvents).move(windowNumber: 21, to: target) == .notMoved)
        #expect(systemEvents.requests.isEmpty)
        #expect(systemEvents.frame(of: 20) == frame)
        #expect(systemEvents.frame(of: 21) == frame)
    }

    /// しまってあるウィンドウが同じ位置と大きさのときも、画面の一覧には出ないが System Events は選びうるので動かさない
    @Test
    func refusesWhenMinimizedWindowHasSameFrame() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.minimizedFrames = [2: [CGRect(x: 185, y: 83, width: 656, height: 422)]]
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .notMoved)
        #expect(systemEvents.requests.isEmpty)
    }

    /// 移動のときに画面の端で縮められたら、最後にもう一度大きさをそろえる
    @Test
    func resizesAgainWhenMoveShrinks() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.shrinksOnMoveTo = CGSize(width: 800, height: 1000)
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .placed)
        #expect(systemEvents.requests.map(\.operation) == [.resize, .move, .resize])
        #expect(systemEvents.requests.last?.expected == CGRect(x: -1728, y: 32, width: 800, height: 1000))
    }

    /// 頼んでいる間にウィンドウが閉じられたら、返ってきたエラーの種類に関係なく、閉じられたと返す
    @Test
    func reportsWindowClosedEvenWhenErrorDiffers() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.closesWindowOnCall = 20
        systemEvents.performError = .failed("エラー -10000")
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .disappeared)
    }

    /// 動かしていない別のエラーは、そのまま投げる
    @Test
    func rethrowsOtherErrors() async {
        let systemEvents = makeSystemEvents()
        systemEvents.performError = .timedOut
        await #expect(throws: SystemEventsWindowMover.Failure.timedOut) {
            try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        }
    }

    /// -1719 が返っても、一覧を読めるなら許可はあるので、合うウィンドウが無かったとみなして続ける
    @Test
    func treatsIllegalIndexAsMismatchWhenReadable() async throws {
        let systemEvents = makeSystemEvents()
        systemEvents.performError = .accessibilityNotPermitted
        #expect(try await makeMover(systemEvents).move(windowNumber: 20, to: target) == .notMoved)
        #expect(systemEvents.requests.count == 3)
    }

    /// オートメーションの許可が無いときは、読み直さずにそのまま投げる
    @Test
    func throwsWhenAutomationIsDenied() async {
        let systemEvents = makeSystemEvents()
        systemEvents.performError = .automationNotPermitted
        await #expect(throws: SystemEventsWindowMover.Failure.automationNotPermitted) {
            try await makeMover(systemEvents).move(windowNumber: 20, to: target)
        }
        #expect(systemEvents.requests.count == 1)
    }

    /// Apple Events のエラー番号を、許可が無い・System Events が動いていない などに分ける
    @Test
    func classifiesErrors() {
        typealias Failure = SystemEventsWindowMover.Failure
        #expect(Failure.from(code: -1743, message: "") == .automationNotPermitted)
        #expect(Failure.from(code: -1744, message: "") == .automationNotPermitted)
        #expect(Failure.from(code: -1719, message: "") == .accessibilityNotPermitted)
        #expect(Failure.from(code: -25211, message: "") == .accessibilityNotPermitted)
        #expect(Failure.from(code: -600, message: "") == .systemEventsUnavailable)
        #expect(Failure.from(code: -609, message: "") == .systemEventsUnavailable)
        #expect(Failure.from(code: -1712, message: "") == .timedOut)
        #expect(Failure.from(code: -1728, message: "") == .noSuchWindow)
        #expect(Failure.from(code: -10000, message: "ハンドラが失敗しました") == .failed("ハンドラが失敗しました"))
        #expect(Failure.from(code: -50, message: "") == .failed("エラー -50"))
    }
}

struct SystemEventsTests {
    private func list(_ pairs: [(Int32, Int32)]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (first, second) in pairs {
            let item = NSAppleEventDescriptor.list()
            item.insert(NSAppleEventDescriptor(int32: first), at: 0)
            item.insert(NSAppleEventDescriptor(int32: second), at: 0)
            list.insert(item, at: 0)
        }
        return list
    }

    /// `position of every window` と `size of every window` の返事を、ウィンドウごとの位置と大きさにする
    @Test
    func readsFramesFromReply() {
        let frames = SystemEvents.frames(positions: list([(-1728, 32), (100, 200)]), sizes: list([(864, 1085), (300, 400)]))
        #expect(frames == [CGRect(x: -1728, y: 32, width: 864, height: 1085), CGRect(x: 100, y: 200, width: 300, height: 400)])
        #expect(SystemEvents.frames(positions: nil, sizes: nil).isEmpty)
    }

    /// 位置と大きさは、丸めた整数の組で渡す
    @Test
    func encodesPairAsIntegers() {
        let pair = SystemEvents.pair(-1727.6, 32.2)
        #expect(pair.numberOfItems == 2)
        #expect(pair.atIndex(1)?.int32Value == -1728)
        #expect(pair.atIndex(2)?.int32Value == 32)
        #expect(SystemEvents.pair(.infinity, -1e12).atIndex(1)?.int32Value == 0)
        #expect(SystemEvents.pair(.infinity, -1e12).atIndex(2)?.int32Value == Int32.min)
    }

    /// 動かすウィンドウは「pid のプロセスの、位置と大きさが一致する最初のウィンドウ」で指す
    @Test
    func specifiesWindowByFrameInProcess() throws {
        let code = CompanionShortcut.code
        let window = SystemEvents.window(matching: CGRect(x: -1728, y: 32, width: 864, height: 1085), of: SystemEvents.process(pid: 42))
        #expect(window.descriptorType == code("obj "))
        #expect(window.forKeyword(code("form"))?.enumCodeValue == code("indx"))
        let filtered = try #require(window.forKeyword(code("from")))
        #expect(filtered.forKeyword(code("want"))?.typeCodeValue == code("cwin"))
        #expect(filtered.forKeyword(code("form"))?.enumCodeValue == code("test"))
        let logical = try #require(filtered.forKeyword(code("seld")))
        #expect(logical.descriptorType == code("logi"))
        #expect(logical.forKeyword(code("logc"))?.enumCodeValue == code("AND "))
        let terms = try #require(logical.forKeyword(code("term")))
        #expect(terms.numberOfItems == 2)
        for (offset, property, first) in [(1, "posn", Int32(-1728)), (2, "ptsz", Int32(864))] {
            let term = try #require(terms.atIndex(offset))
            #expect(term.descriptorType == code("cmpd"))
            #expect(term.forKeyword(code("relo"))?.enumCodeValue == code("=   "))
            #expect(term.forKeyword(code("obj1"))?.forKeyword(code("seld"))?.typeCodeValue == code(property))
            #expect(term.forKeyword(code("obj1"))?.forKeyword(code("from"))?.descriptorType == code("exmn"))
            #expect(term.forKeyword(code("obj2"))?.atIndex(1)?.int32Value == first)
        }
        let process = try #require(filtered.forKeyword(code("from")))
        #expect(process.forKeyword(code("form"))?.enumCodeValue == code("indx"))
        let processTest = try #require(process.forKeyword(code("from"))?.forKeyword(code("seld")))
        #expect(processTest.descriptorType == code("cmpd"))
        #expect(processTest.forKeyword(code("obj1"))?.forKeyword(code("seld"))?.typeCodeValue == code("idux"))
        #expect(processTest.forKeyword(code("obj2"))?.int32Value == 42)
    }

    /// System Events が動いていなくて届かなかったら、起動してから送り直す
    @Test
    func launchesAndResendsWhenUnavailable() async throws {
        nonisolated(unsafe) var attempts = 0
        nonisolated(unsafe) var launched = false
        let reply = try await SystemEvents.sendLaunchingIfNeeded(retries: 3, retryDelay: .zero) {
            attempts += 1
            guard launched, attempts >= 3 else { throw SystemEventsWindowMover.Failure.systemEventsUnavailable }
            return "ok"
        } launch: {
            launched = true
        }
        #expect(reply == "ok")
        #expect(attempts == 3)
    }
}
