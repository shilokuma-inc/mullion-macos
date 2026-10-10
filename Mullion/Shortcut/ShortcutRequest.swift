//
//  ShortcutRequest.swift
//  Mullion
//

import CoreGraphics
import Foundation

/// ショートカット「Mullion」への入力（JSON）と、返ってきた出力の読み取り。形式は scripts/make-companion-shortcut.py の説明を参照
nonisolated enum ShortcutRequest {
    /// 1 回の呼び出しで行う操作。ショートカットは 1 回に 1 つしか操作しない
    enum Operation: String {
        case move
        case resize
    }

    /// 見つかったウィンドウの位置と大きさを、手前から順に 1 行ずつ返してもらう（ショートカットが使えるかの確認に使う）
    static func list() -> String {
        encode(["mode": .text("list")])
    }

    /// 手前から index 番目（1 始まり）のウィンドウが expected の位置と大きさのときだけ、operation を行ってもらう。
    /// 座標はいずれもメイン画面の左上を原点とする
    static func operate(_ operation: Operation, index: Int, expected: CGRect, target: CGRect) -> String {
        encode([
            "mode": .text(operation.rawValue),
            "index": .number(index),
            "expected": .text(frameText(expected)),
            "x": .number(Int(target.minX.rounded())),
            "y": .number(Int(target.minY.rounded())),
            "width": .number(Int(target.width.rounded())),
            "height": .number(Int(target.height.rounded()))
        ])
    }

    /// ショートカットがウィンドウの位置と大きさを書き表す形（「x|y|幅|高さ」の整数）
    static func frameText(_ frame: CGRect) -> String {
        [frame.minX, frame.minY, frame.width, frame.height]
            .map { String(Int($0.rounded())) }
            .joined(separator: "|")
    }

    private enum Value: Encodable {
        case text(String)
        case number(Int)

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case let .text(value): try container.encode(value)
            case let .number(value): try container.encode(value)
            }
        }
    }

    private static func encode(_ object: [String: Value]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // 文字列と整数だけなので失敗しない
        guard let data = try? encoder.encode(object) else { return "{}" }
        return String(bytes: data, encoding: .utf8) ?? "{}"
    }
}

/// 移動・サイズ変更を頼んだときの、ショートカットからの返事
nonisolated enum ShortcutReply: Equatable {
    /// 操作した
    case done
    /// index 番目のウィンドウの位置と大きさが expected と違ったので、何もしなかった
    case mismatch(actual: String)
    /// それ以外。空のときは、初めての操作で macOS の許可の確認が出ていて、操作が行われなかったことがある
    case unexpected(String)

    init(_ output: String) {
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if output == "ok" {
            self = .done
        } else if output.hasPrefix("mismatch|") {
            self = .mismatch(actual: String(output.dropFirst("mismatch|".count)))
        } else {
            self = .unexpected(output)
        }
    }
}
