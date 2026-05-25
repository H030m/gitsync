# GitSync — 整體架構設計 (Architecture Plan)

> **目標**：讓開發者專注於真正重要的事。整合 GitHub + Discord，由 AI Agent 自動拆解任務、分派負載、生成技術交接文件。
>
> **本文件搭配** [`COURSE_METHODS.md`](./COURSE_METHODS.md) **一起看** — Methods 寫「怎麼用課程教的寫法寫 code」，本文件寫「系統由哪些零件組成、各零件的職責、API 與資料 schema」。

---

## 0. 技術選型總結

| 項目 | 選擇 | 理由 |
|---|---|---|
| 前端 | Flutter (iOS + Android) | 課程指定，與 prototype 一致 |
| 後端 Runtime | Firebase Cloud Functions (Node.js 22 + TypeScript) | 課程的 AI Agent / Webhook 教學都在這 |
| 資料庫 | Cloud Firestore | 課程指定，即時同步、與 Functions 整合 |
| Auth | Firebase Auth + GitHub OAuth Provider | 一次拿到 user + GitHub access token |
| AI SDK | OpenAI 官方 Node.js SDK (`openai` npm) | 不勉強套 Genkit，直接用原生 function calling + structured outputs |
| AI Model | OpenAI GPT-4o（推理）+ GPT-4o-mini（輕量）+ text-embedding-3-small（向量） | 已選定 |
| Vector Search | Firestore 原生 `findNearest`（COSINE） | 與 Firestore 同源，免外掛 |
| State Mgmt (Flutter) | `provider` 6.x | 課程指定 |
| Router (Flutter) | `go_router` 14.x | 課程指定 |
| Push | Firebase Cloud Messaging (FCM) | 課程教法 |
| Discord Bot | Cloud Functions HTTPS + Discord Interactions API | 無需常駐 server，符合 Firebase 模型 |
| GitHub 整合 | Webhook → Cloud Functions HTTPS + Octokit REST | 標準作法 |
| 主題色 | Light: `#1565C0`(深藍) / Dark: `#FAB28E`(橘) | Prototype 已決定 |

---

## 1. 系統架構圖

```
┌────────────────────────────────────────────────────────────────────┐
│                         Flutter App (Mobile)                        │
│  ┌─────────┐  ┌────────────┐  ┌──────────┐  ┌─────────┐  ┌──────┐ │
│  │ SignIn  │  │ RepoList   │  │ TaskBoard│  │ Daily   │  │Stats │ │
│  └─────────┘  └────────────┘  └──────────┘  └─────────┘  └──────┘ │
│       │                            │                                │
│       ▼                            ▼                                │
│  AuthService              ViewModels (Provider/ChangeNotifier)      │
│       │                            │                                │
│       └────────────┬───────────────┘                                │
│                    ▼                                                │
│              Repositories (Stream<List<T>> from Firestore)          │
└────────────────────┬───────────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
┌──────────────┐      ┌──────────────────────────────────────────────┐
│ Firebase Auth│      │            Cloud Firestore                    │
│  ─ GitHub    │      │  apps/gitsync/{users,repos,tasks,commits,...}│
│    OAuth     │      └──────────────────────────────────────────────┘
└──────────────┘             ▲           ▲           ▲
                             │           │           │
                  ┌──────────┴───┐  ┌────┴────┐  ┌──┴──────────────┐
                  │ HTTP Triggers│  │Firestore│  │ Callable        │
                  │ (Webhooks)   │  │Triggers │  │ (Flutter→Func)  │
                  └──────────────┘  └─────────┘  └─────────────────┘
                         ▲              │                ▲
                         │              ▼                │
                  ┌──────┴───┐   ┌─────────────┐   ┌─────┴─────┐
                  │  GitHub  │   │   AI Flow   │   │  Flutter  │
                  │  Webhook │   │ (OpenAI SDK)│◄──┤  App      │
                  │  Events  │   │             │   └───────────┘
                  └──────────┘   └─────────────┘
                         ▲              │
                  ┌──────┴───┐          ▼
                  │ Discord  │   ┌─────────────┐
                  │ Bot      │   │  OpenAI API │
                  │(Webhooks │   │ (GPT-4o +   │
                  │ + REST)  │   │  embedding) │
                  └──────────┘   └─────────────┘
                         ▲
                         │
                  ┌──────┴───┐
                  │ Discord  │
                  │ Channel  │
                  └──────────┘
```

---

## 2. Firestore Schema

> 所有 collection 都掛在 `apps/gitsync/` 之下（沿襲課程作法）。

### 2.1 collections

```
apps/gitsync/
├── users/{userId}                              # Firebase Auth UID
│   ├── name: string
│   ├── email: string
│   ├── avatarUrl: string
│   ├── githubLogin: string                     # GitHub username (e.g. "john-developer")
│   ├── githubAccessToken: string (encrypted)   # 用來呼叫 GitHub API
│   ├── discordUserId: string?                  # ★ Discord 18-digit snowflake (e.g. "123456789012345678")
│   │                                           #   讓 RAG 把 discordMessages.authorId 對應回此 user
│   ├── fcmToken: string
│   ├── expertiseTags: string[]                 # ["frontend", "ml"] 自動學習
│   ├── createdAt: Timestamp
│   └── repos/{repoId}                          # subcollection: 此 user 加入的 repo
│       └── role: "owner" | "member"
│
├── repos/{repoId}                              # repoId = `${owner}_${name}` 或 GitHub repo ID
│   ├── name: string                            # "team17/gitsync"
│   ├── url: string
│   ├── githubRepoId: number
│   ├── defaultBranch: string
│   ├── webhookId: number                       # GitHub webhook ID (供刪除用)
│   ├── webhookSecret: string                   # HMAC 驗證
│   ├── discordWebhookUrl: string?              # 用戶設定的 Discord channel webhook (outbound 通知)
│   ├── discordChannelIds: string[]             # 監聽的 Discord channel IDs (給 forwarder bot 對照用)
│   ├── memberIds: string[]                     # 鏡像 subcollection 方便 array-contains query
│   ├── isBreakingDown: boolean                 # 分散式鎖：AI 拆解任務進行中
│   ├── breakdownStartedAt: Timestamp?          # 配 isBreakingDown 用；> 5min 視為卡住可強制解鎖
│   ├── createdAt: Timestamp
│   ├── createdBy: userId
│   │
│   ├── members/{userId}                        # subcollection
│   │   ├── role: "owner" | "admin" | "member"
│   │   ├── activeIssueCount: number            # 即時負載 (供任務分派 AI)
│   │   ├── completedTaskCount: number
│   │   └── lastActiveAt: Timestamp
│   │
│   ├── tasks/{taskId}                          # 看板上的卡片
│   │   ├── title: string
│   │   ├── description: string
│   │   ├── status: "todo" | "in_progress" | "done"
│   │   ├── assigneeId: string?
│   │   ├── dependsOn: string[]                 # taskId 陣列
│   │   ├── githubIssueNumber: number?          # 對應的 GitHub issue
│   │   ├── linkedPRNumbers: number[]
│   │   ├── acceptanceCriteria: string[]
│   │   ├── handoffDoc: string?                 # AI 生成的交接文件 markdown
│   │   ├── handoffGeneratedAt: Timestamp?
│   │   ├── source: "manual" | "ai_breakdown" | "github_issue"
│   │   ├── parentTaskId: string?               # 若由 AI 拆解出來
│   │   ├── createdAt: Timestamp
│   │   ├── createdBy: userId
│   │   └── updatedAt: Timestamp
│   │
│   ├── commits/{commitSha}                     # 由 webhook 寫入
│   │   ├── repoId: string                      # ← 冗餘儲存，供 findNearest 預過濾用
│   │   ├── message: string
│   │   ├── messageEmbedding: Vector            # FieldValue.vector(), 1536 dim (text-embedding-3-small)
│   │   ├── author: { login, name, email }
│   │   ├── url: string
│   │   ├── filesChanged: string[]
│   │   ├── additions: number
│   │   ├── deletions: number
│   │   ├── linkedTaskIds: string[]             # 從 commit message 解析 (e.g. "fix #12")
│   │   ├── aiSummary: string?                  # AI 生成的人話摘要
│   │   └── committedAt: Timestamp
│   │
│   ├── pullRequests/{prNumber}
│   │   ├── repoId: string                      # ← 冗餘儲存
│   │   ├── title: string
│   │   ├── state: "open" | "merged" | "closed"
│   │   ├── author: string
│   │   ├── headBranch: string
│   │   ├── baseBranch: string
│   │   ├── linkedTaskIds: string[]
│   │   ├── commitShas: string[]
│   │   ├── diffStat: { additions, deletions, changedFiles }
│   │   ├── mergedAt: Timestamp?
│   │   └── url: string
│   │
│   ├── discordMessages/{messageId}             # Discord 抓回來的訊息
│   │   ├── repoId: string                      # ← 冗餘儲存，供 findNearest 預過濾用
│   │   ├── channelId: string
│   │   ├── authorId: string                    # Discord user
│   │   ├── content: string
│   │   ├── mentionedUserIds: string[]
│   │   ├── linkedTaskIds: string[]             # AI 推斷
│   │   ├── timestamp: Timestamp
│   │   └── embedding: Vector?                  # FieldValue.vector(), 1536 dim — RAG 用
│   │
│   └── dailyReports/{YYYY-MM-DD}
│       ├── repoId: string
│       ├── summary: string                     # AI 生成
│       ├── completedTasks: string[]
│       ├── memberContributions: { [userId]: { tasksDone, commits } }
│       └── generatedAt: Timestamp
│
└── idempotencyKeys/{eventId}                   # Functions trigger 防重
    └── processedAt: Timestamp
```

### 2.2 Firestore Security Rules

**設計重點**：
1. 不使用 `match /{document=**}` 萬用字元 + `get()`，每次存取 subcollection 會多一次 RTT，浪費 Read Quota
2. 對「應用程式不該直接寫」的 collection（commits / pullRequests / discordMessages / dailyReports）一律 `allow write: if false`，**只允許 Cloud Functions（admin SDK 繞過 rules）寫入**——這也讓 webhook 來源更安全
3. 對「應用程式會寫」的 collection（tasks）才接受 `get()` 確認 membership

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // 1. 使用者文件：只有本人可讀寫
    match /apps/gitsync/users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // 子集合 repos/ 鏡像 — 只有本人讀寫
      match /repos/{repoId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }

    // 2. Repo 根文件：只有 member 可讀；create 開放給已登入；update 限 member
    match /apps/gitsync/repos/{repoId} {
      allow read, update: if request.auth != null
                          && request.auth.uid in resource.data.memberIds;
      allow create: if request.auth != null;
      allow delete: if false; // 只能透過 Cloud Function removeRepo

      // 2a. members — 只能 Cloud Functions 寫，member 可讀
      match /members/{memberId} {
        allow read: if request.auth != null
                    && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
        allow write: if false;
      }

      // 2b. tasks — member 可讀寫（這是唯一需要 get() 驗 membership 的 subcollection）
      match /tasks/{taskId} {
        allow read, write: if request.auth != null
                           && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
      }

      // 2c. commits / pullRequests / discordMessages / dailyReports — 只允許 Cloud Functions 寫
      match /commits/{commitSha} {
        allow read: if request.auth != null
                    && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
        allow write: if false;
      }
      match /pullRequests/{prNumber} {
        allow read: if request.auth != null
                    && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
        allow write: if false;
      }
      match /discordMessages/{messageId} {
        allow read: if request.auth != null
                    && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
        allow write: if false;
      }
      match /dailyReports/{date} {
        allow read: if request.auth != null
                    && request.auth.uid in get(/databases/$(database)/documents/apps/gitsync/repos/$(repoId)).data.memberIds;
        allow write: if false;
      }
    }

    // 3. Idempotency keys — 只 Cloud Functions 用
    match /apps/gitsync/idempotencyKeys/{eventId} {
      allow read, write: if false;
    }
  }
}
```

> **權衡**：`tasks` 與其他 read-only subcollection 仍各做一次 `get()` 驗 membership，但**單次 `get()` 在同一個 request 內會被 Firestore 自動 cache**，所以一次 `streamTasks()` 全 page 只算 1 次 get。這比萬用字元 + 每筆 `get()` 便宜許多。

---

## 3. 前端 (Flutter) — 頁面對應

依 prototype `references/GitSync/src/app/routes.tsx` 設計 Flutter 路由：

```
/                       → SignInPage
/repos                  → RepoListPage
/repos/add              → AddRepoPage
/repos/:repoId          → ShellRoute (RepoLayout，含 BottomNav)
  ├── /tasks            → TasksBoardPage (看板 / 關聯圖兩個 Tab)
  │   ├── /add          → AddTodoPage (3 步驟：輸入 → AI 生成 → 確認)
  │   └── /:taskId      → TaskDetailsPage (含 handoff)
  ├── /daily            → DailyViewPage (日報 / commit / DC 群三 Tab)
  ├── /stats            → StatsViewPage (貢獻度 / 進度表)
  └── /settings         → SettingsPage
/notify                 → NotifyScreen (push 通知開啟跳轉)
```

### 主要 ViewModels

| ViewModel | 訂閱來源 | 提供給 |
|---|---|---|
| `AuthViewModel` | `FirebaseAuth.idTokenChanges()` | 全域 |
| `RepoListViewModel` | `users/{uid}/repos` stream | RepoListPage |
| `TasksBoardViewModel` | `repos/{repoId}/tasks` stream | TasksBoardPage, TaskDetailsPage |
| `MembersViewModel` | `repos/{repoId}/members` stream | TaskAssign dialog, StatsView |
| `DailyReportViewModel` | `repos/{repoId}/dailyReports` + 今日 commits stream | DailyViewPage |
| `CommitsViewModel` | `repos/{repoId}/commits` stream (limit 50) | DailyViewPage |
| `DiscordMessagesViewModel` | `repos/{repoId}/discordMessages` stream | DailyViewPage |
| `StatsViewModel` | derived from TasksBoardViewModel + CommitsViewModel | StatsViewPage |
| `ThemeModeNotifier` | local SharedPreferences | 全域 |

---

## 4. Cloud Functions — 後端 API

### 4.1 Callable Functions（從 Flutter 直接呼叫）

> 一律走 `firebase-functions/v2/https` 的 `onCall`，region = `us-west1`。

| Function | 輸入 | 輸出 | 用途 |
|---|---|---|---|
| `addRepo` | `{ githubUrl: string }` | `{ repoId }` | 解析 URL → 呼叫 GitHub API 驗證 → 註冊 webhook → 寫 Firestore |
| `removeRepo` | `{ repoId }` | `{}` | 刪除 webhook + Firestore docs |
| `breakdownTask` | `{ repoId, goal: string }` | `{ subtasks: [...] }` | AI Flow — 任務拆解（自帶 `isBreakingDown` 鎖）|
| `forceUnlockBreakdown` | `{ repoId }` | `{}` | 強制解 `isBreakingDown` 鎖（卡 > 5min 時前端顯示「重置」按鈕呼叫）|
| `assignTask` | `{ repoId, taskId }` | `{ assigneeId, reason }` | AI Flow — 動態分派 |
| `generateHandoff` | `{ repoId, taskId }` | `{ handoffMarkdown }` | AI Flow — 交接文件 |
| `summarizeDay` | `{ repoId, date: string }` | `{ summary }` | AI Flow — 日報生成 |
| `setDiscordWebhook` | `{ repoId, webhookUrl, channelIds[] }` | `{}` | 設定 Discord outbound webhook + 監聽頻道 |
| `subscribeToTopic` | `{ token, topic }` | `{}` | FCM web push（同課程） |

### 4.2 HTTP Webhook Functions（外部呼叫）

| Function | 來源 | 處理 |
|---|---|---|
| `githubWebhook` | GitHub | 驗證 HMAC → 依 event 類型分派 (`push`/`pull_request`/`issues`) → 寫 Firestore |
| `discordMessageIngest` | 使用者自架的 forwarder bot | 驗共享密鑰 → 寫 `discordMessages/{messageId}`；詳見 §7.2 |

### 4.3 Firestore Triggers（事件驅動）

> **職責切分原則**：HTTP webhook 只做「驗證 + 把外部 raw payload 標準化後寫入 Firestore 文件」；所有「解析業務語意 / 呼叫 OpenAI / 跨文件更新」一律下沉到 Firestore Trigger。這樣才能：
> 1. webhook 在 3 秒內回完外部（GitHub / Discord 不會 retry / 不會 timeout）
> 2. AI 重邏輯都有 idempotency key 保護（trigger 內統一加），不會被外部重送搞壞

| Trigger | 事件 | 動作 |
|---|---|---|
| `onTaskCreated` | tasks/{taskId} create | 若 `source == "manual"`，可選擇呼叫 AI 自動分派；建 GitHub issue |
| `onTaskUpdated` | tasks/{taskId} update | 若 `status` 變 "done"：發 FCM 給下游 (`dependsOn` 反向查) + 推 Discord webhook + 觸發 `generateHandoff` |
| `onCommitCreated` | commits/{sha} create | 1. idempotency check → 2. `shouldSkipEmbedding(message)` 過濾 → 3. 解析 `#N`/`fixes #N` 找對應 task 寫 `linkedTaskIds` → 4. 算 `messageEmbedding` → 5. 生成 `aiSummary` |
| `onPRMerged` | pullRequests/{n} update where state→"merged" | idempotency check → transaction 內把 `linkedTaskIds` 對應 tasks 標 done + 加計 member counter |
| `onDiscordMessageCreated` | discordMessages/{id} create | idempotency check → 過濾規則複查 → 算 embedding → AI 推斷 `linkedTaskIds` 並補回去 |
| `scheduledDailyReport` | Pub/Sub schedule 18:00 daily | 扇出（見 §5.4）→ 每 repo 一個 `dailyReportWorker` instance |
| `scheduledUnstickBreakdown` | Pub/Sub schedule 每 10 分鐘 | 掃 `repos` where `isBreakingDown == true AND breakdownStartedAt < now - 5min` → 強制解鎖（兜底 §5.1）|

**所有 trigger 都要做 idempotency key check**（見 [COURSE_METHODS § 6.2](./COURSE_METHODS.md#62-必學idempotency-key-模式)）。

### 4.4 併發 (Race Condition) 防禦守則

Webhook / trigger 會併發執行（GitHub 一次 push 10 個 commits → 10 個 `onCommitCreated` 同時跑）。違反以下任一規則 → 計數會錯、狀態會被互蓋。實作細節照 [`COURSE_METHODS.md §6.2`](./COURSE_METHODS.md#62-必學idempotency-key-模式)。

**規則 A — 數值欄位禁止「先讀後寫」**

任何 counter（`members.activeIssueCount`、`members.completedTaskCount`、未來任何累加欄位）都必須用 Firestore 的 atomic 操作（`FieldValue.increment(±1)`），不可以先 `get` 拿舊值再算 `+1` 寫回。原因：10 個 trigger 併發時，每個讀到的舊值都相同，最後互蓋變成只 +1 而非 +10。

**規則 B — 跨欄位 / 跨文件狀態變更必用 transaction**

例如 `onPRMerged` 要同時把 task 標 done 並加計 member counter，必須包在 `runTransaction` 裡。transaction 內先 read 確認 task 還沒被標 done（idempotent guard），再做 update。否則兩個 trigger 同時觸發會雙重加計。

**規則 C（最重要）— Firestore Trigger 是 at-least-once 交付，必須做 idempotency**

Firebase 不保證 trigger 正好一次。底層網路抖動、retry 機制都會讓同一個 event 觸發多次。`FieldValue.increment(1)` 是原子操作能避免併發互蓋，但**擋不住「同一事件被送兩次 → 加兩次」**。

標準寫法：每個 trigger 開頭跑一個 transaction：(a) get `apps/gitsync/idempotencyKeys/{event.id}` → (b) 若已存在 return → (c) 否則 set 已處理戳記 → 跳出 transaction 後再跑業務邏輯。範例見 [`COURSE_METHODS.md §6.2`](./COURSE_METHODS.md#62-必學idempotency-key-模式)。

**規則 D — idempotency mark 與慢速副作用不可放同一 transaction**

一旦 idempotency transaction commit，event 就被標記成「已處理」；若隨後的 OpenAI / GitHub API 呼叫失敗，整個 event 不會 retry — 資料就缺了。

正確順序是：先 transaction 標記 idempotency key、退出 transaction 後才呼叫 OpenAI embed / summary、最後再把結果寫回原文件。

若擔心外部呼叫失敗導致欄位永遠為 null：兩種選擇——
1. 嚴格模式：標記前先把 event 留在 `pendingEvents/{eventId}` queue，做完才從 queue 刪
2. 寬鬆模式（建議 MVP）：接受偶爾的 `aiSummary` / `embedding` 為 null（這只是錦上添花，不影響正確性），UI 上提供「重新生成」按鈕讓使用者手動補。

---

## 5. AI Agent 設計（三個核心 Flow）

> 全部用 OpenAI 官方 SDK：**structured outputs**（`response_format` + zod schema）保證 JSON 正確、**function calling**（tool use）做 agentic 自主檢索。詳細寫法見 [`COURSE_METHODS.md §8`](./COURSE_METHODS.md#8-ai-agent--openai-sdk-直接使用後端)。
>
> 每個 flow 是一個 async function 在 `functions/src/flows/` 下，由 `handlers/` 的 `onCall` 包成 Firebase Callable。

### 5.1 Flow 1 — `breakdownTaskFlow`（任務拆解）

對應 prototype 核心功能 01。

**Input**: `{ repoId: string, goal: string }`
**Output**: `{ subtasks: [{ title, description, dependsOn: number[], estimatedHours }] }`

**dependsOn 型別約定（解決 LLM 生不出 taskId 的問題）**：

| 階段 | dependsOn 型別 | 內容 |
|---|---|---|
| AI output (Zod schema) | `number[]` | **0-based 陣列索引**（指向同一輪輸出的其他 subtask 位置）|
| Flutter / Firestore | `string[]` | **真實的 taskId**（Firestore doc id）|

中間的「索引 → taskId」翻譯由 Step 4-6 後端處理，**Flutter 端永遠只看到 taskId**。

**Steps**:

```
Step 1 — fetchProjectContext()                 [純 TS]
  ├─ Read repos/{repoId} + existing tasks
  ├─ Read recent 20 commits via GitHub API
  ├─ Read repo README (optional)
  └─ output: projectContextString

Step 2 — openai.chat.completions.parse(...)    [structured output via zod]
  ├─ system: breakdownTaskSystem
  ├─ user: projectContext + goal
  ├─ response_format: zodResponseFormat(BreakdownOutputSchema)
  └─ output: [{ title, description, dependsOn: number[], estimatedHours }, ...]
                                       ↑ 0-based 索引

Step 3 — detectCycles(subtasks)                [純 TS DFS on index graph]
  └─ if cycle found ─→ Step 3b

Step 3b — re-prompt with cycle info            [agentic 自我修正]
  ├─ Append previous response + error message
  └─ output: fixed subtasks

Step 4 — pre-generate taskIds                  [純 TS]
  ├─ const ids = subtasks.map(_ => tasksCollection.doc().id)   // Firestore auto-id
  └─ output: ids: string[]

Step 5 — translate index → taskId              [純 TS]
  └─ const docs = subtasks.map((s, i) => ({
       id: ids[i],
       ...s,
       dependsOn: s.dependsOn.map(idx => ids[idx]),  // index → real taskId
     }));

Step 6 — batch write Firestore                  [transaction]
  ├─ for each doc: tx.set(tasksCollection.doc(doc.id), doc)
  └─ also set repos/{repoId}.isBreakingDown = false（解鎖）
```

**Prompt**: `functions/src/prompts/breakdownTask.ts`（純字串）
**Schema**: `functions/src/types.ts`（zod；dependsOn 在這層必須是 `number[]`）
**Flow**: `functions/src/flows/breakdownTask.ts`

**併發鎖（重要）— 防止重複拆解**

兩個成員同時點「AI 拆解」、或同一人連點兩下，會跑兩遍 flow → 同 goal 拆出兩套任務 + 兩倍 GitHub Issue。Callable Function 不自帶併發鎖，必須自己加。

**雙層防護**：

1. **前端**：按下按鈕後立刻把該 button 設成 disabled、顯示 `CircularProgressIndicator`，callable 回傳前不准再按。用 StatefulWidget 的 `_isBreakingDown` flag 控制。

2. **後端**：`breakdownTaskFlow` 開頭跑一個 transaction：讀 `repos/{repoId}.isBreakingDown` → 若已是 `true`，throw `HttpsError('already-exists', ...)` 提示「拆解進行中」；否則 set 為 `true` 並記 `breakdownStartedAt: serverTimestamp()`。後續所有業務邏輯包在 `try ... finally`，無論成功失敗都在 `finally` 把 flag set 回 `false`（用 `.catch(() => {})` 吞錯避免影響主流程）。

**自動解鎖兜底**：若 function 半途 crash 沒走到 finally，flag 會永遠卡 `true`：
- 後端：`scheduledUnstickBreakdown` 排程每 10 分鐘掃所有 repo，找 `isBreakingDown == true AND breakdownStartedAt < now - 5min` → 強制解鎖
- 前端：APP 偵測到 `breakdownStartedAt` 超過 5 分鐘前還在鎖，顯示「拆解卡住？點此重置」按鈕，呼叫 `forceUnlockBreakdown` callable

### 5.2 Flow 2 — `assignTaskFlow`（動態任務分派）

對應 prototype 核心功能 02。

**Input**: `{ repoId: string, taskId: string }`
**Output**: `{ assigneeId: string, reasoning: string }`

**Steps（agentic — 用 OpenAI function calling，讓 agent 自己決定要拉哪些資料）**:

```
Setup — 註冊 4 個 tools:
  • readTeamState(repoId)                → 每位 member 的 { userId, name, githubLogin, discordUserId,
                                            activeIssueCount, expertiseTags, lastActiveAt }
                                            ← 含三組身份對照，下游 RAG 才能把 Discord 對話與 Commit
                                              作者對齊
  • searchMemberCommits(memberId, query) → Firestore vector search on commits
  • getTaskDependents(repoId, taskId)    → 下游有誰會被擋
  • finalizeAssignment(assigneeId, reason) → 最終決定（呼叫即結束 loop）

Agentic Loop (max 5 round):
  ├─ openai.chat.completions.create({ tools, tool_choice: 'auto' })
  ├─ if msg.tool_calls 為空 && finalizeAssignment 已被呼叫過 → 結束
  ├─ else 平行執行 agent 要求的 tools，把結果塞回 messages
  └─ 下一輪
```

Agent 會根據任務內容決定要不要做 vector search、要不要查依賴下游；不是每次都全跑。

### 5.3 Flow 3 — `generateHandoffFlow`（交接文件）

對應 prototype 核心功能 03。

**Input**: `{ repoId: string, taskId: string }` （**通常由 `onTaskUpdated` trigger 自動觸發**）
**Output**: `{ handoffMarkdown: string }`

**Steps（agentic — 完整 function calling loop + 自我審查）**:

```
Setup — 註冊 tools:
  • readTeamRoster(repoId)                      → 同 §5.2 readTeamState；回三組身份對照
                                                  (userId / githubLogin / discordUserId)
                                                  ← Agent 在 draft 時把 Discord/Git author 翻回真實姓名
  • findDownstreamTask(repoId, completedTaskId)
  • listRelatedCommits(repoId, taskId)
  • getCommitDiff(repoId, sha)                  → 經 GitHub API
  • searchDiscordMessages(repoId, query)        → Firestore vector search；每筆會回 authorId
                                                  (Discord snowflake)，Agent 自行用 readTeamRoster
                                                  做姓名對齊
  • searchPastCommits(repoId, query)            → Firestore vector search
  • draftHandoff(markdown)                      → 提交草稿，trigger 自我審查
  • finalizeHandoff(markdown)                   → 通過審查，結束 loop

Phase 1 — Draft Loop (max 5 round):
  ├─ Agent 自由呼叫前 5 個 tools 收集資料
  └─ 最後呼叫 draftHandoff(markdown)

Phase 2 — Self Review (1 round):
  ├─ 餵 draft + downstreamTask.acceptanceCriteria 給 GPT-4o-mini
  ├─ Prompt: "Rate this handoff 1-5 for the next engineer. List gaps."
  └─ if score < 4 && totalRounds < 5 → 回 Phase 1，把 gaps 加進 messages
      else → 呼叫 finalizeHandoff(markdown) 結束
```

**自動觸發**：由 Firestore `onTaskUpdated` trigger 在 task 變 done 時自動呼叫此 flow，結果寫回 `tasks/{taskId}.handoffDoc`。

### 5.4 Flow 4 — `summarizeDayFlow`（日報生成）

**Input**: `{ repoId: string, date: string }`
**Output**: `{ summary: string, memberContributions: {...} }`

查當日 commits + completed tasks + discord 討論 → 寫成兩三句的人話日報。

**排程觸發 — 用 Cloud Tasks 扇出，不要 for-loop**

Cloud Functions 單次執行上限 540 秒（9 分鐘）。若每日 18:00 用一個 function 順序跑 50 個 repo 的 `summarizeDayFlow`（每個約 5–10 秒）→ 直接 timeout 崩潰。

採用兩階段架構：

- **`scheduledDailyReport`** — `onSchedule` Cloud Function，每日台北時間 18:00 觸發。**只做扇出**：掃 `apps/gitsync/repos` 所有文件 ID，為每個 repoId 在 `daily-report-queue` 上建一個 Cloud Task，task 內容包含 repoId + 今日日期（ISO 字串），target 指向 `dailyReportWorker` 的 HTTPS URL。本身回 200 後立即結束。

- **`dailyReportWorker`** — `onRequest` Cloud Function，由 Cloud Tasks 觸發。每個 instance 只處理一個 repoId，呼叫 `summarizeDayFlow({ repoId, date })`。Cloud Tasks 自動水平擴展，多個 worker 平行跑，互不影響。

部署前需手動建立 queue（**使用者親自跑**，AI 不可）：

```bash
gcloud tasks queues create daily-report-queue --location=us-west1
```

### 5.5 Prompt Caching 與成本控制

OpenAI 對 ≥1024 tokens 的 prompt prefix 自動 cache（無需設定，自動省 50%）。**設計每個 flow 時把不變的 system prompt + project context 放最前面**：

```
[system prompt — 不變]            ← cached
[project context — 同 repo 不變]   ← cached
[task-specific query]              ← 每次不同
```

對於高頻函式（`onCommitCreated` → AI summary），改用 `gpt-4o-mini` 把單次成本壓低 10x。

### 5.6 Vector Search 索引與預過濾

**Firestore findNearest 限制**：
1. 必須先建 vector index（不是預設）
2. 同一 query 內若要加 `where` filter，必須在**建立 index 時**就把 filter 欄位一起索引

GitSync 用法：在 `commits` collection group 上建一個 `messageEmbedding` + `repoId` 的複合 vector index。

**建立索引**（部署時一次性）：

```bash
# commits 的 vector index（含 repoId 預過濾）
gcloud firestore indexes composite create \
  --collection-group=commits \
  --query-scope=COLLECTION_GROUP \
  --field-config field-path=repoId,order=ASCENDING \
  --field-config field-path=messageEmbedding,vector-config='{"dimension":1536,"flat":{}}'

# discordMessages 的 vector index
gcloud firestore indexes composite create \
  --collection-group=discordMessages \
  --query-scope=COLLECTION_GROUP \
  --field-config field-path=repoId,order=ASCENDING \
  --field-config field-path=embedding,vector-config='{"dimension":1536,"flat":{}}'
```

或寫在 `firestore.indexes.json`：

```json
{
  "indexes": [
    {
      "collectionGroup": "commits",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "repoId", "order": "ASCENDING" },
        { "fieldPath": "messageEmbedding", "vectorConfig": { "dimension": 1536, "flat": {} } }
      ]
    }
  ]
}
```

**寫入前必須過濾自動產生的 commit message**

不過濾的話，向量庫會被 `Merge branch ...` / `Bump version 1.2.3` / `Update README.md` 等沒語義價值的訊息污染，且白燒 embedding token。在 `functions/src/tools/commitFilter.ts` 寫一個 `shouldSkipEmbedding(message)` 函式，用 regex 黑名單判斷第一行是否屬於以下類別：

- `Merge branch` / `Merge pull request` / `Merge remote-tracking branch` 開頭
- `Revert "..."` 開頭
- `chore(release|deps|version): bump/update/upgrade ...` 等版本管理 commit
- 純版本號開頭（如 `v1.2.3`、`1.2.3`）
- 預設模板訊息（`Initial commit`、`Update README.md`、`Update .gitignore`）
- 機器人標記（`Auto-merge`、`Automated commit`、`[bot]` 開頭）
- 第一行去除空白後長度 < 5 字元（資訊量太低）

命中任一條 → `onCommitCreated` trigger 直接把 `messageEmbedding` 與 `aiSummary` 設為 null 跳過 OpenAI 呼叫。

**反向依賴查詢的非向量索引（同樣別忘）**

`onTaskUpdated` trigger 在 task 變 done 時要查「誰在等我」，會用到 `where('dependsOn', 'array-contains', completedTaskId)` 結合 `where('status', '==', 'todo')` 的複合查詢。**沒建索引 trigger 會直接 crash**，下游卡片永遠不會被喚醒（demo 當場露餡）。

建立索引（**使用者親跑**，AI 不可）：

```bash
gcloud firestore indexes composite create \
  --collection-group=tasks \
  --query-scope=COLLECTION_GROUP \
  --field-config field-path=dependsOn,array-config=CONTAINS \
  --field-config field-path=status,order=ASCENDING
```

或直接寫入 `firestore.indexes.json`，內容是一個 `indexes` 陣列項目，`collectionGroup: "tasks"`、`queryScope: "COLLECTION_GROUP"`、`fields` 包含兩欄：`dependsOn`（arrayConfig: CONTAINS）與 `status`（order: ASCENDING），然後執行 `firebase deploy --only firestore:indexes`。

**Vector search 查詢時必須帶 `where('repoId', '==', repoId)` 預過濾**

`findNearest` 對 collection group 查詢時，若不加 repoId filter 會 across 所有 repo（跨 repo 洩漏）。寫法是：`db.collectionGroup('commits').where('repoId', '==', repoId).findNearest({ vectorField, queryVector, limit, distanceMeasure: 'COSINE' })`。`queryVector` 用 `FieldValue.vector(embedding)` 包裝。

---

## 6. GitHub 整合

### 6.1 OAuth 登入

用 Firebase Auth 的 GitHub provider，scope 申請：
```
repo            # 讀寫 issue / PR / webhook
read:user       # 讀 user info
```

登入後 `getCredential` 拿到 `accessToken`，存到 `users/{uid}.githubAccessToken`（**正式環境要加密**，可用 Cloud KMS）。

### 6.2 加 Repo 流程 (`addRepo` Callable)

```
1. Flutter 送 githubUrl ─→ Cloud Function
2. 用 user 的 GitHub token + Octokit 驗證 repo 存在且 user 有權限
3. 註冊 webhook：
   POST /repos/{owner}/{repo}/hooks
   - url: https://<region>-<project>.cloudfunctions.net/githubWebhook
   - secret: 隨機產生並存到 repos/{repoId}.webhookSecret
   - events: ["push", "pull_request", "issues", "issue_comment"]
4. 寫 Firestore：apps/gitsync/repos/{repoId}
5. 寫 users/{uid}/repos/{repoId}：role = "owner"
```

### 6.3 Webhook 處理 (`githubWebhook` HTTPS)

`githubWebhook` Cloud Function 收到 GitHub 推來的 POST 後依序處理：

1. **驗 HMAC 簽章** — 從 `x-hub-signature-256` header 取簽章，從 payload 的 `repository.owner.login` + `name` 組出 `repoId` 並去 Firestore 查 `repos/{repoId}.webhookSecret`，以 HMAC-SHA256 驗 raw body。失敗回 401。
2. **Idempotency** — 取 `x-github-delivery` header（GitHub 為每次推送配發的唯一 ID）當 idempotency key，已處理過直接回 200 `dup`。
3. **依 event 類型派發** — 看 `x-github-event` header，分派到 `handlePush` / `handlePR` / `handleIssue`。
4. **回 200** — GitHub 對 webhook 有 10 秒 timeout，逾期會 retry，因此 handler 必須極快回應。

**重要原則**：webhook handler **只負責「raw payload → 標準化 → 寫入 Firestore」**，不解析業務語意、不呼叫 OpenAI、不跨文件更新。所有後續邏輯下沉給 §4.3 對應的 Firestore Trigger（trigger 才有 idempotency key 保護）。這樣 webhook 永遠在毫秒級回應 GitHub（避免 retry 風暴），重邏輯 / 重 retry 集中在 trigger 層。

**`handlePush`** — 只做寫入：對 payload 中每個 commit，set `repos/{repoId}/commits/{sha}`，欄位含 `repoId`（冗餘）、`message`、`author`、`url`、`filesChanged`、`additions`、`deletions`、`committedAt`。**不解析** commit message 的 `#N`、**不算 embedding**、**不寫 `linkedTaskIds`** — 由 `onCommitCreated` trigger 統一處理。

**`handlePR`**（只在 `action == "closed"` 且 `merged == true` 時處理）— 只做寫入：set `pullRequests/{n}`，欄位含 `repoId`（冗餘）、`title`、`state: "merged"`、`commitShas`、`headBranch`、`baseBranch`、`mergedAt`。**不更新** 對應 tasks 的 status — 由 `onPRMerged` trigger 用 transaction 處理。

**`handleIssue`** — 只做寫入：若 issue 對應系統建立的 task，同步該 task 的 `githubIssueNumber` / `state`；其餘交給 trigger。

### 6.4 GitHub API client 包裝

把 Octokit 包成 `functions/src/services/githubClient.ts`，對外暴露兩個函式：

- `getOctokit(userAccessToken)` — 用使用者的 GitHub OAuth token 建立一個 Octokit 實例。
- `getRecentCommits(owner, repo, accessToken)` — 呼叫 Octokit 的 `repos.listCommits`，回最近 20 個 commit（給 `breakdownTaskFlow` 拉專案上下文用）。

之後需要新增其他 GitHub 操作（如建 issue、查 PR diff）就加到同一個檔案，保持「所有 GitHub API 呼叫只走這層」的紀律。

---

## 7. Discord 整合（簡化版）

> **設計取捨**：原本規劃 slash command + interactions endpoint + Cloud Tasks worker 的完整 bot 架構（3 秒回應限制 + Deferred Response + Cloud Tasks 解耦）整套都不做。改用更簡單的「**訊息直接寫 Firestore，App 端負責整理**」模型。
>
> 換言之：Discord 不是「指令介面」，而是**單向資料源**——成員在 Discord 自然聊天，所有訊息存進 Firestore，APP 端在需要時（如生成交接文件、組日報）才去 RAG 搜尋這些訊息。

### 7.1 兩條資料流

```
┌─────────────────────────────┐                ┌──────────────────────────────┐
│  Discord (團隊聊天頻道)       │                │  Discord Channel (notify 用) │
└──────────────┬──────────────┘                └──────────────▲───────────────┘
               │                                              │
   (Inbound: 訊息進來)                          (Outbound: 任務完成通知)
               │                                              │
               ▼                                              │
  ┌──────────────────────────────┐         ┌─────────────────┴──────────────┐
  │ discordMessageIngest         │         │ onTaskUpdated (Firestore Trigger)│
  │ HTTPS Cloud Function         │         │                                  │
  │ 由使用者另外設置的 forwarder │         │ 任務 status → "done" 時觸發       │
  │ 把 message POST 過來         │         │ POST Discord channel webhook URL │
  └──────────────┬──────────────┘         └──────────────────────────────────┘
                 │
                 ▼
       apps/gitsync/repos/{repoId}/discordMessages/{messageId}
```

### 7.2 Inbound — 訊息怎麼進 Firestore

**重點**：Cloud Functions 是 stateless 的，**不能維持常駐 Discord bot 連線**。所以「捕捉 Discord 所有訊息」這件事必須由 Cloud Functions **以外** 的東西做。三種選項（任選其一）：

| 選項 | 怎麼做 | 適合場景 |
|---|---|---|
| **A. 本機 / VPS 跑 discord.js bot** | 寫一個小 bot，`messageCreate` event → POST 到 `discordMessageIngest` Cloud Function | 開發期 / Demo 期最簡單，使用者自己跑 |
| **B. Discord Channel Outbound Webhook + 中繼** | 設定 channel 的 webhook，但 Discord 沒有原生「訊息送出時轉發到我的 URL」功能——須搭配 [Zapier / IFTTT / n8n] 或 Discord-MCP 之類中繼 | 不想自己跑 bot |
| **C. Cloud Run 跑常駐 discord.js** | discord.js bot 部署到 Cloud Run（min-instance=1） | 正式上線；非 MVP |

**Demo 選 A**（使用者自己在本機 / 一台 VPS 跑 forwarder bot）。

**Cloud Function `discordMessageIngest`** 是 `onRequest` HTTP 端點，行為：

1. **驗共享密鑰** — header `x-ingest-secret` 比對 `DISCORD_INGEST_SECRET`（不是 Discord 自家簽章——這個 endpoint 不直接面向 Discord）。不符回 401。
2. **驗 payload 結構** — body 期望含 `repoId`、`messageId`、`channelId`、`authorId`、`authorName`、`content`、`mentionedUserIds`、`timestamp`。任一缺漏回 400。
3. **Idempotency** — `messageId` 是 Discord 端的全域唯一 ID，直接當文件 ID。先 `get` 看是否存在，存在直接回 200 `dup`。
4. **寫入** — `repos/{repoId}/discordMessages/{messageId}`，欄位含 `repoId`（冗餘，供 vector 預過濾）、`channelId`、`authorId`、`authorName`、`content`、`mentionedUserIds`、`linkedTaskIds: []`（留空，等 `onDiscordMessageCreated` trigger 用 AI 推斷後補上）、`timestamp`（轉成 Firestore Timestamp）、`ingestedAt: serverTimestamp()`。
5. **不算 embedding** — 那是 trigger 的事，這層不做（職責切分原則）。

**Forwarder bot**（使用者另外跑，**不在 functions repo 內**）需具備以下能力：

- **連線** — 用 `discord.js`，啟用 `Guilds` / `GuildMessages` / `MessageContent` 三個 intents
- **頻道對照** — 維護一份 `channelId → repoId` 的對應表（手動設定）；收到訊息先查表，不在表內的頻道直接忽略
- **過濾雜訊**（**重要**，在 forwarder 端就過，不要把噪聲送到 ingest endpoint，省 invocation + token）。`shouldKeepMessage(msg)` 規則：
  - bot 發的訊息一律忽略
  - 純附件 / 純貼圖（無文字內容）忽略
  - 第一行 trim 後長度 < 5 字元忽略
  - 命中以下任一 regex 忽略：純表情字（`haha`/`哈+`/`呵+`/`lol`/`gg` 等）、純應答詞（`ok`/`好`/`收到`/`了解`/`謝謝` 等）、純 `+1` / `-1`、純 emoji 字串、純連結
- **指數退避重試**（`sendWithRetry`，**重要**，對抗冷啟動 + 429）：
  - 上限 4 次重試，base delay 1 秒，指數退避（1s → 2s → 4s → 8s），加 0–500ms jitter 避免同時打
  - 單次 timeout 8 秒（用 `AbortController` 包，覆蓋冷啟動的 1.5–3 秒）
  - 4xx 非 429（如 401、400）直接放棄不重試；5xx 與 429 才重試
  - 4 次全失敗 → log critical 後丟包（不無限重試卡死）
- **不阻塞主執行緒** — `messageCreate` 事件 handler 內**不 await** `sendWithRetry`，讓它在背景跑，否則一個訊息卡住會擋住 discord.js 後續事件

**為什麼必須要 retry**：Cloud Functions 在閒置後啟動需 1.5–3 秒；Discord 一個 channel 突然多人發言時，瞬間多個並發請求會同時撞冷啟動（後續實例還在 spin up）+ 429。沒 retry → 對話直接 drop → RAG 缺資料。指數退避加 jitter 能把重試打散，等到 Functions 暖機完成。

**第二層防護**：`discordMessageIngest` Cloud Function 端也再過一次相同的雜訊規則（防止 forwarder 規則有漏 / 多個 forwarder 不一致 / 或之後有人改 forwarder 沒改 server）。把規則邏輯抽到 `functions/src/tools/discordFilter.ts`，與 forwarder 規則同步維護。

### 7.3 Outbound — 任務完成時通知 Discord

用 Discord channel webhook URL（不需要 bot token，不需要 Cloud Tasks——這是純單向 POST，沒有 3 秒回應問題）。

`repos/{repoId}` 已有 `discordWebhookUrl: string?` 欄位（使用者建立 channel webhook 後填入）。

實作放在 `functions/src/tools/discordNotify.ts`，提供 `notifyDiscord(webhookUrl, content)`：若 webhookUrl 為空就直接 return；否則 POST 一個 JSON `{ content }` 到 webhook URL，失敗用 `.catch()` 吞錯記 log 即可——通知不到不該影響主流程（Firestore 寫入應已完成）。

`onTaskUpdated` trigger 內呼叫情境：當 `before.status !== 'done' && after.status === 'done'`，讀 repo 取 webhook URL，組訊息「✅ \`<task.title>\` 已完成。下一步：\`<nextTask.title>\`」推送即可。

### 7.4 不做的部分（從原規劃移除）

- ❌ `discordInteractions` Cloud Function（接 slash command）
- ❌ Cloud Tasks queue (`discord-tasks`) + `discordAsyncWorker`
- ❌ Discord Ed25519 簽章驗證（不需要，因為不接 Discord interactions）
- ❌ Slash commands (`/gitsync-check`, `/gitsync-daily`, `/gitsync-assign`, `/gitsync-link`)
- ❌ `DISCORD_PUBLIC_KEY` secret

替代：所有「主動查詢 / 觸發」的動作都改在 **GitSync APP 內** 做（按鈕 + Firebase Callable）。Discord 端只負責「聊天就好」。

---

## 8. 主題與設計 Token

### 8.1 顏色（取自 prototype `theme.ts`）

```dart
// lib/theme/colors.dart
class AppColors {
  // Primary (深藍系)
  static const primary = Color(0xFF1565C0);
  static const primaryLight = Color(0xFF90CAF9);
  static const primaryDark = Color(0xFF0D47A1);

  // Dark mode accent (橘)
  static const accentDark = Color(0xFFFAB28E);

  // 狀態
  static const success = Color(0xFF29D398);
  static const warning = Color(0xFFFAB795);
  static const error   = Color(0xFFE95678);
  static const info    = Color(0xFF26BBD9);
}

final lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.light,
    seedColor: AppColors.primary,
    surface: const Color(0xFFEEF5FF),
  ),
  textTheme: GoogleFonts.notoSansTcTextTheme(),
);

final darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    brightness: Brightness.dark,
    seedColor: AppColors.accentDark,
    surface: const Color(0xFF1C1E26),
  ),
  textTheme: GoogleFonts.notoSansTcTextTheme(),
);
```

### 8.2 圓角 / 間距

| Token | 值 |
|---|---|
| `radiusSm` | 8 |
| `radiusMd` | 12 |
| `radiusLg` | 16 |
| `spacingXs` | 4 |
| `spacingSm` | 8 |
| `spacingMd` | 16 |
| `spacingLg` | 24 |

---

## 9. 模組職責 / 隊員分工建議

> 五人團隊，依模組切分，介面（API contract）以本文件為準。

| 模組 | 負責人 | 主要產出 |
|---|---|---|
| **A. 前端 UI + 導航 + Theme** | 1 人 | 所有 `views/`, `widgets/`, theme, GoRouter |
| **B. 前端 State + Repository** | 1 人 | 所有 `view_models/`, `repositories/`, `models/` |
| **C. 後端 Functions + Firestore Triggers** | 1 人 | Functions callable + triggers + Firestore rules |
| **D. AI Agent (OpenAI Flows + Prompts)** | 1 人 | `functions/src/flows/*` + `functions/src/prompts/*` + `functions/src/tools/*` |
| **E. 整合層 (GitHub Webhook + Discord Bot)** | 1 人 | `githubWebhook`, `discordInteractions`, OAuth、Discord 設定 |

各模組透過本文件 §2 (Schema) + §4 (Functions API) 對齊；不需要互等。

---

## 10. 開發里程碑（建議）

### Sprint 1（1 週）— 骨架
- [ ] A: Theme + GoRouter + 所有頁面殼 (空 UI)
- [ ] B: User / Repo model + Repository + sign in flow
- [ ] C: Firestore rules + flutterfire configure
- [ ] D: `openai` SDK 環境設置 + 一個 hello world flow (含 zod schema)
- [ ] E: GitHub OAuth + addRepo callable（含 webhook 註冊）

### Sprint 2（1 週）— 核心功能 1（任務拆解）
- [ ] A: TasksBoard + AddTodo 3 步驟流程 UI
- [ ] B: TasksBoardViewModel + tasks repository
- [ ] D: `breakdownTaskFlow` 完整實作（含 agentic 驗證）

### Sprint 3（1 週）— 核心功能 2 + 3
- [ ] D: `assignTaskFlow` + `generateHandoffFlow`
- [ ] C: `onTaskUpdated` trigger 串接 handoff
- [ ] A/B: TaskDetailsPage 顯示 handoff + 子任務

### Sprint 4（1 週）— GitHub + Discord 整合
- [ ] E: GitHub webhook 處理 push/PR/issue
- [ ] C: `onCommitCreated` trigger + AI summary（含 idempotency + commit filter）
- [ ] E: 部署獨立 forwarder bot 至本機/VPS + `discordMessageIngest` Cloud Function
- [ ] E: 設定 `repos.discordWebhookUrl` 並驗證 outbound 通知（任務完成時推播）
- [ ] A: DailyView 三個 Tab

### Sprint 5（1 週）— 統計 + 拋光
- [ ] A: StatsView (圓餅圖 / 長條圖 — 套 `fl_chart` 或 `syncfusion`)
- [ ] All: 動畫拋光 (AnimatedList / Hero / SliverAppBar)
- [ ] All: FCM 通知測試
- [ ] All: 修 bug + 跑 demo

---

## 11. 風險與權衡

| 風險 | 緩解 |
|---|---|
| OpenAI 費用超支 | Prompt caching；commit summary 用 gpt-4o-mini；commit / discord 雙層雜訊過濾；非必要功能（每日報）可改成手動觸發 |
| Firestore 查詢慢（依賴圖跨節點） | 不用 graph DB；`dependsOn` 直接存陣列，UI 端組圖；最多 50 個 task 沒問題 |
| GitHub webhook 重送 | `x-github-delivery` 當 webhook 層 idempotency；Trigger 層另用 `event.id` (§4.4 規則 C) |
| **GitHub webhook 高併發爭用** | webhook handler 只寫入 raw doc，全部業務邏輯下沉到 trigger（§6.3 / §4.3 職責切分） |
| **Discord forwarder 丟包（冷啟動 / 429）** | forwarder 內建指數退避重試 + jitter (§7.2 `sendWithRetry`)；4xx 非 429 直接 drop 不再 retry |
| Discord 不能常駐連線 (Cloud Functions 限制) | 由使用者自架 forwarder bot（本機/VPS）即時轉發；正式版可遷至 Cloud Run min-instance=1 |
| **重複拆解任務** (兩人同時點 / 連點) | 前端 button disable + 後端 `isBreakingDown` 分散式鎖 + 5min 排程兜底解鎖 (§5.1) |
| Firebase Auth GitHub provider 拿不到 long-lived token | 第一次拿到的 token 存好；過期再 silent refresh |
| Function cold start（一般） | 高頻函式 (`githubWebhook`、`discordMessageIngest`) 在期末 demo 前加 `minInstances: 1`（會多算錢） |

---

## 12. 環境變數 / Secret 管理

統一用 Firebase Functions 的 `defineSecret`（`firebase-functions/params`）。所有 secret 在 `functions/src/config.ts` 集中宣告，需要該 secret 的 function 在註冊時把它列在 options 的 `secrets` 陣列裡，function 內以 `secret.value()` 讀取。

需要的 secrets：

| Secret 名稱 | 用途 | 誰需要 |
|---|---|---|
| `OPENAI_API_KEY` | 呼叫 OpenAI API | 所有 AI flow / trigger |
| `DISCORD_INGEST_SECRET` | forwarder bot ↔ `discordMessageIngest` 共享密鑰 | `discordMessageIngest` |
| `GITHUB_APP_PRIVATE_KEY` | 若改用 GitHub App 模式；個人 OAuth 模式不用 | `githubWebhook` / `addRepo` |

設定指令（**使用者親跑**，AI 不可）：

```bash
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set DISCORD_INGEST_SECRET
```

設定後 Firebase Console 會把 secret 加密存進 Google Secret Manager。Functions 啟動時自動以環境變數注入，本機 emulator 跑時用 `.secret.local` 檔（不入 git，加進 `.gitignore`）。

---

## 13. 後續可擴充（不做進 demo）

- Discord 訊息常駐抓取（改用 Cloud Run + 常駐 discord.js bot）
- Slack 整合（同 Discord 模式）
- VS Code extension（直接從 IDE 看任務 / 觸發 handoff）
- Web 版（Flutter Web；Firebase 已支援）

---

> 完成本文件後，所有 API contract、Firestore schema、AI flow 都已對齊。隊員開工時務必先讀 [`COURSE_METHODS.md`](./COURSE_METHODS.md) 確保 coding style 與課程一致。
