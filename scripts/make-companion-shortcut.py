#!/usr/bin/env python3
#
# Mullion がウィンドウを動かすときに呼び出す「ショートカット」（Mullion.shortcut）を生成し、署名する。
#
# Mac App Store のアプリは App Sandbox の中で動くため、Accessibility API で他のアプリのウィンドウを動かせない。
# そこで、ウィンドウの移動とサイズ変更は「ショートカット」アプリのアクション（ウィンドウを検索 / 移動 / サイズを変更）に任せ、
# アプリからは Apple Events で Shortcuts Events に実行を頼む。
#
# 使い方:
#   python3 scripts/make-companion-shortcut.py
#
# 出力: Mullion/Shortcut/Mullion.shortcut（`shortcuts sign --mode anyone` で署名済み）
#   - ショートカットアプリは、読み込んだショートカットの名前をファイル名から付ける。アプリは「Mullion」という名前で呼び出すので、
#     ファイル名を変えないこと
#   - 署名には Apple のサーバーへの問い合わせがあり、数十秒かかる。入出力のパスは絶対パスで渡す（相対パスだと失敗する）
#
# 入力（テキストの JSON）:
#   {"mode": "list"}
#       「ウィンドウを検索」で見つかったウィンドウを、手前から順に 1 行ずつ返す（各行はウィンドウのアプリ名）。
#       アプリ側の CGWindowListCopyWindowInfo の並びと突き合わせ、何番目のウィンドウを動かせばよいかを決めるのに使う
#   {"mode": "move", "index": 3, "x": 0, "y": 38, "width": 640, "height": 1080}
#       手前から index 番目（1 始まり）のウィンドウを、左上が (x, y) で width × height の枠に動かす。
#       座標はメイン画面の左上を原点とする（CGWindowListCopyWindowInfo と同じ）。完了したら "ok" を返す
#
# 組み方の根拠（いずれも実機で確かめられたもの）:
#   - 辞書の値は型の無い項目なので、If の条件にそのまま渡すと「このアクションの各パラメータの値を選択してください」で止まる。
#     いったん「テキスト」アクションで文字列にしてから If に渡す
#   - 結果は「出力を停止」で明示的に返す。最後のアクションの結果は、Apple Events や CLI の呼び出し元には返らない
#   - 数値は「数値」アクションを通してから渡す。辞書の値をそのまま渡すと、移動・サイズ変更は何もせずに成功扱いで終わる
#   - 「ウィンドウを検索」の結果は使い回さず、操作のたびに検索し直す。同じ結果を 2 回使うと 2 回目が効かない
#   - サイズ変更 → 移動 → サイズ変更の順にし、間に短い待ちを入れる。macOS は移動先を今のサイズで画面内に収めるため、
#     先に縮めないと大きいウィンドウを端に寄せられない。待ちが無いと操作が追い越し合い、片方しか効かないことがある
#   - 「ウィンドウを検索」の絞り込みは、変数から渡したアプリ名では効かない。絞り込まずに全ウィンドウを取り、番号で選ぶ
#   参考（いずれも MIT License）:
#     https://github.com/daumedia/MikaGrid の features/01-app-store-vertrieb/machbarkeit.md
#     https://github.com/sweetrb/apple-notes-mcp の scripts/build-native-operations-shortcut.py
#
from __future__ import annotations

import pathlib
import plistlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Mullion" / "Shortcut" / "Mullion.shortcut"

# 変数を差し込む位置を表す文字（Shortcuts のテキストで、1 文字ぶんの添付を置く場所）
PLACEHOLDER = "￼"

# 操作の間の待ち時間（秒）
STEP_DELAY = 0.15

# 参照: アクションの出力を (UUID, 出力名) で表す
Ref = tuple[str, str]


class Ids:
    """生成するたびに中身が変わらないよう、UUID は連番で固定する"""

    def __init__(self) -> None:
        self.count = 0

    def next(self) -> str:
        self.count += 1
        return f"4D554C4C-494F-4E00-8000-{self.count:012X}"


ids = Ids()


def attachment(value: dict) -> dict:
    return {"Value": value, "WFSerializationType": "WFTextTokenAttachment"}


def output_of(ref: Ref) -> dict:
    """前のアクションの出力を、そのまま参照する"""
    return attachment({"OutputUUID": ref[0], "OutputName": ref[1], "Type": "ActionOutput"})


def text_with(ref: Ref | None = None, string: str = PLACEHOLDER) -> dict:
    """前のアクションの出力を埋め込んだテキスト。ref が無ければ固定の文字列"""
    attachments = {}
    if ref is not None:
        attachments["{0, 1}"] = {"OutputUUID": ref[0], "OutputName": ref[1], "Type": "ActionOutput"}
    return {"Value": {"string": string, "attachmentsByRange": attachments}, "WFSerializationType": "WFTextTokenString"}


def action(identifier: str, name: str | None = None, **parameters) -> tuple[dict, Ref]:
    uuid = ids.next()
    parameters["UUID"] = uuid
    if name is not None:
        parameters["CustomOutputName"] = name
    return {"WFWorkflowActionIdentifier": f"is.workflow.actions.{identifier}", "WFWorkflowActionParameters": parameters}, (
        uuid,
        name or "",
    )


def find_windows(name: str) -> tuple[dict, Ref]:
    """絞り込みも件数の上限も付けずに、すべてのウィンドウを手前から順に取る（ショートカットアプリが書き出す形に合わせる）"""
    return action(
        "filter.windows",
        name,
        WFContentItemInputParameter="Library",
        WFContentItemLimitEnabled=False,
        WFContentItemLimitNumber=1.0,
    )


def stop_and_output(ref: Ref) -> dict:
    return action("output", WFOutput=text_with(ref))[0]


def build_actions() -> list[dict]:
    actions: list[dict] = []

    def add(entry: tuple[dict, Ref]) -> Ref:
        actions.append(entry[0])
        return entry[1]

    # 入力の JSON を辞書にする
    dictionary = add(action("detect.dictionary", "Request", WFInput=attachment({"Type": "ExtensionInput"})))

    def value_of(key: str, name: str) -> Ref:
        return add(action("getvalueforkey", name, WFInput=output_of(dictionary), WFDictionaryKey=key, WFGetDictionaryValueType="Value"))

    # If で比べられるよう、mode は文字列にしておく
    mode = add(action("gettext", "Mode", WFTextActionText=text_with(value_of("mode", "Mode Value"))))

    # mode が list なら、見つかったウィンドウのアプリ名を 1 行ずつ返す
    group = ids.next()
    actions.append(
        action(
            "conditional",
            GroupingIdentifier=group,
            WFControlFlowMode=0,
            WFCondition=4,
            WFConditionalActionString="list",
            WFInput={"Type": "Variable", "Variable": output_of(mode)},
        )[0]
    )
    found = add(find_windows("Windows"))
    combined = add(action("text.combine", "Window List", WFTextSeparator="New Lines", text=output_of(found)))
    actions.append(stop_and_output(combined))

    # それ以外（move）なら、index 番目のウィンドウを動かす
    actions.append(action("conditional", GroupingIdentifier=group, WFControlFlowMode=1)[0])
    numbers = {}
    for key, name in [("index", "Index"), ("x", "X"), ("y", "Y"), ("width", "Width"), ("height", "Height")]:
        numbers[key] = add(action("number", name, WFNumberActionNumber=output_of(value_of(key, f"{name} Value"))))

    steps = ["resize", "move", "resize"]
    for step, kind in enumerate(steps, start=1):
        windows = add(find_windows(f"Windows {step}"))
        window = add(
            action(
                "getitemfromlist",
                f"Window {step}",
                WFInput=output_of(windows),
                WFItemSpecifier="Item At Index",
                WFItemIndex=output_of(numbers["index"]),
            )
        )
        if kind == "resize":
            actions.append(
                action(
                    "resizewindow",
                    WFWindow=output_of(window),
                    WFConfiguration="Dimensions",
                    WFWidth=output_of(numbers["width"]),
                    WFHeight=output_of(numbers["height"]),
                    WFBringToFront=False,
                )[0]
            )
        else:
            actions.append(
                action(
                    "movewindow",
                    WFWindow=output_of(window),
                    WFPosition="Coordinates",
                    WFXCoordinate=output_of(numbers["x"]),
                    WFYCoordinate=output_of(numbers["y"]),
                    WFBringToFront=False,
                )[0]
            )
        if step < len(steps):
            actions.append(action("delay", WFDelayTime=STEP_DELAY)[0])
    done = add(action("gettext", "Done", WFTextActionText="ok"))
    actions.append(stop_and_output(done))

    actions.append(action("conditional", GroupingIdentifier=group, WFControlFlowMode=2)[0])
    return actions


def main() -> int:
    workflow = {
        "WFWorkflowClientVersion": "3100.0.2.1",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 61440},
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": [],
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowActions": build_actions(),
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as directory:
        unsigned = pathlib.Path(directory) / "Mullion.shortcut"
        with unsigned.open("wb") as file:
            plistlib.dump(workflow, file, fmt=plistlib.FMT_BINARY)
        print(f"==> {len(workflow['WFWorkflowActions'])} 個のアクションを書き出しました")
        print("==> 署名しています（Apple のサーバーに問い合わせるため数十秒かかります）")
        subprocess.run(
            ["shortcuts", "sign", "--mode", "anyone", "--input", str(unsigned), "--output", str(OUTPUT)],
            check=True,
        )
    print(f"==> 完了: {OUTPUT.relative_to(ROOT)}（{OUTPUT.stat().st_size} バイト）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
