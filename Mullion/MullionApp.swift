//
//  MullionApp.swift
//  Mullion
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

@main
struct MullionApp: App {
    @State private var model = ArrangementModel()

    var body: some Scene {
        WindowGroup("Mullion") {
            ContentView(model: model)
        }
        .defaultSize(width: 680, height: 760)
    }
}
