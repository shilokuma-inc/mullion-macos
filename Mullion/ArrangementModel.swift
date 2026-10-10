//
//  ArrangementModel.swift
//  Mullion
//

import AppKit
import Observation

/// 並べる対象のアプリ
struct TargetApp: Identifiable, Hashable {
    /// Bundle Identifier
    let id: String
    let name: String
}

/// ショートカット「Mullion」が使えるか
enum ShortcutStatus: Equatable {
    /// まだ確かめていない（起動しただけで Apple Events の許可を求めないよう、確かめるのは操作されてから）
    case unchecked
    case checking
    case ready
    case notInstalled
    case notPermitted
    case failed(String)
}

/// ある画面に並べた結果
struct ArrangeReport: Equatable {
    var placed = 0
    /// 動いたが、アプリや macOS の制限で枠どおりにならなかった
    var adjusted = 0
    var notMoved = 0
    /// 枠が足りずに動かさなかった
    var leftovers = 0
    /// 途中で止めた理由
    var failure: String?

    var summary: String {
        var parts: [String] = []
        if placed + adjusted == 0, notMoved == 0, leftovers == 0, failure == nil {
            parts.append("この画面に並べるウィンドウがありません")
        }
        if placed + adjusted > 0 {
            parts.append("\(placed + adjusted) 枚を並べました")
        }
        if adjusted > 0 {
            parts.append("うち \(adjusted) 枚はアプリの最小サイズなどの都合で枠どおりになっていません")
        }
        if notMoved > 0 {
            parts.append("\(notMoved) 枚は動かせませんでした")
        }
        if leftovers > 0 {
            parts.append("\(leftovers) 枚は枠が足りないため動かしていません")
        }
        if let failure {
            parts.append(failure)
        }
        return parts.joined(separator: "。") + "。"
    }
}

/// 画面の一覧、画面ごとの分け方、ショートカットの状態をまとめ、ウィンドウを並べる
@Observable
final class ArrangementModel {
    private(set) var screens: [ScreenInfo] = []
    private(set) var targetApps: [TargetApp] = []
    /// 並べるアプリ。nil ならすべてのアプリ
    var targetAppID: String? {
        didSet { defaults.set(targetAppID, forKey: Keys.targetApp) }
    }
    private(set) var shortcutStatus = ShortcutStatus.unchecked
    /// 並べている最中の画面
    private(set) var arrangingScreenID: String?
    private(set) var reports: [String: ArrangeReport] = [:]

    let limit: SplitLimit
    private var layouts: [String: SplitLayout]
    private let defaults: UserDefaults
    private let shortcut = CompanionShortcut()

    init(limit: SplitLimit = .standard, defaults: UserDefaults = .standard) {
        self.limit = limit
        self.defaults = defaults
        layouts = defaults.data(forKey: Keys.layouts)
            .flatMap { try? JSONDecoder().decode([String: SplitLayout].self, from: $0) } ?? [:]
        targetAppID = defaults.string(forKey: Keys.targetApp)
    }

    // MARK: - 画面と分け方

    /// 画面とアプリの一覧を読み直す。画面の構成が変わったときにも呼ぶ
    func reload() {
        screens = ScreenInfo.current()
        reloadTargetApps()
    }

    func maxColumns(for screen: ScreenInfo) -> Int {
        limit.maxColumns(forWidth: screen.usableFrame.width)
    }

    func maxRows(for screen: ScreenInfo) -> Int {
        limit.maxRows(forHeight: screen.usableFrame.height)
    }

    /// 画面の分け方。保存したものを今の上限に収めて返す。保存していなければ 3 列（上限が 3 未満なら上限）
    func layout(for screen: ScreenInfo) -> SplitLayout {
        let saved = layouts[screen.id] ?? .columns(3)
        return saved.clamped(maxColumns: maxColumns(for: screen), maxRows: maxRows(for: screen))
    }

    func setColumnCount(_ count: Int, for screen: ScreenInfo) {
        var layout = layout(for: screen)
        layout.setColumnCount(min(count, maxColumns(for: screen)))
        save(layout, for: screen)
    }

    func setRowCount(_ count: Int, forColumn column: Int, on screen: ScreenInfo) {
        var layout = layout(for: screen)
        layout.setRowCount(min(count, maxRows(for: screen)), forColumn: column)
        save(layout, for: screen)
    }

    private func save(_ layout: SplitLayout, for screen: ScreenInfo) {
        layouts[screen.id] = layout
        if let data = try? JSONEncoder().encode(layouts) {
            defaults.set(data, forKey: Keys.layouts)
        }
    }

    // MARK: - 並べるアプリ

    /// 今ウィンドウを表示しているアプリの一覧を読み直す（Mullion 自身は除く）
    func reloadTargetApps() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [String: TargetApp] = [:]
        for pid in Set(WindowList.onScreenWindows().map(\.ownerPID)) where pid != ownPID {
            guard let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier else { continue }
            apps[id] = TargetApp(id: id, name: app.localizedName ?? id)
        }
        targetApps = apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func isTarget(_ window: WindowInfo) -> Bool {
        guard window.ownerPID != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let targetAppID else { return true }
        return NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier == targetAppID
    }

    // MARK: - ショートカット

    /// 同梱のショートカットを開き、ショートカットアプリの追加画面を出す
    func installShortcut() {
        guard let url = CompanionShortcut.bundledFileURL else { return }
        NSWorkspace.shared.open(url)
        shortcutStatus = .unchecked
    }

    /// ショートカット「Mullion」が追加されていて、実行できるかを確かめる。
    /// 初めてのときは、macOS が Mullion から Shortcuts Events を操作してよいかを確認する
    func checkShortcut() async {
        shortcutStatus = .checking
        do {
            guard try await shortcut.isInstalled() else {
                shortcutStatus = .notInstalled
                return
            }
            let output = try await shortcut.run(input: ShortcutRequest.list())
            // 初めての実行では、ショートカット側の許可の確認のために空で返ってくることがある
            shortcutStatus = output.isEmpty ? .failed(Self.firstRunHint) : .ready
        } catch {
            shortcutStatus = Self.status(for: error)
        }
    }

    // MARK: - 並べる

    /// screen にあるウィンドウを、分け方の枠に左の列から順に並べる
    func arrange(on screen: ScreenInfo) async {
        guard arrangingScreenID == nil, screen.isReachable else { return }
        arrangingScreenID = screen.id
        defer { arrangingScreenID = nil }

        let slots = layout(for: screen).frames(in: screen.usableFrame)
        let windows = WindowList.onScreenWindows().filter(isTarget)
        let plan = ArrangementPlanner.plan(windows: windows, on: screen.frame, slots: slots)
        let shortcut = shortcut
        let mover = WindowMover(
            runShortcut: { try await shortcut.run(input: $0) },
            readWindows: { WindowList.onScreenWindows() }
        )

        var report = ArrangeReport(leftovers: plan.leftovers.count)
        for placement in plan.placements {
            do {
                switch try await mover.move(windowNumber: placement.window.number, to: placement.frame) {
                case .placed: report.placed += 1
                case .adjusted: report.adjusted += 1
                case .notMoved: report.notMoved += 1
                case .disappeared: break
                }
            } catch {
                shortcutStatus = Self.status(for: error)
                report.failure = Self.message(for: error)
                break
            }
        }
        if report.failure == nil, report.placed + report.adjusted > 0 {
            shortcutStatus = .ready
        }
        reports[screen.id] = report
    }

    // MARK: - エラーの表し方

    private static let firstRunHint =
        "初めての実行で、ショートカットアプリに許可の確認が出ている可能性があります。確認に答えてから、もう一度お試しください"

    private static func status(for error: any Error) -> ShortcutStatus {
        switch error {
        case CompanionShortcut.Failure.notInstalled: .notInstalled
        case CompanionShortcut.Failure.notPermitted: .notPermitted
        default: .failed(message(for: error))
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case CompanionShortcut.Failure.notInstalled:
            "ショートカット「\(CompanionShortcut.name)」が見つからないため止めました"
        case CompanionShortcut.Failure.notPermitted:
            "Mullion にショートカットの実行が許可されていないため止めました"
        case CompanionShortcut.Failure.timedOut:
            "ショートカットが応答しないため止めました。ショートカットアプリに確認が出ていないか見てください"
        case let CompanionShortcut.Failure.shortcutFailed(message):
            "ショートカットの実行に失敗したため止めました（\(message)）"
        case let WindowMover.Failure.unexpectedReply(output) where output.isEmpty:
            firstRunHint
        case let WindowMover.Failure.unexpectedReply(output):
            "ショートカットから想定外の返事があったため止めました（\(output)）"
        default:
            "途中で止めました（\(error.localizedDescription)）"
        }
    }

    private enum Keys {
        static let layouts = "layouts"
        static let targetApp = "targetAppBundleIdentifier"
    }
}
