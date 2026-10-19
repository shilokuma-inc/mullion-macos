//
//  CompanionShortcut.swift
//  Mullion
//

import AppKit

/// ウィンドウを動かすショートカット「Mullion」（Mullion/Shortcut/Mullion.shortcut）を、Shortcuts Events に実行させる。
///
/// App Sandbox の中では Accessibility API で他のアプリのウィンドウを動かせないため、移動とサイズ変更はショートカットに任せる。
/// Shortcuts Events に頼むと、ショートカットアプリの画面を開かずに裏で実行される。
/// 送れる Apple Events は entitlements の scripting-targets で「ショートカットの実行」（com.apple.shortcuts.run）だけに絞っている。
/// Shortcuts Events はしばらく使われないと終了し、Apple Events を送るだけでは起動しないため、届かなかったら起動して送り直す
nonisolated struct CompanionShortcut: Sendable {
    /// ショートカットアプリでの名前。読み込んだファイル名（Mullion.shortcut）がそのまま名前になる
    static let name = "Mullion"
    static let shortcutsEventsBundleIdentifier = "com.apple.shortcuts.events"

    /// アプリに同梱しているショートカットのファイル。開くとショートカットアプリの追加画面が出る
    static var bundledFileURL: URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut")
    }

    enum Failure: Error, Equatable {
        /// ショートカット「Mullion」が追加されていない
        case notInstalled
        /// 「オートメーション」で Mullion から Shortcuts Events を操作することが許可されていない
        case notPermitted
        /// 決まった時間内に終わらなかった（ショートカットアプリが許可の確認などで止まっていることがある）
        case timedOut
        /// Shortcuts Events が動いていない。起動して送り直しても届かなかったときに投げる
        case shortcutsEventsUnavailable
        /// ショートカットの中でエラーになった
        case shortcutFailed(String)

        /// Apple Events のエラー番号から分類する
        static func from(code: Int, message: String) -> Failure {
            switch code {
            case -1728: .notInstalled // errAENoSuchObject: 名前のショートカットが無い
            case -1743, -1744: .notPermitted // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            case -1712: .timedOut // errAETimeout
            case -600, -609: .shortcutsEventsUnavailable // procNotFound / connectionInvalid: 起動していない、送る途中で終了した
            default: .shortcutFailed(message.isEmpty ? "エラー \(code)" : message)
            }
        }
    }

    /// 1 回の実行を待つ上限（秒）
    var timeout: TimeInterval = 30
    /// Shortcuts Events を起動したあとに送り直す回数（起動の直後は Apple Events を受け付けるまで少しかかることがある）
    var retriesAfterLaunch = 10
    /// 送り直す間隔
    var retryDelay: Duration = .milliseconds(200)

    /// ショートカットを input を入力にして実行し、「出力を停止」で返された文字列を返す。
    /// 1 回に 1 秒ほどかかるため、メインスレッドの外で送る
    @concurrent
    func run(input: String) async throws -> String {
        let event = makeEvent(eventClass: "srct", eventID: "run ")
        event.setParam(NSAppleEventDescriptor(string: input), forKeyword: Self.code("inpt"))
        let reply = try await send(event)
        return Self.text(of: reply.paramDescriptor(forKeyword: Self.code("----")))
    }

    /// ショートカット「Mullion」が追加されているか
    @concurrent
    func isInstalled() async throws -> Bool {
        let event = makeEvent(eventClass: "core", eventID: "doex")
        let reply = try await send(event)
        return reply.paramDescriptor(forKeyword: Self.code("----"))?.booleanValue ?? false
    }

    /// 直接目的語を「ショートカット "Mullion"」にした Apple Event
    private func makeEvent(eventClass: String, eventID: String) -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: Self.shortcutsEventsBundleIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: Self.code(eventClass),
            eventID: Self.code(eventID),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(Self.shortcutSpecifier(), forKeyword: Self.code("----"))
        return event
    }

    private func send(_ event: NSAppleEventDescriptor) async throws -> NSAppleEventDescriptor {
        try await Self.sendLaunchingIfNeeded(retries: retriesAfterLaunch, retryDelay: retryDelay) {
            try sendOnce(event)
        } launch: {
            try await Self.launchShortcutsEvents()
        }
    }

    /// send で送り、Shortcuts Events が動いていなくて届かなかったら、launch で起動してから retries 回まで送り直す
    static func sendLaunchingIfNeeded<Reply>(
        retries: Int,
        retryDelay: Duration,
        send: () throws -> Reply,
        launch: () async throws -> Void
    ) async throws -> Reply {
        do {
            return try send()
        } catch Failure.shortcutsEventsUnavailable {
            try await launch()
        }
        var attempt = 1
        while true {
            do {
                return try send()
            } catch Failure.shortcutsEventsUnavailable where attempt < retries {
                attempt += 1
                try await Task.sleep(for: retryDelay)
            }
        }
    }

    /// Shortcuts Events を手前に出さずに起動する
    private static func launchShortcutsEvents() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcutsEventsBundleIdentifier) else {
            throw Failure.shortcutsEventsUnavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw Failure.shortcutsEventsUnavailable
        }
    }

    private func sendOnce(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
        } catch let error as NSError {
            throw Failure.from(code: error.code, message: error.localizedDescription)
        }
        // 相手のアプリの中で起きたエラーは、例外ではなく返事の中のエラー番号として届く
        if let code = reply.paramDescriptor(forKeyword: Self.code("errn"))?.int32Value, code != 0 {
            let message = reply.paramDescriptor(forKeyword: Self.code("errs"))?.stringValue ?? ""
            throw Failure.from(code: Int(code), message: message)
        }
        return reply
    }

    /// AppleScript の `shortcut "Mullion"` にあたるオブジェクト指定子
    private static func shortcutSpecifier() -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: code("srct")), forKeyword: code("want"))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: code("name")), forKeyword: code("form"))
        specifier.setDescriptor(NSAppleEventDescriptor(string: name), forKeyword: code("seld"))
        specifier.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: code("from"))
        return specifier.coerce(toDescriptorType: code("obj ")) ?? specifier
    }

    /// 返事の値を文字列にする。リストで返ってきたときは改行でつなぐ
    private static func text(of descriptor: NSAppleEventDescriptor?) -> String {
        guard let descriptor else { return "" }
        if descriptor.numberOfItems > 0, descriptor.descriptorType == code("list") {
            return (1...descriptor.numberOfItems)
                .compactMap { descriptor.atIndex($0)?.stringValue }
                .joined(separator: "\n")
        }
        return descriptor.stringValue ?? ""
    }

    /// "srct" のような 4 文字を Apple Events の 4 文字コードにする
    static func code(_ string: String) -> FourCharCode {
        string.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
