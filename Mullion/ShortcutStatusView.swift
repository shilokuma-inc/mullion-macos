//
//  ShortcutStatusView.swift
//  Mullion
//

import SwiftUI

/// ショートカット「Mullion」が使えるかを表示し、追加や確認をする
struct ShortcutStatusView: View {
    let model: ArrangementModel

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                icon
                    .font(.title2)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if showsInstallButton {
                            Button("ショートカットを追加") {
                                model.installShortcut()
                            }
                        }
                        if model.shortcutStatus == .notPermitted {
                            Button("システム設定を開く") {
                                openAutomationSettings()
                            }
                        }
                        Button(model.shortcutStatus == .unchecked ? "使えるか確かめる" : "確かめ直す") {
                            Task { await model.checkShortcut() }
                        }
                        .disabled(model.shortcutStatus == .checking)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.shortcutStatus {
        case .unchecked:
            Image(systemName: "rectangle.split.3x1")
                .foregroundStyle(.tint)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notInstalled, .notPermitted, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var message: String {
        let name = CompanionShortcut.name
        return switch model.shortcutStatus {
        case .unchecked:
            "ウィンドウの移動とサイズ変更は、ショートカット「\(name)」で行います。初めて使うときは追加してから、使えるか確かめてください。"
        case .checking:
            "ショートカット「\(name)」を確かめています…"
        case .ready:
            "ショートカット「\(name)」を使えます。"
        case .notInstalled:
            "ショートカット「\(name)」が見つかりません。追加してから、もう一度確かめてください。"
                + "別の名前（「\(name) 2」など）で追加された場合は、名前を「\(name)」に変えてください。"
        case .notPermitted:
            "Mullion にショートカットの実行が許可されていません。システム設定の「プライバシーとセキュリティ」→「オートメーション」で、"
                + "Mullion の「Shortcuts Events」をオンにしてください。"
        case let .failed(message):
            message
        }
    }

    private var showsInstallButton: Bool {
        switch model.shortcutStatus {
        case .unchecked, .notInstalled: true
        default: false
        }
    }

    private func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}
