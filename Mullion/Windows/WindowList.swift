//
//  WindowList.swift
//  Mullion
//

import CoreGraphics

/// 画面に表示されているウィンドウ 1 枚の情報
nonisolated struct WindowInfo: Equatable, Sendable {
    /// ウィンドウサーバーでの番号（kCGWindowNumber）。並べている間にウィンドウを見分けるのに使う
    let number: Int
    let ownerPID: pid_t
    let ownerName: String
    /// メイン画面の左上を原点とし、y が下に向かって増える座標
    let frame: CGRect
}

/// 画面に表示されているウィンドウの一覧を、ウィンドウサーバーから読む。
/// 位置と大きさを読むだけなら、App Sandbox の中でも権限は要らない（ウィンドウのタイトルは画面収録の権限が無いと読めない）
nonisolated enum WindowList {
    /// これより小さいウィンドウは数えない。CGWindowList は、アプリが画面の外に置いている細い補助パネルなども返すが、
    /// ショートカットの「ウィンドウを検索」はそれらを数えないため、番号を合わせるために除く
    static let minimumSize = CGSize(width: 120, height: 80)

    /// 手前から順に、画面に表示されている通常のウィンドウを返す。
    /// ショートカットの「ウィンドウを検索」（絞り込みなし）が返す並びと同じで、index + 1 がショートカットに渡す番号になる
    static func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows(from: entries)
    }

    /// 各画面のメニューバーの位置と大きさ。ウィンドウサーバーがメニューバーのレイヤーに画面ごとに 1 枚ずつ置いている
    static func menuBarFrames() -> [CGRect] {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return menuBarFrames(from: entries)
    }

    static func menuBarFrames(from entries: [[String: Any]]) -> [CGRect] {
        let menuBarLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        return entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == menuBarLevel,
                  (entry[kCGWindowOwnerName as String] as? String) == "Window Server",
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any]
            else {
                return nil
            }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }

    /// CGWindowListCopyWindowInfo の結果から、通常のウィンドウ（レイヤー 0・不透明度 0 より大・最小サイズ以上）を取り出す
    static func windows(from entries: [[String: Any]]) -> [WindowInfo] {
        entries.compactMap { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let number = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= minimumSize.width,
                  frame.height >= minimumSize.height
            else {
                return nil
            }
            return WindowInfo(
                number: number,
                ownerPID: pid_t(pid),
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "",
                frame: frame
            )
        }
    }
}
