//
//  SplitLimit.swift
//  Mullion
//

import CoreGraphics

/// 画面を分割できる上限。ウィンドウを置ける範囲を、1 マスの最小サイズで割って決める
struct SplitLimit: Equatable {
    /// ターミナル（Ayuthaya 12pt）で約 46 桁 × 16 行が入る大きさ。
    /// 1 文字 7.2pt・1 行 17pt と、ウィンドウの枠（横 4pt・縦 48pt）の実測から決めた
    static let standard = SplitLimit(minimumCellSize: CGSize(width: 340, height: 320))

    /// 1 マスの最小サイズ（pt）
    let minimumCellSize: CGSize

    /// 幅 width を分けられる列数の上限。最小サイズより狭くても 1 列は残す
    func maxColumns(forWidth width: CGFloat) -> Int {
        Self.count(of: minimumCellSize.width, in: width)
    }

    /// 高さ height を分けられる行数の上限。最小サイズより低くても 1 行は残す
    func maxRows(forHeight height: CGFloat) -> Int {
        Self.count(of: minimumCellSize.height, in: height)
    }

    private static func count(of minimum: CGFloat, in length: CGFloat) -> Int {
        guard minimum > 0, length > 0 else { return 1 }
        return max(1, Int((length / minimum).rounded(.down)))
    }
}
