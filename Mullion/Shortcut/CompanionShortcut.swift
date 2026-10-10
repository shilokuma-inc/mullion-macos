//
//  CompanionShortcut.swift
//  Mullion
//

import AppKit

/// ウィンドウを動かすショートカット「Mullion」（Mullion/Shortcut/Mullion.shortcut）を、Shortcuts Events に実行させる。
///
/// App Sandbox の中では Accessibility API で他のアプリのウィンドウを動かせないため、移動とサイズ変更はショートカットに任せる。
/// Shortcuts Events に頼むと、ショートカットアプリの画面を開かずに裏で実行される。
/// 送れる Apple Events は entitlements の scripting-targets で「ショートカットの実行」（com.apple.shortcuts.run）だけに絞っている
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
        /// ショートカットの中でエラーになった
        case shortcutFailed(String)

        /// Apple Events のエラー番号から分類する
        static func from(code: Int, message: String) -> Failure {
            switch code {
            case -1728: .notInstalled // errAENoSuchObject: 名前のショートカットが無い
            case -1743, -1744: .notPermitted // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
            case -1712: .timedOut // errAETimeout
            default: .shortcutFailed(message.isEmpty ? "エラー \(code)" : message)
            }
        }
    }

    /// 1 回の実行を待つ上限（秒）
    var timeout: TimeInterval = 30

    /// ショートカットを input を入力にして実行し、「出力を停止」で返された文字列を返す。
    /// 1 回に 1 秒ほどかかるため、メインスレッドの外で送る
    @concurrent
    func run(input: String) async throws -> String {
        let event = makeEvent(eventClass: "srct", eventID: "run ")
        event.setParam(NSAppleEventDescriptor(string: input), forKeyword: Self.code("inpt"))
        let reply = try send(event)
        return Self.text(of: reply.paramDescriptor(forKeyword: Self.code("----")))
    }

    /// ショートカット「Mullion」が追加されているか
    @concurrent
    func isInstalled() async throws -> Bool {
        let event = makeEvent(eventClass: "core", eventID: "doex")
        let reply = try send(event)
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

    private func send(_ event: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
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
