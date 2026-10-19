//
//  ScreenSection.swift
//  Mullion
//

import SwiftUI

/// 画面 1 つぶんの分け方の設定と、並べるボタン
struct ScreenSection: View {
    let model: ArrangementModel
    let screen: ScreenInfo

    var body: some View {
        let layout = model.layout(for: screen)
        let maxColumns = model.maxColumns(for: screen)
        let maxRows = model.maxRows(for: screen)
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                header(maxColumns: maxColumns, maxRows: maxRows)
                if !screen.isReachable {
                    SystemEventsNotice(status: model.systemEventsStatus)
                }
                HStack(alignment: .top, spacing: 16) {
                    LayoutPreview(layout: layout, aspectRatio: screen.usableFrame.width / max(1, screen.usableFrame.height))
                        .frame(width: 240)
                    controls(layout: layout, maxColumns: maxColumns, maxRows: maxRows)
                }
                footer
            }
            .padding(4)
        }
    }

    private func header(maxColumns: Int, maxRows: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(screen.name)
                .font(.headline)
            Spacer()
            Text("\(Int(screen.usableFrame.width)) × \(Int(screen.usableFrame.height)) pt・最大 \(maxColumns) 列 × \(maxRows) 段")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func controls(layout: SplitLayout, maxColumns: Int, maxRows: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: columnCount, in: 1...maxColumns) {
                Text("列: \(layout.columnCount)")
            }
            .accessibilityIdentifier("column-stepper")
            if maxRows > 1 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
                    ForEach(0..<layout.columnCount, id: \.self) { column in
                        Stepper(value: rowCount(forColumn: column), in: 1...maxRows) {
                            Text("\(column + 1) 列目: \(layout.rowCounts[column]) 段")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button("この画面に並べる") {
                Task { await model.arrange(on: screen) }
            }
            .disabled(model.arrangingScreenID != nil)
            if model.arrangingScreenID == screen.id {
                ProgressView()
                    .controlSize(.small)
            } else if let report = model.reports[screen.id] {
                Text(report.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var columnCount: Binding<Int> {
        Binding(
            get: { model.layout(for: screen).columnCount },
            set: { model.setColumnCount($0, for: screen) }
        )
    }

    private func rowCount(forColumn column: Int) -> Binding<Int> {
        Binding(
            get: { model.layout(for: screen).rowCounts[safe: column] ?? 1 },
            set: { model.setRowCount($0, forColumn: column, on: screen) }
        )
    }
}

/// メイン画面より左か上にある画面に出す、System Events で並べることと要る許可の説明
struct SystemEventsNotice: View {
    let status: SystemEventsStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: isProblem ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            switch status {
            case .automationNotPermitted:
                Button("オートメーションの設定を開く") {
                    open("Privacy_Automation")
                }
            case .accessibilityNotPermitted:
                Button("アクセシビリティの設定を開く") {
                    open("Privacy_Accessibility")
                }
            default:
                EmptyView()
            }
        }
        .font(.callout)
    }

    private var isProblem: Bool {
        switch status {
        case .unchecked, .ready: false
        case .automationNotPermitted, .accessibilityNotPermitted, .failed: true
        }
    }

    private var message: String {
        switch status {
        case .unchecked, .ready:
            "この画面はメイン画面より左か上にあるため、System Events でウィンドウを動かします。"
                + "初めて並べるときに、System Events の操作とアクセシビリティの許可を求められます。"
        case .automationNotPermitted:
            "Mullion に System Events の操作が許可されていません。システム設定の「プライバシーとセキュリティ」→「オートメーション」で、"
                + "Mullion の「System Events」をオンにしてください。"
        case .accessibilityNotPermitted:
            "Mullion にアクセシビリティの許可がありません。システム設定の「プライバシーとセキュリティ」→「アクセシビリティ」で、"
                + "Mullion をオンにしてください。"
        case let .failed(message):
            message
        }
    }

    private func open(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// 分け方のプレビュー。枠には並べる順の番号を出す
struct LayoutPreview: View {
    let layout: SplitLayout
    /// 画面の縦横比（幅 ÷ 高さ）
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let frames = layout.frames(in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.2))
                        .strokeBorder(Color.accentColor.opacity(0.7))
                        .overlay {
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: max(0, frame.width - 4), height: max(0, frame.height - 4))
                        .offset(x: frame.minX + 2, y: frame.minY + 2)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(layout.columnCount) 列・\(layout.slotCount) 枠の分け方")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
