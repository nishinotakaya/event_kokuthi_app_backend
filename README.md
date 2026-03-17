# イベント告知自動投稿アプリ — Rails Backend

イベント告知文の管理・AI文章生成・複数SNSへの自動投稿を行うWebアプリのバックエンドAPI。

## 技術スタック

- **Ruby on Rails 7.2** (API mode)
- **SQLite3** (開発) / **PostgreSQL** (本番: Heroku)
- **ActionCable** (WebSocket — リアルタイムログストリーミング)
- **Sidekiq** (非同期ジョブ: 本番)
- **Playwright** (ブラウザ自動化)
- **OpenAI API** (文章生成・添削)
- **2captcha** (reCAPTCHA解決)

## フロントエンドリポジトリ

https://github.com/nishinotakaya/event_kokuthi_app_front

---

## 環境構築

### 必要なもの

- Ruby 3.x
- Bundler
- Node.js（Playwright インストール用）
- Redis（ActionCable / Sidekiq 用 — 開発は async adapter でOK）

### セットアップ

```bash
# 1. 依存関係インストール
bundle install

# 2. Playwright ブラウザインストール
npx playwright install chromium

# 3. 環境変数設定
cp .env.example .env
# .env を編集して各種キー・パスワードを設定

# 4. DB作成 & マイグレーション
bin/rails db:create db:migrate

# 5. サーバー起動（ポート3001）
bin/rails server -p 3001
```

### 環境変数一覧 (.env)

```env
# LME (エルメ)
LME_EMAIL=your@email.com
LME_PASSWORD=yourpassword
LME_BASE_URL=https://step.lme.jp
LME_BOT_ID=17106

# 2captcha (reCAPTCHA解決)
API2CAPTCHA_KEY=your_2captcha_key

# OpenAI
OPENAI_API_KEY=sk-...

# こくチーズ / connpass
CONPASS__KOKUCIZE_MAIL=your@email.com
CONPASS_KOKUCIZE_PASSWORD=yourpassword

# Peatix
PEATIX_EMAIL=your@email.com
PEATIX_PASSWORD=yourpassword

# TechPlay
TECHPLAY_EMAIL=your@email.com
TECHPLAY_PASSWORD=yourpassword

# 本番のみ
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
```

---

## APIエンドポイント

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/folders` | フォルダ一覧 |
| POST | `/api/folders` | フォルダ作成 |
| GET | `/api/texts/:type` | テキスト一覧 |
| POST | `/api/texts/:type` | テキスト作成 |
| PUT | `/api/texts/:type/:id` | テキスト更新 |
| DELETE | `/api/texts/:type/:id` | テキスト削除 |
| POST | `/api/post` | 複数サイトへ並列投稿（WebSocketでログストリーミング） |
| POST | `/api/ai/generate` | AI文章生成 |
| POST | `/api/ai/correct` | AI文章添削 |
| POST | `/api/ai/agent` | カスタム指示で文章修正 |
| POST | `/api/ai/align-datetime` | 開催日時の自動調整 |

### 投稿先サイト

| サイト | 方式 | 環境変数 |
|--------|------|---------|
| LME (エルメ) | Playwright + LME API | `LME_EMAIL` / `LME_PASSWORD` |
| こくチーズ | Playwright + TinyMCE | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| Peatix | Playwright + Bearer API | `PEATIX_EMAIL` / `PEATIX_PASSWORD` |
| connpass | ブラウザ内fetch + CSRF | `CONPASS__KOKUCIZE_MAIL` / `CONPASS_KOKUCIZE_PASSWORD` |
| TechPlay | Playwright | `TECHPLAY_EMAIL` / `TECHPLAY_PASSWORD` |

---

## Dockerで動かす場合

```bash
docker-compose up
```

## 本番デプロイ (Heroku)

```bash
git push heroku main
heroku run rails db:migrate
```
