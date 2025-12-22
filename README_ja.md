# AgentLimits

**開発中**

macOS Sonoma以降向けのアプリと通知センターウィジェットで、ChatGPT Codex / Claude Code の使用制限（5時間・週）を表示します。

![](./images/agentlimit_sample.png)

## 仕様概要
- ログイン: アプリ内WKWebViewで対象サービスにログイン（Codex/Claudeを切替）
- 取得:
  - Codex: `https://chatgpt.com/backend-api/wham/usage`（JSON）
  - Claude: `https://claude.ai/api/organizations/{orgId}/usage`（JSON）
- 共有: App Group `group.com.(your domain).agentlimit` にプロバイダ別スナップショット保存
- ウィジェット: Codex用 / Claude用の別ウィジェットとして表示
- 共有モデル: `AgentLimitsShared/` に共通モデル/ストアを配置
- 自動更新: アプリ起動中は1分ごと（ログイン済みのサービスのみ）

## 使い方
1. Xcodeで `AgentLimits.xcodeproj` を開く
2. macOSターゲットでアプリを実行
3. メニューバーのアイコンから「設定ウィンドウを開く」を選ぶ
4. 画面上部でCodex/Claudeを切り替える
5. 画面下部のWebViewで対象サービスにログイン
6. メニューバーの「表示モード」から使用量/残り使用量を切り替える
7. 「今すぐ更新」は選択中のサービスのみ更新します
8. Apple DeveloperのIdentifiersで、アプリとウィジェットの2つのBundle IDに同じApp Group ID（`group.com.(your domain).agentlimit`）を有効化

## 表示内容
- 5時間の使用率（%）または残り（%）
- 週あたりの使用率（%）または残り（%）
- 最終更新（相対表示）
- 表示モードはメニューバーから設定（アプリ/ウィジェット共通）

## 配布方法（Developer ID）

Mac App Store外でNotarization付きで配布する手順:

1. Xcodeで **AgentLimits Release** スキームを選択
2. **Product → Archive** でアーカイブを作成
3. Organizerで **Distribute App → Developer ID** を選択
4. Notarizationが自動的に実行される
5. 公証済みの `.app` または `.dmg` をエクスポート

### ビルド設定（設定済み）
- Hardened Runtime: 有効
- App Sandbox: 有効
- デバッグシンボル: dSYM（クラッシュレポート用）
- ウィジェット拡張: アーカイブに含まれる

## 注意
- 取得は内部APIに依存します。仕様変更で取得できなくなる可能性があります。
- Widgetの更新頻度はOSにより間引かれる場合があります。
