//
//  ArrangementPlanner.swift
//  Mullion
//

import CoreGraphics

/// ウィンドウ 1 枚を置く先
struct WindowPlacement: Equatable {
    let window: WindowInfo
    /// メイン画面の左上を原点とする座標
    let frame: CGRect
}

/// 画面にあるウィンドウを、分け方の枠に割り当てる
enum ArrangementPlanner {
    /// 割り当ての結果
    struct Plan: Equatable {
        var placements: [WindowPlacement]
        /// 枠が足りずに置けなかったウィンドウ
        var leftovers: [WindowInfo]
    }

    /// screenFrame（画面全体）の上にあるウィンドウを、今の位置の左から順（同じ列なら上から順）に並べ、
    /// slots（左の列から、列の中は上から順の枠）へ順に割り当てる。今の並びをなるべく崩さずに整えるため
    static func plan(windows: [WindowInfo], on screenFrame: CGRect, slots: [CGRect]) -> Plan {
        let sorted = windows
            .filter { screenFrame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .sorted { lhs, rhs in
                let left = (lhs.frame.minX.rounded(), lhs.frame.minY.rounded(), lhs.number)
                let right = (rhs.frame.minX.rounded(), rhs.frame.minY.rounded(), rhs.number)
                return left < right
            }
        return Plan(
            placements: zip(sorted, slots).map { WindowPlacement(window: $0, frame: $1) },
            leftovers: Array(sorted.dropFirst(slots.count))
        )
    }
}
