# GitSync

Flutter app + Firebase Cloud Functions + OpenAI agent that integrates GitHub +
Discord and auto-generates task breakdowns, assignments, and handoff docs.

NTHU Software Studio final project, team 17.

---

## 🚀 Quickstart — git clone 到跑起來

> 完整教學在 [`docs/SETUP.md`](./docs/SETUP.md);這裡是最短路徑。
> 前置工具:Flutter 3.44+、Node.js 22(只有要動 Cloud Functions 才需要)。

### 路徑 A — Fake 模式(~10 分鐘,不需要任何帳號/金鑰)

```powershell
git clone https://github.com/H030m/gitsync.git
cd gitsync
flutter pub get

# ⚠️ 必做:firebase_options.dart 是 gitignored(web apiKey 不入 git),
#    fresh clone 缺這檔會直接編譯失敗 — 複製 placeholder 即可:
Copy-Item lib/firebase_options.example.dart lib/firebase_options.dart

flutter run        # 預設就是 fake backend,自動以 demo 帳號登入
```

跑起來會看到 demo repo(`team17/gitsync`)的看板、Summary 日報、commit
分支圖、Discord 訊息——全部是內建假資料,適合看 UI / 開發前端。

### 路徑 B — Live 模式(連團隊的 Firebase,需要被邀請)

1. 請 project owner 把你的 Google 帳號加進 Firebase 專案
   (`gitsync-645b3`,Console → 使用者和權限 → Editor)
2. ```powershell
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure   # 產生真的 lib/firebase_options.dart(覆蓋 placeholder)
   flutter run --dart-define=BACKEND=live
   ```
3. App 內用 **GitHub 帳號登入**——加 repo、分支圖、AI 解釋 commit 都是用你
   自己的 GitHub token 打 API,所以要用對目標 repo 有權限的帳號。

後端(Cloud Functions / OpenAI / Discord bot)已部署在雲端,clone 的人
**不需要**設定那些;要自己部署後端才看 [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md)。

---

## 📚 Project docs

- [`docs/SETUP.md`](./docs/SETUP.md) — local environment setup (Fake / Live modes)
- [`docs/DEPLOYMENT.md`](./docs/DEPLOYMENT.md) — full cloud deployment runbook (functions, secrets, OAuth, Discord bot, end-to-end verify, error table)
- [`docs/TRELLIS_WORKFLOW.md`](./docs/TRELLIS_WORKFLOW.md) — how the team develops with Trellis (per-dev setup, task lifecycle, conventions)
- [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) — system design (Firestore schema, Cloud Functions, AI flows, Discord/GitHub integration)
- [`docs/AI_AGENT_RULES.md`](./docs/AI_AGENT_RULES.md) — required reading for any AI assistant before writing code
- [`docs/COURSE_METHODS.md`](./docs/COURSE_METHODS.md) — course-prescribed Flutter + Firebase patterns
- [`docs/MEMORY.md`](./docs/MEMORY.md) — team decisions log (why we chose X over Y)
- [`docs/journal/`](./docs/journal/) — per-member work log
- [`secrets/README.md`](./secrets/README.md) — API key / secret management
- [`functions/README.md`](./functions/README.md) — Cloud Functions package layout + commands

---

## 🛠️ Quick commands

```powershell
# Run with fake (in-memory) backend — no Firebase setup needed
flutter run --dart-define=BACKEND=fake

# Run against real Firebase (requires flutterfire configure first)
flutter run --dart-define=BACKEND=live

# Lint
flutter analyze

# Cloud Functions type check
npm --prefix functions run typecheck

# Firestore + Functions emulator
firebase emulators:start
```

---

## 🤝 Team

5-person team; each person owns a module per [`docs/ARCHITECTURE.md §9`](./docs/ARCHITECTURE.md). See individual journals under [`docs/journal/`](./docs/journal/).
