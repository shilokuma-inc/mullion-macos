//
//  ArrangementModelTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

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
}
