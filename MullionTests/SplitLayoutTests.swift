//
//  SplitLayoutTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

struct SplitLimitTests {
    /// 340 × 320 pt で割った上限（端数は切り捨て）
    @Test(arguments: [
        (CGSize(width: 1920, height: 1080), 5, 3),
        (CGSize(width: 2056, height: 1234), 6, 3),
        (CGSize(width: 2560, height: 994), 7, 3),
        (CGSize(width: 1470, height: 920), 4, 2),
        (CGSize(width: 680, height: 640), 2, 2)
    ])
    func standardLimit(size: CGSize, columns: Int, rows: Int) {
        let limit = SplitLimit.standard
        #expect(limit.maxColumns(forWidth: size.width) == columns)
        #expect(limit.maxRows(forHeight: size.height) == rows)
    }

    /// 最小サイズより狭い・低い画面でも 1 列・1 段は残す
    @Test
    func keepsAtLeastOne() {
        let limit = SplitLimit.standard
        #expect(limit.maxColumns(forWidth: 200) == 1)
        #expect(limit.maxRows(forHeight: 0) == 1)
    }
}

struct SplitLayoutTests {
    @Test
    func columnsHaveOneRowEach() {
        let layout = SplitLayout.columns(4)
        #expect(layout.rowCounts == [1, 1, 1, 1])
        #expect(layout.columnCount == 4)
        #expect(layout.slotCount == 4)
    }

    /// 列が無い・行数が 1 未満の指定は、1 に直す
    @Test
    func sanitizesInvalidCounts() {
        #expect(SplitLayout(rowCounts: []).rowCounts == [1])
        #expect(SplitLayout(rowCounts: [0, 2, -1]).rowCounts == [1, 2, 1])
        #expect(SplitLayout.columns(0).rowCounts == [1])
    }

    /// 列数を変えても、残る列の段数はそのまま。増えた列は上下に分けない
    @Test
    func changingColumnCountKeepsRows() {
        var layout = SplitLayout(rowCounts: [2, 1, 3])
        layout.setColumnCount(5)
        #expect(layout.rowCounts == [2, 1, 3, 1, 1])
        layout.setColumnCount(2)
        #expect(layout.rowCounts == [2, 1])
    }

    @Test
    func changingRowCount() {
        var layout = SplitLayout.columns(3)
        layout.setRowCount(2, forColumn: 1)
        layout.setRowCount(3, forColumn: 5)
        #expect(layout.rowCounts == [1, 2, 1])
        #expect(layout.slotCount == 4)
    }

    /// 画面が狭くなったら、上限に収まるよう列と段を切り詰める
    @Test
    func clampsToLimits() {
        let layout = SplitLayout(rowCounts: [3, 1, 2, 1, 1])
        #expect(layout.clamped(maxColumns: 3, maxRows: 2).rowCounts == [2, 1, 2])
        #expect(layout.clamped(maxColumns: 0, maxRows: 0).rowCounts == [1])
    }

    /// 枠は左の列から、列の中は上から順に並ぶ
    @Test
    func framesAreOrderedByColumnThenRow() {
        let layout = SplitLayout(rowCounts: [1, 2])
        let frames = layout.frames(in: CGRect(x: 100, y: 30, width: 1000, height: 600))
        #expect(frames == [
            CGRect(x: 100, y: 30, width: 500, height: 600),
            CGRect(x: 600, y: 30, width: 500, height: 300),
            CGRect(x: 600, y: 330, width: 500, height: 300)
        ])
    }

    /// 割り切れない幅でも、境目は整数で、隣り合う枠に隙間も重なりも無く、全体を埋める
    @Test
    func framesTileWithoutGaps() {
        let rect = CGRect(x: 1728, y: 30, width: 2560, height: 994)
        let frames = SplitLayout(rowCounts: [1, 3, 1, 1, 1, 1, 2]).frames(in: rect)
        let topRow = frames.filter { $0.minY == rect.minY }.sorted { $0.minX < $1.minX }
        #expect(topRow.count == 7)
        #expect(topRow.first?.minX == rect.minX)
        #expect(topRow.last?.maxX == rect.maxX)
        for (left, right) in zip(topRow, topRow.dropFirst()) {
            #expect(left.maxX == right.minX)
        }
        #expect(frames.allSatisfy { $0.minX == $0.minX.rounded() && $0.width == $0.width.rounded() })
        let secondColumn = frames.filter { $0.minX == topRow[1].minX }
        #expect(secondColumn.map(\.minY) == [30, 361, 693])
        #expect(secondColumn.last?.maxY == rect.maxY)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let layout = SplitLayout(rowCounts: [1, 2, 1])
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(SplitLayout.self, from: data) == layout)
    }
}
