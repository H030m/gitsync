# 修 Android 無法取得/刷新 GitHub OAuth token

## Goal

讓 **Android** 版在使用者用 GitHub 登入時,能取得並寫入有效的 GitHub OAuth access token 到 `users/{uid}.githubAccessToken`,使依賴該 token 的後端功能(分支圖 `getCommitGraph`、建 issue `onTaskCreated`、`explainCommit` 抓 diff fallback 等)在 Android 使用者建立的 repo 上也能正常運作。

## 已確認的根因(本 session 診斷)

* 後端 `getCommitGraph` 對 GitHub 回 **401 Bad credentials**(`functions/src/flows/getCommitGraph.ts`),= 存的 token 失效。
* token 用的是 **repo 建立者** `repos.createdBy` → `users/{createdBy}.githubAccessToken`。
* `lib/services/authentication.dart`:
  ```dart
  final accessToken = credential is OAuthCredential ? credential.accessToken : null;
  ```
  **Android 的 `signInWithProvider` 回傳 base `AuthCredential`(非 `OAuthCredential`)→ accessToken = null**。
* `lib/repositories/user_repo.dart` upsert:`if (githubAccessToken != null) 'githubAccessToken': ...` → **null 時跳過**,所以舊(失效)token 永遠保留。
* 結論:**Web(`signInWithPopup`)能取得 token,Android(`signInWithProvider`)取不到** → Android 使用者永遠無法刷新 token。

## Decisions（已與 user 確認）

* **D1 方案 A**:`flutter_web_auth_2` 跑 GitHub authorization-code flow 取 `code` → 新 Cloud Function `exchangeGitHubCode`(client_secret 用 `defineSecret`,**不進 APK**)向 GitHub `POST /login/oauth/access_token` 換 `gho_` token → 寫回 `users/{uid}.githubAccessToken`(同一欄位,**後端消費者不用改**)。
* **D2** 既有 **web 登入取 token 流程保留不動**;本 task 補 Android(及通用)路徑。可讓「連結 GitHub」成為一個獨立動作(登入後可重跑),web 也能沿用此新流程刷 token。
* **D3 加 401 重連觸發**:後端(getCommitGraph 等)遇 GitHub 401 → 回**特定錯誤碼/訊息** → app 偵測到 → 顯示「重新連結 GitHub」入口,引導使用者重跑取 token 流程。
* Cloud Function 屬 Firebase 範圍 → 符合「Flutter + Firebase only」限制。

## Research References

* `research/android-github-token.md` — Q1–Q5 完整分析(Android 無法取 token 是平台層、需次要 OAuth;web-auth/device flow/GitHub App 設計與取捨)。
* `research/android-github-token-internal-map.md` — 取/存/消費 token 的程式碼位置 + 既有 onCall/defineSecret/REGION 慣例。
* `research/android-github-token-recommendation.md` — 排名建議(A 為首選)。

## Technical Approach

1. **新 Cloud Function `exchangeGitHubCode`**(`functions/src/handlers/`,onCall,需 auth):
   - input:`{ code, redirectUri }`;用 `defineSecret('GITHUB_OAUTH_CLIENT_SECRET')`(+ client_id)向 GitHub 換 token;驗證 scope 含 `repo`+`read:user`;寫 `users/{request.auth.uid}.githubAccessToken`;回成功/錯誤。沿用既有 REGION/onCall/錯誤處理慣例。
2. **Client 端「連結 GitHub」流程**(`lib/services/authentication.dart` 或新 service):
   - 用 `flutter_web_auth_2` 開 GitHub authorize URL(client_id + scope `repo read:user` + state + redirect = 自訂 URL scheme)→ 取 `code` → 呼叫 `exchangeGitHubCode` callable。
   - 既有 web `signInWithPopup` 取 token 路徑保留;Android 走新流程。
3. **401 → 重連**:後端 token 消費者(至少 `getCommitGraph`)把 GitHub 401 對映成一個**可辨識的 HttpsError code**(如 `failed-precondition` + 特定 message/code);Flutter 端攔到 → 顯示「重新連結 GitHub」按鈕觸發步驟 2。
4. **設定(owner 一次性,非程式)**:GitHub OAuth App 加 **Authorization callback URL = 自訂 URL scheme**;把 **client_secret** 設成 Firebase secret(`firebase functions:secrets:set`)。

## Acceptance Criteria

* [ ] Android 跑「連結 GitHub」後,`users/{uid}.githubAccessToken` 為**有效** token(可成功打 GitHub `/user`),scope 含 `repo`+`read:user`。
* [ ] 連結後分支圖(getCommitGraph)在該使用者建立的 repo 上能載入(不再 401)。
* [ ] token 失效時:後端回特定錯誤 → app 顯示「重新連結 GitHub」並可重跑流程刷新。
* [ ] web 既有取 token 行為不退步。
* [ ] client_secret 不出現在 APK / client 程式;只在 Cloud Function secret。
* [ ] functions lint/build/test + flutter analyze/test 綠。

## Out of Scope

* 重設既有失效 token 的資料(ops:建立者重跑連結流程)。
* getCommitGraph/explainCommit 的核心邏輯(只加 401 錯誤對映)。
* device flow / GitHub App(方案 B/C,未採用)。

## Requirements（暫定,待收斂）

* Android 登入後 `users/{uid}.githubAccessToken` 應為**有效**且涵蓋既有 scope(`repo` + `read:user`)。
* 不破壞現有 web 登入取 token 的行為。
* token 失效時要能透過「重新登入」刷新(Android + web 皆可)。

## Out of Scope（暫定）

* 重設既有失效 token 的資料(那是 ops:建立者重登;本 task 是讓重登在 Android 真的有效)。
* 後端 getCommitGraph / explainCommit 的邏輯(它們只是 token 的消費者)。

## Technical Notes / 研究方向

* 候選:`flutter_web_auth_2` + GitHub OAuth(authorize → code）→ Cloud Function 用 code 換 token（client_secret 留後端)→ 寫回 Firestore;或 firebase_auth Android 取 credential 的其他 API;或 GitHub Device Flow。
* 約束:MEMORY「final demo:Flutter + Firebase only,禁自建外部 server」——Cloud Function 換 token 屬 Firebase 範圍、應可接受(待確認)。
* 相關檔:`lib/services/authentication.dart`、`lib/repositories/user_repo.dart`、(可能)新 Cloud Function `functions/src/handlers/*`。
* 研究產物寫到 `research/`。

## Owner Setup (一次性,實作後需手動完成才能 end-to-end)

實作已完成(見下方),但因需要 GitHub OAuth App 的 callback URL + Firebase secret,**owner 必須手動設定以下三項**才能真正在 Android 上 end-to-end 跑通(自動化測試無法涵蓋這段):

1. **GitHub OAuth App — Authorization callback URL**
   * 值:`gitsync://oauth/github`(自訂 URL scheme,與 `AppConfig.githubOAuthRedirectUri` 一致)。
   * 可重用現有(web token 背後的)OAuth App,或另建一個 mobile 專用 App。
2. **Firebase Functions secret — client_secret(只在後端)**
   * 指令:`firebase functions:secrets:set GITHUB_OAUTH_CLIENT_SECRET`(貼上該 OAuth App 的 client secret)。
   * **client_secret 永不進 APK / Dart**;只有 `exchangeGitHubCode` Cloud Function 透過 `defineSecret` 讀取。
3. **client_id(public)對齊**
   * App 端:`AppConfig.githubOAuthClientId`(目前預設 placeholder `Ov23liGitSyncClientId`,可用 `--dart-define=GITHUB_OAUTH_CLIENT_ID=<真實 id>` 覆寫)。
   * 後端:`functions/src/config.ts` 的 `GITHUB_OAUTH_CLIENT_ID`(可用 `GITHUB_OAUTH_CLIENT_ID` env 覆寫)。
   * 兩者必須等於同一個 OAuth App 的 client_id。

### 已採用的固定值
* URL scheme:`gitsync`(Android `AndroidManifest.xml` 已加 `flutter_web_auth_2` 的 `CallbackActivity` intent-filter)。
* Redirect URI:`gitsync://oauth/github`。
* Scope:`repo read:user`(`exchangeGitHubCode` 會驗證回傳 scope 含這兩個,缺少則回 `failed-precondition`)。
* 401 marker:後端 `getCommitGraph` 遇 GitHub 401 回 `HttpsError('failed-precondition', 'github-token-invalid: ...')`;app 端 `CommitsViewModel.graphTokenInvalid` 比對此字串顯示「重新連結 GitHub」CTA。
