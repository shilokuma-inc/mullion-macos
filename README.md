# Mullion

画面を 3〜5 列などの縦の列に分け、列ごとに上下にも分けて、ウィンドウをまとめて並べる macOS アプリです。
画面ごとに解像度から分割できる上限を決め、狭い画面で細かく分けすぎてウィンドウが潰れないようにします。
Mac App Store での配布を目指しています。

## 使い方

1. 初めて使うときは「ショートカットを追加」を押し、ショートカットアプリでショートカット「Mullion」を追加します。続けて「使えるか確かめる」を押し、Mullion から Shortcuts Events を操作してよいかの確認に「OK」で答えます
2. 画面ごとに、列の数と、列ごとの上下の分割数（段）を選びます。選べる上限は画面の大きさから決まり、分け方はプレビューで確認できます
3. 必要なら「並べるアプリ」で対象のアプリを絞り込み、「この画面に並べる」を押します。その画面にあるウィンドウが、今の位置の左から順に、左の列の上の枠から並びます

- 上限は、ウィンドウを置ける範囲（メニューバーと Dock を除く）を 1 マスの最小サイズ 340 × 320 pt で割って決めます。ターミナル（Ayuthaya 12pt）で約 46 桁 × 16 行が入る大きさです
- 画面をつないだり外したり、解像度や Dock の位置を変えたりすると、上限を計算し直します。画面ごとの分け方は保存し、つなぎ直しても同じ画面には同じ分け方を使います
- 枠より多いウィンドウは動かしません。アプリの最小サイズより狭い枠では、ウィンドウが枠どおりにならないことがあります（並べたあとに件数を表示します）
- メイン画面より左か上にある画面には、今のバージョンでは並べられません（ショートカットの「ウィンドウを移動」が負の座標を受け付けないため）

## Environment

- Xcode 26.3
- macOS 14.0 以上
- Swift 6（Swift 6 言語モード / Strict Concurrency）
- SwiftUI / Swift Testing / XCTest（UI テスト）
- SwiftLint 0.65.1（Build Tool Plugin。バイナリだけを配布する [SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins) 経由）

## Status

<div style="margin:0px;padding:0px;">
  <table width="98%" style="border-collapse: collapse;border:2px double #000080;text-align:center;margin:auto;">
    <tbody>
      <tr>
        <td style="border:2px double #000080;">branch \ workflow</td>
        <td style="border:2px double #000080;">Build</td>
        <td style="border:2px double #000080;">Archive</td>
        <td style="border:2px double #000080;">Upload</td>
      </tr>
      <tr>
        <td style="border:2px double #000080;text-align:left;">main</td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/build.yml?query=branch%3Amain">
            <img src="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/build.yml/badge.svg?branch=main" alt="Build">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/archive.yml?query=branch%3Amain">
            <img src="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/archive.yml/badge.svg?branch=main" alt="Archive">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
        </td>
      </tr>
      <tr>
        <td style="border:2px double #000080;text-align:left;">develop</td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/build.yml?query=branch%3Adevelop">
            <img src="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/build.yml/badge.svg?branch=develop" alt="Build">
          </a>
        </td>
        <td style="border:2px double #000080;text-align:center;">
        </td>
        <td style="border:2px double #000080;text-align:center;">
          <a href="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/upload.yml?query=branch%3Adevelop">
            <img src="https://github.com/shilokuma-inc/mullion-macos/actions/workflows/upload.yml/badge.svg?branch=develop" alt="Upload">
          </a>
        </td>
      </tr>
    </tbody>
  </table>
</div>

## 開発

[Mullion.xcodeproj](Mullion.xcodeproj) を Xcode で開き、スキーム `Mullion` を My Mac で実行します。

コマンドラインで Unit テストを実行する場合は、CI と同じくアドホック署名にし、App Sandbox を外します（App Sandbox を有効にしたままアドホック署名すると、test runner がアプリに接続できずに止まるため）。

```bash
xcodebuild test \
  -project Mullion.xcodeproj \
  -scheme Mullion \
  -destination 'platform=macOS' \
  -skip-testing:MullionUITests \
  -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_APP_SANDBOX=NO
```

UI テスト（`MullionUITests`）は実際にアプリを起動して操作するため、手元で実行すると作業中の画面が使えなくなります。普段は CI に任せてください。

### ウィンドウを動かす仕組み（ショートカット「Mullion」）

Mac App Store のアプリは App Sandbox の中で動くため、Accessibility API でほかのアプリのウィンドウを動かせません。
そこで、ウィンドウの位置と大きさはウィンドウサーバー（`CGWindowListCopyWindowInfo`）から読み、移動とサイズ変更はアプリに同梱したショートカット「Mullion」（[Mullion/Shortcut/Mullion.shortcut](Mullion/Shortcut/Mullion.shortcut)）に任せます。
アプリからは Apple Events で Shortcuts Events にショートカットの実行を頼みます（[CompanionShortcut.swift](Mullion/Shortcut/CompanionShortcut.swift)）。

- 送れる Apple Events は、entitlements の `com.apple.security.scripting-targets` で Shortcuts Events の「ショートカットの実行」だけに絞っています（[Mullion/Mullion.entitlements](Mullion/Mullion.entitlements)）
- ショートカットは「手前から何番目のウィンドウか」でしかウィンドウを選べません。そのため、操作のたびにウィンドウの一覧を読み直して番号を決め、今の位置と大きさも渡します。ショートカットは位置と大きさが一致したときだけ操作するので、途中で重なり順が変わっても別のウィンドウを動かしません（[WindowMover.swift](Mullion/Windows/WindowMover.swift)）
- 1 回の呼び出しでは 1 つの操作（移動かサイズ変更）しかしません。1 枚あたり、サイズ変更 → 移動 → サイズ変更の順に呼びます

ショートカットは [scripts/make-companion-shortcut.py](scripts/make-companion-shortcut.py) で生成・署名します。入出力の形式と、ショートカットの組み方の根拠もこのスクリプトに書いています。

```bash
python3 scripts/make-companion-shortcut.py
```

- 署名に Apple のサーバーへの問い合わせがあり、数十秒かかります
- 作り直したショートカットは、ファイルを開いてショートカットアプリで「置き換える」を選ぶまで手元に反映されません
- 手元でショートカットを試すと、開いている本物のウィンドウが動きます。試すときは TextEdit などで捨ててよいウィンドウを開いて使います

### ビルド設定

署名情報やバージョンは pbxproj ではなく [Configs/Project.xcconfig](Configs/Project.xcconfig) に集約しています。

| 設定 | 内容 |
|---|---|
| `DEVELOPMENT_TEAM` | Apple Developer Program の Team ID |
| `APP_BUNDLE_IDENTIFIER` | アプリ本体の Bundle Identifier（`jp.shilokuma.Mullion`）。テストターゲットは `.Tests` / `.UITests` を付けて自動で派生します |
| `MARKETING_VERSION` | アプリのバージョン。ビルド番号（`CURRENT_PROJECT_VERSION`）は Upload のときに App Store Connect の最新ビルドを見て Xcode が自動で増やすため、手で上げる必要はありません |
| `MACOSX_DEPLOYMENT_TARGET` | 最低サポート OS |

- Mac App Store の必須条件なので、アプリ本体は App Sandbox を有効にしています（pbxproj の `ENABLE_APP_SANDBOX`）
- App Store のカテゴリは「仕事効率化」（`public.app-category.productivity`）です

## 配布（Mac App Store）

Archive / Upload ワークフローは App Store Connect API Key で認証します。Secrets は org で共有しているもの（template-app-ios から作った他のアプリと同じ）を使います。このリポジトリで参照できない場合は、Settings → Secrets and variables → Actions に登録してください。

| Secret | 内容 |
|---|---|
| `EXPORT_OPTIONS` | `ExportOptions.plist` の内容（[docs/ExportOptions.sample.plist](docs/ExportOptions.sample.plist)）。`.ipa` と `.pkg` のどちらを書き出すかはアーカイブのプラットフォームで決まるため、iOS アプリと共用できます |
| `APPLE_API_KEY_BASE64` | App Store Connect の API Key（`AuthKey_XXXXXXXXXX.p8`）を base64 でエンコードした文字列 |
| `APPLE_API_KEY_ID` | API Key の Key ID |
| `APPLE_API_ISSUER_ID` | API Key の Issuer ID |

Bundle ID・証明書・プロビジョニングプロファイルは、Export のときに API Key で自動的に作成されます（`-allowProvisioningUpdates`）。
App Store Connect でのアプリ作成だけは API で行えないため、Web 画面で行います。
アプリが無いまま `develop` に push すると、Upload ワークフローがアップロードの前に止まり、「新規アプリ」画面に入力する値（プラットフォーム macOS・名前・バンドル ID・SKU など）を Job Summary に表示します（[.github/scripts/check-app-store-app.rb](.github/scripts/check-app-store-app.rb)）。表示された値でアプリを作成してから、ワークフローを再実行してください。SKU は Bundle ID と同じ値にします。

## ブランチ運用と CI

| ブランチ | Build（ビルド + テスト + SwiftLint） | Archive（.pkg の Export） | Upload（App Store Connect） |
|---|:-:|:-:|:-:|
| `main` | ✅ | ✅ | |
| `develop` | ✅ | | ✅ |
| `release/**` | ✅ | | ✅ |
| その他の作業ブランチ | ✅（Unit テストのみ） | | |
| Pull Request の作成時（opened / reopened / ready_for_review） | ✅ | | |
| Fork からの Pull Request | ✅ | | |
| `assets/**`（PR 用スクリーンショット置き場） | | | |

- テストは macOS ランナー上で、アドホック署名・App Sandbox なしで実行します
- Archive は、App Sandbox の entitlements を埋め込むためにアドホック署名で作り、Export のときに配布用の署名をし直します
- Upload は Archive → .pkg の Export を含むため、`develop` / `release/**` では Archive を別途実行しません
- Archive / Upload は Actions タブから手動でも実行できます（Run workflow）。作業ブランチを TestFlight で確認したいときは、Upload を手動実行してそのブランチを選びます
- リポジトリ変数（Settings → Secrets and variables → Actions → Variables）に `ENABLE_DELIVERY=false` を設定すると Upload をスキップします
- ドキュメントだけの変更（`**/*.md`、`docs/**`）では Build を実行しません。Upload（`develop` / `release/**` への push）と Archive（`main` への push）は、ドキュメントだけの変更でも実行します
- 作業ブランチへの push では、時間のかかる UI テスト（`MullionUITests`）を省いて Unit テストだけ実行します。UI テストは Pull Request の作成時と `main` / `develop` / `release/**` への push で実行します。Fork からの Pull Request は push で実行されないため、更新（synchronize）を含むすべてのイベントで UI テストまで実行します
- Xcode のバージョンは [.github/workflows/_build.yml](.github/workflows/_build.yml) と [.github/workflows/_archive.yml](.github/workflows/_archive.yml) の `xcode-version` で固定しています。Environment の更新時はあわせて変更してください

## PR 本文のスクリーンショット

UI の見た目が変わる変更では、Before / After のスクリーンショットを PR 本文に添付します。

- 画像は PR の diff を汚さないよう **`assets/issue-<Issue番号>` ブランチ**に置き、PR 本文からは raw URL で参照します
  - 例: `https://raw.githubusercontent.com/<owner>/<repo>/assets/issue-12/12/before.png`
  - このブランチは [.github/workflows/cleanup-assets-branch.yml](.github/workflows/cleanup-assets-branch.yml) が PR のマージ時に自動削除します。削除するのは、PR 本文の行頭（箇条書きの `- ` は可）にある `resolve #<Issue番号>`（`resolves` / `resolved`・`close` 系・`fix` 系でも可）と番号が一致するブランチだけです。PR テンプレートの「関連するISSUE」の書き方のままで条件を満たします。これらのキーワードが行頭に無い場合や、ブランチ名がこの規約から外れる場合は削除されないので注意してください
  - 削除後は PR 本文の画像が表示されなくなります。画像はレビューのためのもので、マージ後に残す必要はないという前提です。残したい画像は、マージ前に Issue や PR のコメントへ直接添付してください
- Before / After は表で横に並べ、同一条件（同じ端末・OS・外観モード・データ状態）で撮影します
- 影響する画面が複数ある場合は画面ごとに用意します。新規画面で Before が無い場合は「なし」と書きます

## 構成

```
.
├── Configs/                  # xcconfig（署名情報・バージョン・Deployment Target）
├── Mullion/                  # アプリ本体（SwiftUI）
│   ├── Layout/               # 分割できる上限と、列と段の分け方の計算
│   ├── Windows/              # 画面とウィンドウの一覧の読み取り、枠への割り当て、ウィンドウの移動
│   └── Shortcut/             # 同梱のショートカット「Mullion」と、Apple Events での実行
├── MullionTests/             # Unit テスト（Swift Testing）
├── MullionUITests/           # UI テスト（XCTest）
├── Mullion.xcodeproj         # 共有スキーム Mullion を含む
├── docs/                     # ExportOptions.plist のサンプル
├── scripts/                  # ショートカットの生成（make-companion-shortcut.py）/ rename.sh / ralph-loop の補助スクリプト
├── .swiftlint.yml            # SwiftLint 設定
└── .github/
    ├── ISSUE_TEMPLATE/       # Issue テンプレート
    ├── pull_request_template.md
    ├── scripts/              # check-app-store-app.rb（App Store Connect のアプリの有無を確認）
    └── workflows/
        ├── _build.yml        # 共通処理: ビルド + テスト + SwiftLint（workflow_call）
        ├── _archive.yml      # 共通処理: Archive → .pkg の Export（→ Upload）（workflow_call）
        ├── build.yml         # 全ブランチの push / Fork からの PR
        ├── archive.yml       # main の push
        ├── upload.yml        # develop / release/** の push
        └── cleanup-assets-branch.yml # PR マージ時に assets/issue-<番号> ブランチを削除
```

- [shilokuma-inc/template-app-ios](https://github.com/shilokuma-inc/template-app-ios) から作成し、macOS 専用に変えています
- プロジェクトはフォルダ同期グループ（Xcode 16 以降の形式）で管理しているため、ファイルの追加・削除で pbxproj は変わりません
- SwiftLint は Build Tool Plugin として全ターゲットに適用され、CI では `swiftlint lint --strict` としても実行されます。ルールは [.swiftlint.yml](.swiftlint.yml) で管理します
- CI のワークフローは `*.xcodeproj` の名前と同名の共有スキームが存在することを前提にしています
- [Mullion/PrivacyInfo.xcprivacy](Mullion/PrivacyInfo.xcprivacy) はプライバシーマニフェストです。UserDefaults（画面ごとの分け方と、並べるアプリの保存）の利用だけを申告しています。データの収集・トラッキング・ほかの理由の申告が必要な API を足したら、ここと App Store Connect の「App のプライバシー」を更新してください

## License

[MIT License](LICENSE)
