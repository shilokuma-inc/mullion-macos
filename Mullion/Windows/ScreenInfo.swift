//
//  ScreenInfo.swift
//  Mullion
//

import AppKit

/// 接続している画面 1 つの情報。座標はいずれもウィンドウサーバーの座標（メイン画面の左上が原点で y は下向き）
struct ScreenInfo: Identifiable, Equatable {
    /// 画面を見分ける ID。つなぎ直しても変わらないよう、ディスプレイの UUID を使う
    let id: String
    let name: String
    /// 画面全体。ウィンドウがどの画面にあるかの判定に使う
    let frame: CGRect
    /// ウィンドウを置ける範囲（メニューバーと Dock を除く）
    let usableFrame: CGRect

    /// ショートカットでウィンドウを動かせる画面か（メイン画面より左や上にある画面は、負の座標になるため動かせない）
    var isReachable: Bool {
        ScreenGeometry.isReachable(usableFrame)
    }

    /// 今つながっている画面。並びは NSScreen.screens と同じ（先頭がメイン画面）
    static func current() -> [ScreenInfo] {
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        let menuBars = WindowList.menuBarFrames()
        return screens.map { screen in
            let visible = ScreenGeometry.topLeftRect(fromAppKit: screen.visibleFrame, primaryHeight: primaryHeight)
            return ScreenInfo(
                id: identifier(of: screen),
                name: screen.localizedName,
                frame: ScreenGeometry.topLeftRect(fromAppKit: screen.frame, primaryHeight: primaryHeight),
                usableFrame: ScreenGeometry.usableFrame(visibleFrame: visible, menuBars: menuBars)
            )
        }
    }

    private static func identifier(of screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return screen.localizedName
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        // CGDirectDisplayID はつなぎ直すと変わることがあるため、取れる場合は UUID を使う
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else {
            return "display-\(displayID)"
        }
        return string
    }
}
