//
//  MullionUITests.swift
//  MullionUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class MullionUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 起動すると、つながっている画面ごとに並べるボタンが出て、ショートカットを確かめるボタンも出る。
    /// 確かめるまでは Apple Events を送らない（起動しただけで許可の確認を出さない）ので、テストでも確認は出ない
    @MainActor
    func testLaunchShowsScreenSections() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["この画面に並べる"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["使えるか確かめる"].exists)
        XCTAssertTrue(app.buttons["ショートカットを追加"].exists)
    }
}
