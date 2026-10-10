//
//  WindowListTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

struct ScreenGeometryTests {
    /// AppKit の座標（左下が原点）を、ウィンドウサーバーの座標（左上が原点）に変える
    @Test
    func convertsAppKitRectToTopLeftOrigin() {
        // メイン画面（高さ 1117）の右に、少し下げて置いた 2560 × 1080 の画面
        let external = CGRect(x: 1728, y: 37, width: 2560, height: 1080)
        #expect(ScreenGeometry.topLeftRect(fromAppKit: external, primaryHeight: 1117) == CGRect(x: 1728, y: 0, width: 2560, height: 1080))
        let main = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        #expect(ScreenGeometry.topLeftRect(fromAppKit: main, primaryHeight: 1117) == CGRect(x: 0, y: 33, width: 1728, height: 1084))
    }

    /// メイン画面以外では visibleFrame にメニューバーが含まれていることがあるので、その分を除く
    @Test
    func excludesMenuBarMissingFromVisibleFrame() {
        let visible = CGRect(x: 1728, y: 0, width: 2560, height: 1024)
        let menuBars = [CGRect(x: 0, y: 0, width: 1728, height: 33), CGRect(x: 1728, y: 0, width: 2560, height: 30)]
        #expect(ScreenGeometry.usableFrame(visibleFrame: visible, menuBars: menuBars) == CGRect(x: 1728, y: 30, width: 2560, height: 994))
    }

    /// visibleFrame がすでにメニューバーを除いているときは、そのまま
    @Test
    func keepsVisibleFrameThatAlreadyExcludesMenuBar() {
        let visible = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let menuBars = [CGRect(x: 0, y: 0, width: 1728, height: 33)]
        #expect(ScreenGeometry.usableFrame(visibleFrame: visible, menuBars: menuBars) == visible)
        #expect(ScreenGeometry.usableFrame(visibleFrame: visible, menuBars: []) == visible)
    }

    @Test
    func screensLeftOrAboveTheMainScreenAreUnreachable() {
        #expect(ScreenGeometry.isReachable(CGRect(x: 1728, y: 30, width: 2560, height: 994)))
        #expect(!ScreenGeometry.isReachable(CGRect(x: -1920, y: 30, width: 1920, height: 1050)))
        #expect(!ScreenGeometry.isReachable(CGRect(x: 0, y: -1080, width: 1920, height: 1050)))
    }
}

struct WindowListTests {
    private func entry(
        number: Int,
        pid: Int = 100,
        owner: String = "ターミナル",
        layer: Int = 0,
        alpha: Double = 1,
        frame: CGRect
    ) -> [String: Any] {
        [
            kCGWindowNumber as String: number,
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary
        ]
    }

    /// 通常のウィンドウだけを、並びを変えずに取り出す（ショートカットの「ウィンドウを検索」と番号を合わせるため）
    @Test
    func keepsOnlyRegularWindowsInOrder() {
        let entries = [
            entry(number: 1, frame: CGRect(x: 0, y: 33, width: 600, height: 400)),
            entry(number: 2, layer: 24, frame: CGRect(x: 0, y: 0, width: 1728, height: 33)),
            entry(number: 3, alpha: 0, frame: CGRect(x: 0, y: 33, width: 600, height: 400)),
            entry(number: 4, frame: CGRect(x: 485, y: 1182, width: 559, height: 22)),
            entry(number: 5, pid: 200, owner: "Slack", frame: CGRect(x: 10, y: 50, width: 955, height: 1030))
        ]
        let windows = WindowList.windows(from: entries)
        #expect(windows.map(\.number) == [1, 5])
        let slack = WindowInfo(number: 5, ownerPID: 200, ownerName: "Slack", frame: CGRect(x: 10, y: 50, width: 955, height: 1030))
        #expect(windows.last == slack)
    }

    @Test
    func findsMenuBarsOfEachScreen() {
        let entries = [
            entry(number: 1, owner: "Window Server", layer: 24, frame: CGRect(x: 0, y: 0, width: 1728, height: 33)),
            entry(number: 2, owner: "Window Server", layer: 24, frame: CGRect(x: 1728, y: 0, width: 2560, height: 30)),
            entry(number: 3, owner: "Window Server", layer: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            entry(number: 4, owner: "Dock", layer: 24, frame: CGRect(x: 0, y: 1000, width: 1728, height: 60))
        ]
        #expect(WindowList.menuBarFrames(from: entries) == [
            CGRect(x: 0, y: 0, width: 1728, height: 33),
            CGRect(x: 1728, y: 0, width: 2560, height: 30)
        ])
    }
}

struct ArrangementPlannerTests {
    private let screen = CGRect(x: 1728, y: 0, width: 2560, height: 1080)
    private let slots = SplitLayout.columns(3).frames(in: CGRect(x: 1728, y: 30, width: 2560, height: 994))

    private func window(_ number: Int, x: CGFloat, y: CGFloat = 30) -> WindowInfo {
        WindowInfo(number: number, ownerPID: 100, ownerName: "ターミナル", frame: CGRect(x: x, y: y, width: 400, height: 600))
    }

    /// 今の位置の左から順に、左の列の枠から割り当てる
    @Test
    func assignsWindowsFromLeftToRight() {
        let plan = ArrangementPlanner.plan(
            windows: [window(1, x: 3000), window(2, x: 1800), window(3, x: 2400)],
            on: screen,
            slots: slots
        )
        #expect(plan.placements.map(\.window.number) == [2, 3, 1])
        #expect(plan.placements.map(\.frame) == slots)
        #expect(plan.leftovers.isEmpty)
    }

    /// 左端がそろっているときは上から順
    @Test
    func breaksTiesFromTopToBottom() {
        let plan = ArrangementPlanner.plan(windows: [window(1, x: 1800, y: 500), window(2, x: 1800, y: 30)], on: screen, slots: slots)
        #expect(plan.placements.map(\.window.number) == [2, 1])
    }

    /// ほかの画面にあるウィンドウ（中心が画面の外）は対象にしない
    @Test
    func ignoresWindowsOnOtherScreens() {
        let plan = ArrangementPlanner.plan(windows: [window(1, x: 100), window(2, x: 2000)], on: screen, slots: slots)
        #expect(plan.placements.map(\.window.number) == [2])
    }

    /// 枠より多いウィンドウは動かさずに残す
    @Test
    func leavesWindowsBeyondTheSlots() {
        let windows = (1...5).map { window($0, x: 1728 + CGFloat($0) * 300) }
        let plan = ArrangementPlanner.plan(windows: windows, on: screen, slots: slots)
        #expect(plan.placements.map(\.window.number) == [1, 2, 3])
        #expect(plan.leftovers.map(\.number) == [4, 5])
    }
}
