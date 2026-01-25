# AgentLimits

**開発中**

macOS Sonoma以降向けのメニューバーアプリと通知センターウィジェットで、ChatGPT Codex / Claude Code の使用量（5時間・週）と ccusage のトークン使用量を表示します。

![](./images/agentlimit_sample.png)

## ダウンロード
最新版はこちらからダウンロードしてください: [ダウンロード](https://github.com/Nihondo/AgentLimits/releases/latest/download/AgentLimits.zip)

## クイックスタート（初回セットアップ）
1. AgentLimitsアプリを起動
2. 通知センターでウィジェットを追加
3. メニューバーから **AgentLimits設定...** を開く
4. **使用量**タブで Codex / Claude Code を選び、更新間隔（1〜10分）を設定してログイン
5. メニューバーの **表示モード** で「使用/残り」を切り替え、必要に応じて **今すぐ更新**

## 取得する情報
- **使用量（Codex / Claude Code）**: 5時間/週の使用量を内部APIから取得
  - Codex: `https://chatgpt.com/backend-api/wham/usage`
  - Claude Code: `https://claude.ai/api/organizations/{orgId}/usage`
- **トークン使用量（ccusage）**: CLIで日/週/月のトークン数とコストを取得
  - Codex: `npx -y @ccusage/codex@latest daily`
  - Claude Code: `npx -y ccusage@latest daily`

## メニューバー表示
- プロバイダごとに2行表示
  - 1行目: サービス名
  - 2行目: `X% / Y%`（5時間 / 週）
- 表示モード: **使用率** / **残り率**（アプリとウィジェットで共通）
- 色分け: ペースメーカー比較に基づく表示（色は **通知** タブで設定）
- ペースメーカーモード: `<使用率>% (<ペースメーカー>)%` 形式で経過時間比率を表示
- 表示のオン/オフは **使用量** タブでプロバイダごとに切替
- メニューバーのメニューから **言語**（システム/日本語/English）、**Wake Upの今すぐ起動**、**ログイン時にアプリを起動** を操作可能

## ペースメーカーモード
ペースメーカーモードは、時間経過に基づく使用量の目安を表示し、ペース配分に役立てます。

- **計算方法**: ウィンドウの経過時間割合（例: 50% = 5時間・週の半分が経過）
- **色分け**: 緑 = 目安以下（順調）、オレンジ = やや超過、赤 = 10%以上超過
- **メニューバー**: `<使用率>% (<ペースメーカー>)%` 形式で表示（表示切替は **ペースメーカー** タブ）
- **ウィジェット**: 外側リング = 実際の使用率、内側リング = ペースメーカー値（取得できる場合に表示）
- **閾値設定**: 警告・危険の超過閾値は **ペースメーカー** タブで設定可能
- **色設定**: ペースメーカーのリング色・文字色は **ペースメーカー** タブで設定可能

## ウィジェット
### 使用量ウィジェット（Codex / Claude Code）
- 使用率と表示モードに応じて色分け表示
- 更新時刻は `HH:mm` 形式（24時間以上前なら `--:--`）

### トークン使用量ウィジェット（Codex / Claude Code）
- **小サイズ**: 今日 / 今週 / 今月のサマリー
- **中サイズ**: サマリー + GitHub風ヒートマップ
  - 7行（日〜土）× 4〜6列（週）
  - 四分位に基づく5段階の色濃度
  - 曜日ラベル（Mon, Wed, Fri）表示
  - デスクトップ固定モード対応（アクセント / グレースケール）
- ウィジェットタップ時の動作を設定可能（デフォルトは `https://ccusage.com/` を開く）

## 設定ガイド
### 使用量
1. **使用量**タブを開く
2. Codex / Claude Code を選択
3. 更新間隔（1〜10分）を選択
4. 「メニューバーに表示」をプロバイダごとに切替
5. WebViewでログイン
6. ログインが詰まる場合は **データを削除** でログイン情報とサイトデータを消去

### ccusage
1. **ccusage**タブを開く
2. プロバイダを選択
3. 更新間隔（1〜10分）を選択
4. 「定期取得を有効にする」をオンにし、必要なら追加CLI引数を設定
5. 「今すぐテスト実行」でCLI動作を確認

### Wake Up
1. **Wake Up**タブを開く
2. プロバイダ（Codex / Claude Code）を選択
3. スケジュールを有効化
4. 実行したい時刻（0〜23時）を選択
5. 「今すぐテスト実行」でCLI動作を確認

### 通知
1. **通知**タブを開く
2. 通知権限をリクエスト（初回のみ）
3. プロバイダ（Codex / Claude Code）を選択
4. 5時間 / 週の閾値を設定
5. 使用率の色（ドーナツ色/ステータス色）を必要に応じて調整

### ペースメーカー
1. **ペースメーカー**タブを開く
2. メニューバーのペースメーカー値表示を切替
3. 警告/危険の超過閾値を調整
4. ペースメーカーのリング色/文字色を調整

### 詳細設定
1. **詳細設定**タブを開く
2. `codex` / `claude` / `npx` のフルパスを必要に応じて指定（空欄ならPATHから解決）
3. PATH解決結果を確認
4. ウィジェットタップ時の動作を選択（サイトを開く / データ更新）
5. ステータスライン用スクリプトのパスを必要に応じてコピー

## Wake Up（CLIスケジューラ）
- 実行コマンド例:
  - `codex exec --skip-git-repo-check "hello"`
  - `claude -p "hello"`
- LaunchAgentのplist: `~/Library/LaunchAgents/com.dmng.agentlimit.wakeup-*.plist`
- ログ: `/tmp/agentlimit-wakeup-*.log`
- 追加の引数はプロバイダごとに設定可能

## Claude Code ステータスライン用スクリプト
![](./images/agentlimits_statusline_sample.png)
- Claude Code ステータスライン向けの同梱スクリプト（**詳細設定 → 同梱スクリプト** にパス表示）
- Claude Code使用量スナップショット + App Group 設定（表示モード/言語/閾値/色）を参照
- 5時間/週の使用率、リセット時刻、更新時刻を1行で出力
- オプション: `-ja` / `-en` / `-r`（残り表示） / `-u`（使用率表示） / `-p`（ペースメーカー表示） / `-i`（使用率+ペースメーカー併記） / `-d`（デバッグ）
- `jq` が必要（`brew install jq`）

## 参考: App Groupの保存先
スナップショットはApp Groupコンテナに保存されます。
```
~/Library/Group Containers/group.com.dmng.agentlimit/Library/Application Support/AgentLimit/
├── usage_snapshot.json
├── usage_snapshot_claude.json
├── token_usage_codex.json
└── token_usage_claude.json
```

## 注意 / トラブルシューティング
- 内部APIは変更される可能性があります。
- ccusageのCLI出力が変わると取得に失敗する可能性があります。
- ウィジェットの更新頻度はOSにより間引かれる場合があります。
- 閾値通知には通知権限が必要です。
- CLI実行は**ユーザーのログインシェル**で行い、PATHは `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH` を先頭に追加します。
- 詳細設定でフルパスを指定した場合は、そのパスを優先して実行します。
- Claude Codeのログインに失敗し、複数回のログイン作業が必要になる可能性があります。
- Claude Code ステータスライン用スクリプトは `jq` が必要です。
