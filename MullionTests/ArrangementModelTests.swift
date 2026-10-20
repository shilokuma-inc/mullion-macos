//
//  ArrangementModelTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

/// どちらの手段で、どのウィンドウを動かすよう頼まれたかを記録する
nonisolated private final class MoveRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var shortcutMoves: [Int] = []
    private(set) var systemEventsMoves: [Int] = []
    var shortcutError: (any Error)?
    var systemEventsError: (any Error)?
    var systemEventsOutcome = WindowMover.Outcome.placed

    func movers(windows: [WindowInfo]) -> WindowMovers {
        WindowMovers(
            readWindows: { windows },
            shortcut: { number, _ in
                try self.record(number, error: self.shortcutError, outcome: .placed) { $0.shortcutMoves.append(number) }
            },
            systemEvents: { number, _ in
                try self.record(number, error: self.systemEventsError, outcome: self.systemEventsOutcome) {
                    $0.systemEventsMoves.append(number)
                }
            }
        )
    }

    private func record(
        _ number: Int,
        error: (any Error)?,
        outcome: WindowMover.Outcome,
        append: (MoveRecorder) -> Void
    ) throws -> WindowMover.Outcome {
        try lock.withLock {
            append(self)
            if let error { throw error }
            return outcome
        }
    }
}

struct ArrangementModelTests {
    private let wide = ScreenInfo(
        id: "LG",
        name: "LG ULTRAWIDE",
        frame: CGRect(x: 1728, y: 0, width: 2560, height: 1080),
        usableFrame: CGRect(x: 1728, y: 30, width: 2560, height: 994)
    )
    private let small = ScreenInfo(
        id: "LG",
        name: "LG ULTRAWIDE",
        frame: CGRect(x: 1728, y: 0, width: 1280, height: 720),
        usableFrame: CGRect(x: 1728, y: 30, width: 1280, height: 690)
    )

    private func makeDefaults() throws -> UserDefaults {
        let name = "MullionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// 保存していない画面は 3 列
    @Test
    func defaultsToThreeColumns() throws {
        let model = ArrangementModel(defaults: try makeDefaults())
        #expect(model.maxColumns(for: wide) == 7)
        #expect(model.maxRows(for: wide) == 3)
        #expect(model.layout(for: wide) == .columns(3))
    }

    /// 画面ごとの分け方は保存され、次に起動したときも使われる
    @Test
    func savesLayoutPerScreen() throws {
        let defaults = try makeDefaults()
        let model = ArrangementModel(defaults: defaults)
        model.setColumnCount(5, for: wide)
        model.setRowCount(2, forColumn: 1, on: wide)
        #expect(model.layout(for: wide).rowCounts == [1, 2, 1, 1, 1])
        #expect(ArrangementModel(defaults: defaults).layout(for: wide).rowCounts == [1, 2, 1, 1, 1])
    }

    /// 上限を超える指定は上限に収める。同じ画面が小さくなったら（解像度の変更など）、保存した分け方も切り詰めて使う
    @Test
    func keepsLayoutWithinLimits() throws {
        let model = ArrangementModel(defaults: try makeDefaults())
        model.setColumnCount(10, for: wide)
        model.setRowCount(9, forColumn: 0, on: wide)
        #expect(model.layout(for: wide).rowCounts == [3, 1, 1, 1, 1, 1, 1])
        #expect(model.layout(for: small).rowCounts == [2, 1, 1])
    }

    @Test
    func summarizesReport() {
        #expect(ArrangeReport().summary == "この画面に並べるウィンドウがありません。")
        #expect(ArrangeReport(placed: 4, adjusted: 1, leftovers: 2).summary
            == "5 枚を並べました。うち 1 枚はアプリの最小サイズなどの都合で枠どおりになっていません。2 枚は枠が足りないため動かしていません。")
        #expect(ArrangeReport(placed: 1, failure: "止めました").summary == "1 枚を並べました。止めました。")
    }

    // MARK: - 並べる手段の振り分け

    /// メイン画面の左にある内蔵ディスプレイ
    private let leftScreen = ScreenInfo(
        id: "BuiltIn",
        name: "内蔵ディスプレイ",
        frame: CGRect(x: -1728, y: 0, width: 1728, height: 1117),
        usableFrame: CGRect(x: -1728, y: 32, width: 1728, height: 1085)
    )
    private let windows = [
        WindowInfo(number: 1, ownerPID: 101, ownerName: "テキストエディット", frame: CGRect(x: -1500, y: 200, width: 600, height: 400)),
        WindowInfo(number: 2, ownerPID: 102, ownerName: "メモ", frame: CGRect(x: 2000, y: 200, width: 600, height: 400))
    ]

    /// 左か上にある画面のウィンドウは System Events で、届く画面のウィンドウはショートカットで動かす
    @Test
    func choosesMoverByScreen() async throws {
        let recorder = MoveRecorder()
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: windows))
        await model.arrange(on: leftScreen)
        #expect(recorder.systemEventsMoves == [1])
        #expect(recorder.shortcutMoves.isEmpty)
        #expect(model.systemEventsStatus == .ready)
        #expect(model.shortcutStatus == .unchecked)
        #expect(model.reports[leftScreen.id]?.placed == 1)

        await model.arrange(on: wide)
        #expect(recorder.shortcutMoves == [2])
        #expect(recorder.systemEventsMoves == [1])
        #expect(model.shortcutStatus == .ready)
    }

    /// System Events の許可が無いと分かったら、System Events の状態にだけ反映し、理由を結果に出す
    @Test
    func reportsSystemEventsPermission() async throws {
        let recorder = MoveRecorder()
        recorder.systemEventsError = SystemEventsWindowMover.Failure.accessibilityNotPermitted
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: windows))
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .accessibilityNotPermitted)
        #expect(model.shortcutStatus == .unchecked)
        #expect(model.reports[leftScreen.id]?.failure == "Mullion にアクセシビリティの許可が無いため止めました")

        recorder.systemEventsError = SystemEventsWindowMover.Failure.automationNotPermitted
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .automationNotPermitted)
        #expect(model.reports[leftScreen.id]?.failure == "Mullion に System Events の操作が許可されていないため止めました")

        recorder.systemEventsError = SystemEventsWindowMover.Failure.timedOut
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .failed("System Events が応答しないため止めました。許可の確認が出ていないか見てください"))
    }

    /// ショートカットの失敗は、System Events の状態を変えない
    @Test
    func keepsSystemEventsStatusOnShortcutFailure() async throws {
        let recorder = MoveRecorder()
        recorder.shortcutError = CompanionShortcut.Failure.notPermitted
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: windows))
        await model.arrange(on: wide)
        #expect(model.shortcutStatus == .notPermitted)
        #expect(model.systemEventsStatus == .unchecked)
        #expect(model.reports[wide.id]?.failure == "Mullion にショートカットの実行が許可されていないため止めました")
    }

    /// 許可を出したあとに並べ直したら、動かせなかったウィンドウしか無くても「使える」に戻す（許可が無いままの案内を出し続けない）
    @Test
    func clearsPermissionProblemAfterRetry() async throws {
        let recorder = MoveRecorder()
        recorder.systemEventsError = SystemEventsWindowMover.Failure.accessibilityNotPermitted
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: windows))
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .accessibilityNotPermitted)

        recorder.systemEventsError = nil
        recorder.systemEventsOutcome = .notMoved
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .ready)
        #expect(model.reports[leftScreen.id]?.notMoved == 1)
    }

    /// 並べるウィンドウが無ければ System Events に頼まないので、状態も変えない
    @Test
    func keepsStatusWhenNothingToArrange() async throws {
        let recorder = MoveRecorder()
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: []))
        await model.arrange(on: leftScreen)
        #expect(model.systemEventsStatus == .unchecked)
        #expect(recorder.systemEventsMoves.isEmpty)
    }

    /// メイン画面の上にある画面も System Events で動かし、1 枚目で許可が無いと分かったら残りは頼まない
    @Test
    func stopsAtFirstFailureOnUpperScreen() async throws {
        let upper = ScreenInfo(
            id: "Upper",
            name: "上の画面",
            frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
            usableFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        )
        let recorder = MoveRecorder()
        recorder.systemEventsError = SystemEventsWindowMover.Failure.automationNotPermitted
        let upperWindows = [
            WindowInfo(number: 5, ownerPID: 101, ownerName: "テキストエディット", frame: CGRect(x: 100, y: -900, width: 600, height: 400)),
            WindowInfo(number: 6, ownerPID: 102, ownerName: "メモ", frame: CGRect(x: 900, y: -900, width: 600, height: 400))
        ]
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: upperWindows))
        await model.arrange(on: upper)
        #expect(recorder.systemEventsMoves == [5])
        #expect(recorder.shortcutMoves.isEmpty)
        #expect(model.systemEventsStatus == .automationNotPermitted)
    }

    /// 画面の配置を変えて動かし方が変わった画面は、前の結果（許可が無くて止めた、など）を消す。変わっていない画面の結果は残す
    @Test
    func clearsReportWhenReachabilityChanges() async throws {
        nonisolated(unsafe) var current = [leftScreen, wide]
        let recorder = MoveRecorder()
        recorder.systemEventsError = SystemEventsWindowMover.Failure.accessibilityNotPermitted
        let model = ArrangementModel(defaults: try makeDefaults(), movers: recorder.movers(windows: windows), currentScreens: { current })
        model.reload()
        await model.arrange(on: leftScreen)
        await model.arrange(on: wide)
        #expect(model.reports[leftScreen.id]?.failure != nil)

        // 内蔵ディスプレイをメイン画面の右に置き直した
        let movedRight = ScreenInfo(
            id: leftScreen.id,
            name: leftScreen.name,
            frame: CGRect(x: 4288, y: 0, width: 1728, height: 1117),
            usableFrame: CGRect(x: 4288, y: 32, width: 1728, height: 1085)
        )
        current = [movedRight, wide]
        model.reload()
        #expect(model.screens == [movedRight, wide])
        #expect(model.reports[leftScreen.id] == nil)
        #expect(model.reports[wide.id] != nil)
    }
}
