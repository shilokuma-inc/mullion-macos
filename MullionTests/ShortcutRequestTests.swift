//
//  ShortcutRequestTests.swift
//  MullionTests
//

import CoreGraphics
import Foundation
@testable import Mullion
import Testing

struct ShortcutRequestTests {
    private func decode(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test
    func listRequest() throws {
        #expect(try decode(ShortcutRequest.list()) as? [String: String] == ["mode": "list"])
    }

    /// 移動・サイズ変更の入力。数値は整数に丸め、expected はショートカットと同じ「x|y|幅|高さ」で渡す
    @Test
    func operationRequest() throws {
        let json = ShortcutRequest.operate(
            .resize,
            index: 3,
            expected: CGRect(x: 2056, y: 30, width: 349, height: 983),
            target: CGRect(x: 1728.4, y: 30, width: 365.6, height: 331)
        )
        let request = try decode(json)
        #expect(request["mode"] as? String == "resize")
        #expect(request["index"] as? Int == 3)
        #expect(request["expected"] as? String == "2056|30|349|983")
        #expect(request["x"] as? Int == 1728)
        #expect(request["y"] as? Int == 30)
        #expect(request["width"] as? Int == 366)
        #expect(request["height"] as? Int == 331)
    }

    @Test
    func readsReplies() {
        #expect(ShortcutReply("ok") == .done)
        #expect(ShortcutReply("ok\n") == .done)
        #expect(ShortcutReply("mismatch|185|83|640|480") == .mismatch(actual: "185|83|640|480"))
        #expect(ShortcutReply("") == .unexpected(""))
    }
}

struct CompanionShortcutTests {
    /// Apple Events のエラー番号を、画面に出し分ける種類に分ける
    @Test
    func classifiesAppleEventErrors() {
        #expect(CompanionShortcut.Failure.from(code: -1728, message: "") == .notInstalled)
        #expect(CompanionShortcut.Failure.from(code: -1743, message: "") == .notPermitted)
        #expect(CompanionShortcut.Failure.from(code: -1712, message: "") == .timedOut)
        #expect(CompanionShortcut.Failure.from(code: -600, message: "") == .shortcutsEventsUnavailable)
        #expect(CompanionShortcut.Failure.from(code: -609, message: "") == .shortcutsEventsUnavailable)
        #expect(CompanionShortcut.Failure.from(code: -1753, message: "項目0を求めています") == .shortcutFailed("項目0を求めています"))
        #expect(CompanionShortcut.Failure.from(code: -50, message: "") == .shortcutFailed("エラー -50"))
    }

    /// Shortcuts Events が動いていれば、起動せずにそのまま送る
    @Test
    func sendsWithoutLaunchingWhenRunning() async throws {
        var sends = 0
        var launches = 0
        let reply = try await CompanionShortcut.sendLaunchingIfNeeded(retries: 3, retryDelay: .zero) {
            sends += 1
            return "ok"
        } launch: {
            launches += 1
        }
        #expect(reply == "ok")
        #expect(sends == 1)
        #expect(launches == 0)
    }

    /// Shortcuts Events が終了していたら、起動してから送り直す。起動の直後に届かなくても、間を置いて送り直す
    @Test
    func launchesAndResendsWhenNotRunning() async throws {
        var sends = 0
        var launches = 0
        let reply = try await CompanionShortcut.sendLaunchingIfNeeded(retries: 3, retryDelay: .zero) {
            sends += 1
            guard sends >= 3 else { throw CompanionShortcut.Failure.shortcutsEventsUnavailable }
            return "ok"
        } launch: {
            launches += 1
        }
        #expect(reply == "ok")
        #expect(sends == 3)
        #expect(launches == 1)
    }

    /// 起動しても届かなければ、決まった回数で諦める
    @Test
    func givesUpAfterRetries() async {
        var sends = 0
        var launches = 0
        await #expect(throws: CompanionShortcut.Failure.shortcutsEventsUnavailable) {
            try await CompanionShortcut.sendLaunchingIfNeeded(retries: 3, retryDelay: .zero) { () throws -> String in
                sends += 1
                throw CompanionShortcut.Failure.shortcutsEventsUnavailable
            } launch: {
                launches += 1
            }
        }
        #expect(sends == 1 + 3)
        #expect(launches == 1)
    }

    /// Shortcuts Events が動いていないこと以外のエラーは、起動も送り直しもせずにそのまま投げる
    @Test
    func doesNotLaunchForOtherFailures() async {
        var sends = 0
        var launches = 0
        await #expect(throws: CompanionShortcut.Failure.notPermitted) {
            try await CompanionShortcut.sendLaunchingIfNeeded(retries: 3, retryDelay: .zero) { () throws -> String in
                sends += 1
                throw CompanionShortcut.Failure.notPermitted
            } launch: {
                launches += 1
            }
        }
        #expect(sends == 1)
        #expect(launches == 0)
    }

    @Test
    func fourCharacterCodes() {
        #expect(CompanionShortcut.code("srct") == 0x7372_6374)
        #expect(CompanionShortcut.code("----") == 0x2D2D_2D2D)
    }

    /// 同梱のショートカットは、ショートカットアプリでの名前と同じファイル名にする（読み込むとファイル名が名前になる）
    @Test
    func bundlesShortcutNamedAfterIt() throws {
        let url = try #require(CompanionShortcut.bundledFileURL)
        #expect(url.deletingPathExtension().lastPathComponent == CompanionShortcut.name)
    }
}
