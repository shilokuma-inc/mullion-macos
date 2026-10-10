//
//  ScreenGeometry.swift
//  Mullion
//

import CoreGraphics

/// AppKit（NSScreen）の座標と、ウィンドウサーバー（CGWindowList・ショートカット）の座標の変換と、ウィンドウを置ける範囲の計算
enum ScreenGeometry {
    /// AppKit の座標（メイン画面の左下が原点で y は上向き）の rect を、
    /// ウィンドウサーバーの座標（メイン画面の左上が原点で y は下向き）に変える。primaryHeight はメイン画面の高さ
    static func topLeftRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// ウィンドウを置ける範囲。NSScreen.visibleFrame から、さらにメニューバーと重なる上の部分を除く。
    /// メイン画面以外のメニューバーは visibleFrame から除かれていないことがあり、そのまま使うとウィンドウがメニューバーの下に押し下げられて
    /// 下の枠と重なる（macOS 26 で確認）。座標はいずれもウィンドウサーバーの座標
    static func usableFrame(visibleFrame: CGRect, menuBars: [CGRect]) -> CGRect {
        let top = menuBars
            .filter { $0.intersects(visibleFrame) && $0.minY <= visibleFrame.minY }
            .map(\.maxY)
            .max() ?? visibleFrame.minY
        guard top > visibleFrame.minY else { return visibleFrame }
        return CGRect(
            x: visibleFrame.minX,
            y: top,
            width: visibleFrame.width,
            height: max(0, visibleFrame.maxY - top)
        )
    }

    /// ショートカットの「ウィンドウを移動」は負の座標を受け付けない（メイン画面より左や上の画面には移動できない）
    static func isReachable(_ rect: CGRect) -> Bool {
        rect.minX >= 0 && rect.minY >= 0
    }
}
