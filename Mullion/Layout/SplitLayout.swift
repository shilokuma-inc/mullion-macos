//
//  SplitLayout.swift
//  Mullion
//

import CoreGraphics

/// 画面の分け方。左の列から順に、列ごとの行数（上下にいくつに分けるか）を持つ
struct SplitLayout: Codable, Equatable {
    /// 左の列から順に並べた、列ごとの行数。列は 1 つ以上、行数は 1 以上
    private(set) var rowCounts: [Int]

    /// rowCounts が空なら 1 列、1 未満の行数は 1 として扱う
    init(rowCounts: [Int]) {
        self.rowCounts = rowCounts.isEmpty ? [1] : rowCounts.map { max(1, $0) }
    }

    /// どの列も上下に分けない、count 列の分け方
    static func columns(_ count: Int) -> SplitLayout {
        SplitLayout(rowCounts: Array(repeating: 1, count: max(1, count)))
    }

    var columnCount: Int {
        rowCounts.count
    }

    /// 枠の数（ウィンドウを置ける数）
    var slotCount: Int {
        rowCounts.reduce(0, +)
    }

    /// 列数を変える。残る列の行数はそのままにし、増えた列は上下に分けない
    mutating func setColumnCount(_ count: Int) {
        let count = max(1, count)
        if count < rowCounts.count {
            rowCounts.removeLast(rowCounts.count - count)
        } else {
            rowCounts += Array(repeating: 1, count: count - rowCounts.count)
        }
    }

    /// column 列目（0 始まり）の行数を変える
    mutating func setRowCount(_ count: Int, forColumn column: Int) {
        guard rowCounts.indices.contains(column) else { return }
        rowCounts[column] = max(1, count)
    }

    /// 上限に収まるよう、列数と各列の行数を切り詰めた分け方
    func clamped(maxColumns: Int, maxRows: Int) -> SplitLayout {
        let maxRows = max(1, maxRows)
        return SplitLayout(rowCounts: rowCounts.prefix(max(1, maxColumns)).map { min($0, maxRows) })
    }

    /// rect を分けた枠を、左の列から、列の中は上から順に返す。座標系は rect と同じで、y は下に向かって増えるものとする。
    /// 隣り合う枠の境目に 1pt の隙間や重なりが出ないよう、境目の位置を整数に丸めてから幅と高さを決める
    func frames(in rect: CGRect) -> [CGRect] {
        let columnEdges = Self.edges(from: rect.minX, length: rect.width, count: rowCounts.count)
        return rowCounts.indices.flatMap { column in
            let rowEdges = Self.edges(from: rect.minY, length: rect.height, count: rowCounts[column])
            return (0..<rowCounts[column]).map { row in
                CGRect(
                    x: columnEdges[column],
                    y: rowEdges[row],
                    width: columnEdges[column + 1] - columnEdges[column],
                    height: rowEdges[row + 1] - rowEdges[row]
                )
            }
        }
    }

    /// start から length を count 等分した境目（count + 1 個）
    private static func edges(from start: CGFloat, length: CGFloat, count: Int) -> [CGFloat] {
        (0...count).map { index in
            (start + length * CGFloat(index) / CGFloat(count)).rounded()
        }
    }
}
