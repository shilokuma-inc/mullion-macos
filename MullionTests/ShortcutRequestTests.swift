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
        #expect(CompanionShortcut.Failure.from(code: -1753, message: "項目0を求めています") == .shortcutFailed("項目0を求めています"))
        #expect(CompanionShortcut.Failure.from(code: -50, message: "") == .shortcutFailed("エラー -50"))
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
