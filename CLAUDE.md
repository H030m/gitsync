## 必讀文件 — 每次 SESSION 開始時必須讀取

每次 session 開始、寫任何程式碼之前，**必須用 Read 工具依序讀取**：

1. `docs/AI_AGENT_RULES.md` — 強制工作流程（Read → Write → Verify）、紅線、五欄回報格式
2. `docs/MEMORY.md` — 團隊決策備忘（最新在最上面）
3. `docs/ARCHITECTURE.md` — 讀與當前任務相關的章節
4. `docs/COURSE_METHODS.md` — 讀與當前任務相關的章節
5. `docs/journal/_index.md` — 確認誰正在改哪些檔案，避免衝突
6. `docs/journal/<成員>.md` — 當前使用者的近期工作日誌（不知道是誰就先問）

## 建置與執行指令

```bash
# Flutter（前端）
flutter run                              # fake backend（預設，不需 Firebase）
flutter run --dart-define=BACKEND=live   # 真實 Firebase 後端
flutter analyze                          # 回報「完成」前必須 0 error / 0 warning
flutter test                             # 全部測試
flutter test test/widget_test.dart       # 單一測試

# Fresh clone 初始設定（firebase_options.dart 已被 gitignore）
cp lib/firebase_options.example.dart lib/firebase_options.dart

# Cloud Functions（後端）
cd functions && npm install
npm run build          # tsc
npm run typecheck      # tsc --noEmit
npm run lint           # eslint
npm run serve          # build + firebase emulators:start --only functions
```

## 關鍵約束

- **絕對禁止** 執行 `git commit`、`git push`、`firebase deploy`、`npm install`、`flutter pub add`
- **只做** 被明確要求的部分 — 不加料、不重構、不主動修未被提及的 bug
- 不得未經使用者同意自行新增 dependency
- 完成後必須用五欄格式回報：`做了 / 檔案 / 沒做 / 驗證 / 建議 commit message`
- 每完成一個功能必須在 `docs/journal/<成員>.md` 寫工作日誌
