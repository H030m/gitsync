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
│   ├── githubLogin: string                     # GitHub username
│   ├── githubAccessToken: string (encrypted)   # 用來呼叫 GitHub API
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
│   ├── discordChannelId: string?               # 綁定的 Discord channel
│   ├── memberIds: string[]                     # 鏡像 subcollection 方便 array-contains query
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
| `breakdownTask` | `{ repoId, goal: string }` | `{ subtasks: [...] }` | AI Flow — 任務拆解 |
| `assignTask` | `{ repoId, taskId }` | `{ assigneeId, reason }` | AI Flow — 動態分派 |
| `generateHandoff` | `{ repoId, taskId }` | `{ handoffMarkdown }` | AI Flow — 交接文件 |
| `summarizeDay` | `{ repoId, date: string }` | `{ summary }` | AI Flow — 日報生成 |
| `linkDiscordChannel` | `{ repoId, channelId }` | `{}` | 綁定 Discord channel |
| `subscribeToTopic` | `{ token, topic }` | `{}` | FCM web push（同課程） |

### 4.2 HTTP Webhook Functions（外部呼叫）

| Function | 來源 | 處理 |
|---|---|---|
| `githubWebhook` | GitHub | 驗證 HMAC → 依 event 類型分派 (`push`/`pull_request`/`issues`) → 寫 Firestore |
| `discordInteractions` | Discord | 驗證簽章 → 處理 slash command (`/check`, `/assign`, `/daily`) |

### 4.3 Firestore Triggers（事件驅動）

| Trigger | 事件 | 動作 |
|---|---|---|
| `onTaskCreated` | tasks/{taskId} create | 若 `source == "manual"`，可選擇呼叫 AI 自動分派；建 GitHub issue |
| `onTaskUpdated` | tasks/{taskId} update | 若 `status` 變 "done"：發 FCM 給下游 (`dependsOn` 反向查) + 寫 Discord + 觸發 `generateHandoff` |
| `onCommitCreated` | commits/{sha} create | 解析 message 連結 task → AI 生成 `aiSummary` → 算 `messageEmbedding` |
| `onPRMerged` | pullRequests/{n} update where state→"merged" | 把 linkedTaskIds 標 done |
| `onDiscordMessageCreated` | discordMessages/{id} create | AI 推斷 `linkedTaskIds` 並補回去 |
| `scheduledDailyReport` | Pub/Sub schedule 18:00 daily | 對每個 repo 觸發 `summarizeDay` |

**所有 trigger 都要做 idempotency key check**（見 [COURSE_METHODS § 6.2](./COURSE_METHODS.md#62-必學idempotency-key-模式)）。

---

## 5. AI Agent 設計（三個核心 Flow）

> 全部用 OpenAI 官方 SDK：**structured outputs**（`response_format` + zod schema）保證 JSON 正確、**function calling**（tool use）做 agentic 自主檢索。詳細寫法見 [`COURSE_METHODS.md §8`](./COURSE_METHODS.md#8-ai-agent--openai-sdk-直接使用後端)。
>
> 每個 flow 是一個 async function 在 `functions/src/flows/` 下，由 `handlers/` 的 `onCall` 包成 Firebase Callable。

### 5.1 Flow 1 — `breakdownTaskFlow`（任務拆解）

對應 prototype 核心功能 01。

**Input**: `{ repoId: string, goal: string }`
**Output**: `{ subtasks: [{ title, description, dependsOn: number[], estimatedHours }] }`

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
  └─ output: validated JSON { subtasks: [...] }

Step 3 — detectCycles(subtasks)                [純 TS DFS]
  └─ if cycle found ─→ Step 3b

Step 3b — re-prompt with cycle info            [agentic 自我修正]
  ├─ Append previous response + error message
  └─ output: fixed subtasks
```

**Prompt**: `functions/src/prompts/breakdownTask.ts`（純字串）
**Schema**: `functions/src/types.ts`（zod）
**Flow**: `functions/src/flows/breakdownTask.ts`

### 5.2 Flow 2 — `assignTaskFlow`（動態任務分派）

對應 prototype 核心功能 02。

**Input**: `{ repoId: string, taskId: string }`
**Output**: `{ assigneeId: string, reasoning: string }`

**Steps（agentic — 用 OpenAI function calling，讓 agent 自己決定要拉哪些資料）**:

```
Setup — 註冊 4 個 tools:
  • readTeamState(repoId)                → 全員 activeIssueCount / expertiseTags / lastActiveAt
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
  • findDownstreamTask(repoId, completedTaskId)
  • listRelatedCommits(repoId, taskId)
  • getCommitDiff(repoId, sha)                  → 經 GitHub API
  • searchDiscordMessages(repoId, query)        → Firestore vector search
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

由 Pub/Sub 排程每日 18:00 觸發；查當日 commits + completed tasks + discord 討論 → 寫成兩三句的人話日報。

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

**查詢時必須帶 `where` 預過濾**（否則會 across 所有 repo）：

```ts
const queryEmbedding = await embed(searchText);
const snapshot = await db.collectionGroup('commits')
  .where('repoId', '==', repoId)               // ← 必加，否則跨 repo 洩漏
  .findNearest({
    vectorField: 'messageEmbedding',
    queryVector: FieldValue.vector(queryEmbedding),
    limit: 5,
    distanceMeasure: 'COSINE',
  })
  .get();
```

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

```typescript
export const githubWebhook = onRequest(async (req, res) => {
  const sig = req.headers['x-hub-signature-256'];
  const event = req.headers['x-github-event'];
  const delivery = req.headers['x-github-delivery'];   // 用於 idempotency

  // 1. 從 payload 拿 repoId → 查 webhookSecret → 驗 HMAC
  const repoId = `${payload.repository.owner.login}_${payload.repository.name}`;
  if (!verifyHmac(sig, secret, rawBody)) return res.status(401).send('bad sig');

  // 2. Idempotency
  if (await alreadyProcessed(delivery)) return res.status(200).send('dup');

  // 3. Dispatch
  switch (event) {
    case 'push':         await handlePush(repoId, payload); break;
    case 'pull_request': await handlePR(repoId, payload); break;
    case 'issues':       await handleIssue(repoId, payload); break;
  }

  res.status(200).send('ok');
});
```

**`handlePush`**：
- 對每個 commit 寫 `repos/{repoId}/commits/{sha}`
- 解析 message 找 `#N` / `fixes #N` → 找對應 task → 寫 `linkedTaskIds`
- 由 `onCommitCreated` trigger 算 embedding + AI 摘要

**`handlePR` (action = "closed" && merged)**：
- 寫 `pullRequests/{n}`
- 把 `linkedTaskIds` 標為 done（觸發 `generateHandoffFlow`）

### 6.4 GitHub API client 包裝

```typescript
// functions/src/services/githubClient.ts
import { Octokit } from '@octokit/rest';

export function getOctokit(userAccessToken: string) {
  return new Octokit({ auth: userAccessToken });
}

export async function getRecentCommits(owner: string, repo: string, accessToken: string) {
  const octokit = getOctokit(accessToken);
  const { data } = await octokit.repos.listCommits({ owner, repo, per_page: 20 });
  return data;
}
```

---

## 7. Discord Bot 整合

> 用 Discord Interactions API（webhook-based），**不用 gateway/bot 常駐連線**，完全符合 Cloud Functions 模型。

### 7.1 Bot 設置

1. Discord Developer Portal 建 Application
2. 啟用 **Interactions Endpoint URL**: `https://<region>-<project>.cloudfunctions.net/discordInteractions`
3. 註冊 slash commands（一次性）:

```typescript
// scripts/registerDiscordCommands.ts (本機跑一次)
await fetch(`https://discord.com/api/v10/applications/${APP_ID}/commands`, {
  method: 'PUT',
  headers: { Authorization: `Bot ${BOT_TOKEN}` },
  body: JSON.stringify([
    { name: 'gitsync-link', description: '把這個頻道綁到 GitSync repo' },
    { name: 'gitsync-check', description: '查看某人的任務', options: [{ name: 'user', type: 6, required: true }] },
    { name: 'gitsync-daily', description: '取得今天的日報' },
    { name: 'gitsync-assign', description: 'AI 自動分派指定任務' },
  ]),
});
```

### 7.2 `discordInteractions` Function — **3 秒回應限制 + Deferred Response**

**關鍵限制**：Discord Interactions Webhook 必須在 **3 秒內** 回應，否則使用者會看到「應用程式沒有回應」。但 `gitsync-assign`（呼 AI flow loop）或 `gitsync-daily`（生成日報）動輒 5–15 秒。

**解法**：兩段式回應
1. 立刻回 `type: 5`（DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE）→ Discord 顯示「正在處理中...」
2. 真正處理完，用 `interaction.token` PATCH `@original` 訊息，把結果補上去

```typescript
import nacl from 'tweetnacl';

export const discordInteractions = onRequest(
  { region: 'us-west1', secrets: [discordPublicKey, discordBotToken, openaiKey] },
  async (req, res) => {
    // 1. 驗證 Ed25519 簽章 (Discord 要求)
    const sig = req.headers['x-signature-ed25519'] as string;
    const ts = req.headers['x-signature-timestamp'] as string;
    if (!nacl.sign.detached.verify(
          Buffer.from(ts + req.rawBody),
          Buffer.from(sig, 'hex'),
          Buffer.from(discordPublicKey.value(), 'hex'))) {
      return res.status(401).send('invalid signature');
    }

    // 2. PING (Discord 驗證 endpoint 用)
    if (req.body.type === 1) return res.json({ type: 1 });

    // 3. APPLICATION_COMMAND
    if (req.body.type === 2) {
      const cmd = req.body.data.name;
      const token = req.body.token;
      const applicationId = req.body.application_id;

      // 3a. 短指令（< 1s）— 直接同步回
      if (cmd === 'gitsync-link') {
        return handleLinkSync(req, res);
      }

      // 3b. 長指令 — 立刻回 DEFERRED，把實際工作丟到背景
      // 必要：必須先 res.json 才能跑長工作，否則 Discord 會 timeout
      res.json({ type: 5 });  // DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE

      // 背景處理（注意：onRequest 的 process 不會等 res 之後的 async，
      // 所以高頻場景請改投 Cloud Tasks / Pub/Sub）
      try {
        let resultContent = '';
        switch (cmd) {
          case 'gitsync-check':  resultContent = await runCheck(req.body); break;
          case 'gitsync-daily':  resultContent = await runDaily(req.body); break;
          case 'gitsync-assign': resultContent = await runAssign(req.body); break;
        }
        await editOriginalInteraction(applicationId, token, resultContent);
      } catch (err) {
        await editOriginalInteraction(applicationId, token, `❌ Failed: ${err.message}`);
      }
      return;
    }
  }
);

// PATCH @original：把 deferred 訊息更新成真實內容
async function editOriginalInteraction(appId: string, token: string, content: string) {
  await fetch(
    `https://discord.com/api/v10/webhooks/${appId}/${token}/messages/@original`,
    {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    }
  );
}
```

**為何不用 Cloud Tasks**：MVP 階段 onRequest 的「res.json 後繼續跑 async」在 Functions v2 是可行的（process 生命週期延續到所有 promise 完成）；若日後遇到 cold start / timeout 再升級成 Cloud Tasks。

**為何 `gitsync-assign` 不直接呼 `assignTask` callable**：Discord 端的 `interaction.token` 只在 Discord 環境有效，必須由 `discordInteractions` 親自處理回填；不能把工作丟給 callable 後讓它「自己回覆 Discord」（會丟失 token 上下文）。實作上 `runAssign` 內部會直接 import 並呼叫 `assignTaskFlow`（不走 callable wrapper）。

### 7.3 Bot 主動發訊 (從 Firestore Trigger)

```typescript
// 當任務狀態變 done，通知下游
async function notifyDiscordOnTaskDone(repoId: string, task: Task) {
  const repo = await getRepo(repoId);
  if (!repo.discordChannelId) return;

  await fetch(`https://discord.com/api/v10/channels/${repo.discordChannelId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bot ${BOT_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      content: `✅ \`${task.title}\` 已完成！\n下一步：<@${nextAssigneeDiscordId}> 可以開始 \`${nextTask.title}\` 了。`,
    }),
  });
}
```

### 7.4 抓 Discord 訊息（被動模式）

不用常駐 bot，**改用 Discord 的 Message Webhook**：
1. 用戶在 Discord Server 設定 webhook → 訊息 forward 到我們的 `discordMessageReceiver` Cloud Function
2. 或更實際：在 bot 上加 `messageCreate` event（需要常駐連線）—> 太重，不採用
3. **方案**：bot 只回應 slash command，**訊息抓取改成「使用者按按鈕主動 import」**：
   - Discord 訊息上加 [Add to GitSync] context menu command
   - 點了之後 webhook 送過來，存到 `discordMessages`

> 這比常駐 bot 簡單十倍，且足以滿足核心功能（讓 AI 在生成 handoff 時能搜尋到相關討論）。

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
- [ ] C: `onCommitCreated` trigger + AI summary
- [ ] E: Discord slash commands + bot 主動推播
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
| OpenAI 費用超支 | 用 prompt caching；非必要功能（每日報、commit summary）做成手動觸發 |
| Firestore 查詢慢（依賴圖跨節點） | 不用 graph DB；`dependsOn` 直接存陣列，UI 端組圖；最多 50 個 task 沒問題 |
| GitHub webhook 重送 | `x-github-delivery` 當 idempotency key |
| Discord 不能常駐連線 | 不抓所有訊息；改成「用戶按按鈕主動 import」 |
| Firebase Auth GitHub provider 拿不到 long-lived token | 第一次拿到的 token 存好；過期再 silent refresh |
| Function cold start | 高頻函式 (`githubWebhook`) 加 `minInstances: 1`（會多算錢，期末再加） |

---

## 12. 環境變數 / Secret 管理

用 Firebase Functions `defineSecret`：

```typescript
import { defineSecret } from 'firebase-functions/params';
import { onCall } from 'firebase-functions/v2/https';

const openaiKey = defineSecret('OPENAI_API_KEY');
const discordBotToken = defineSecret('DISCORD_BOT_TOKEN');
const discordPublicKey = defineSecret('DISCORD_PUBLIC_KEY');
const githubAppPrivateKey = defineSecret('GITHUB_APP_PRIVATE_KEY');  // 若用 GitHub App，個人 OAuth 不用

export const breakdownTask = onCall(
  { region: 'us-west1', secrets: [openaiKey] },
  async (request) => { /* ... */ }
);
```

設定：
```bash
firebase functions:secrets:set OPENAI_API_KEY
```

---

## 13. 後續可擴充（不做進 demo）

- Discord 訊息常駐抓取（改用 Cloud Run + 常駐 discord.js bot）
- Slack 整合（同 Discord 模式）
- VS Code extension（直接從 IDE 看任務 / 觸發 handoff）
- Web 版（Flutter Web；Firebase 已支援）

---

> 完成本文件後，所有 API contract、Firestore schema、AI flow 都已對齊。隊員開工時務必先讀 [`COURSE_METHODS.md`](./COURSE_METHODS.md) 確保 coding style 與課程一致。
