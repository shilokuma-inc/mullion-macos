//
//  ContentView.swift
//  Mullion
//
//  Created by 村石 拓海 on 2024/05/12.
//

import SwiftUI

struct ContentView: View {
    @Bindable var model: ArrangementModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShortcutStatusView(model: model)
            TargetAppPicker(model: model)
            Divider()
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(model.screens) { screen in
                        ScreenSection(model: model, screen: screen)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 520)
        .onAppear { model.reload() }
        // 画面をつないだり外したり、解像度や Dock の位置を変えたりしたら、上限を計算し直す
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            model.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reloadTargetApps()
        }
    }
}

/// 並べるアプリを選ぶ
private struct TargetAppPicker: View {
    @Bindable var model: ArrangementModel

    var body: some View {
        HStack {
            Picker("並べるアプリ", selection: $model.targetAppID) {
                Text("すべてのアプリ").tag(String?.none)
                ForEach(model.targetApps) { app in
                    Text(app.name).tag(Optional(app.id))
                }
                if let id = model.targetAppID, !model.targetApps.contains(where: { $0.id == id }) {
                    Text("\(id)（ウィンドウがありません）").tag(Optional(id))
                }
            }
            .fixedSize()
            Button("アプリの一覧を更新", systemImage: "arrow.clockwise") {
                model.reloadTargetApps()
            }
            .labelStyle(.iconOnly)
            .help("アプリの一覧を更新")
        }
    }
}

#Preview {
    ContentView(model: ArrangementModel())
}
