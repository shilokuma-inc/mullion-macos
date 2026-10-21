#!/bin/bash
#
# Icon Composer の .icon を PNG に書き出し、見た目を確かめる。
#
# 使い方:
#   scripts/render-app-icon.sh <x.icon> <出力先ディレクトリ>
#
#   x.icon            書き出す .icon（例: Mullion/AppIcon.icon）
#   出力先ディレクトリ  PNG を書く場所。無ければ作る。画像をリポジトリに残さないため、
#                     リポジトリの外（例: ~/Desktop/icon-check）を指定する
#
# 書き出すもの（<名前> は .icon の拡張子を除いた名前）:
#   <名前>-<rendition>.png  6 つの rendition（Default・Dark・ClearLight・ClearDark・TintedLight・TintedDark）の 1024px
#   <名前>-<px>.png         16・32・64・128px の Default（小さいサイズで形が潰れないかを見る）
#
# ictool は Xcode に同梱の Icon Composer のものを使う（${DEVELOPER_DIR:-$(xcode-select -p)} から探す）。
# xcode-select が CommandLineTools を指している Mac では、DEVELOPER_DIR を付けて実行する:
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/render-app-icon.sh Mullion/AppIcon.icon ~/Desktop/icon-check
#
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <x.icon> <出力先ディレクトリ>" >&2
  exit 1
fi

ICON="${1%/}"
OUT="$2"

if [[ ! -f "${ICON}/icon.json" ]]; then
  echo "${ICON} に icon.json がありません。Icon Composer の .icon を指定してください" >&2
  exit 1
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
ICTOOL="${DEVELOPER_DIR}/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  echo "ictool が見つかりません: ${ICTOOL}" >&2
  echo "Xcode 26 以降を入れ、DEVELOPER_DIR に Xcode の Contents/Developer を指定して実行してください" >&2
  echo "  例: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $0 $*" >&2
  exit 1
fi

mkdir -p "$OUT"
NAME="$(basename "$ICON" .icon)"

# export_image <rendition> <px> <出力ファイル>
export_image() {
  # ictool は成功すると標準出力に {} を出すだけなので捨てる
  "$ICTOOL" "$ICON" --export-image --output-file "$3" \
    --platform macOS --rendition "$1" --width "$2" --height "$2" --scale 1 >/dev/null
  echo "$3"
}

for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  export_image "$rendition" 1024 "${OUT}/${NAME}-${rendition}.png"
done

for px in 16 32 64 128; do
  export_image Default "$px" "${OUT}/${NAME}-${px}.png"
done
