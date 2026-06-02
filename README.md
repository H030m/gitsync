# GitSync

Flutter app + Firebase Cloud Functions + OpenAI agent that integrates GitHub +
Discord and auto-generates task breakdowns, assignments, and handoff docs.

NTHU Software Studio final project, team 17.

---

## 🚀 First time here?

**Read [`docs/SETUP.md`](./docs/SETUP.md)** — step-by-step guide to get the app
running on your machine. Takes ~10 minutes for the fastest path (fake backend,
no Firebase needed).

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
