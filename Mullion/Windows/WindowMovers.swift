//
//  WindowMovers.swift
//  Mullion
//

import CoreGraphics

/// ArrangementModel がウィンドウを読み、動かすための手段。テストでは差し替える
nonisolated struct WindowMovers: Sendable {
    typealias Move = @Sendable (_ windowNumber: Int, _ target: CGRect) async throws -> WindowMover.Outcome

    /// 手前から順のウィンドウ一覧
    var readWindows: @Sendable () -> [WindowInfo]
    /// ショートカット「Mullion」で動かす。メイン画面の右か下にある画面（ScreenInfo.isReachable）で使う
    var shortcut: Move
    /// System Events で動かす。ショートカットでは届かない、メイン画面より左か上にある画面で使う
    var systemEvents: Move

    static let live: WindowMovers = {
        let readWindows: @Sendable () -> [WindowInfo] = { WindowList.onScreenWindows() }
        let shortcut = CompanionShortcut()
        let shortcutMover = WindowMover(runShortcut: { try await shortcut.run(input: $0) }, readWindows: readWindows)
        let systemEventsMover = SystemEventsWindowMover(client: SystemEvents().client, readWindows: readWindows)
        return WindowMovers(
            readWindows: readWindows,
            shortcut: { try await shortcutMover.move(windowNumber: $0, to: $1) },
            systemEvents: { try await systemEventsMover.move(windowNumber: $0, to: $1) }
        )
    }()
}
