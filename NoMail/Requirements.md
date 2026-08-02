# Requirements

> **⚠️ Historical — read [[Roadmap]] and [[One App Vision]] for what NoMail is
> now.** This is the audit of the original README as found on 2026-08-01. The
> product pivoted that same week: NoMail is **not** a full email client. The
> "core email" requirements below (compose, send, labels, star/archive/trash,
> thread view) were **deliberately dropped** — Gmail is treated as a read-only
> backend, and the app's surface is ranked, actionable insights. The scope is
> `gmail.readonly` on purpose; NoMail cannot send, move or delete mail.
>
> Kept because the AI-insight and non-functional sections below still describe
> real intent, and because the audit records why the pivot happened.

Source: repo README (v. initial commit 65c1164) plus code audit on 2026-08-01. Items are tagged with implementation status found at recovery: ✅ built, 🟡 partial/stub, ❌ absent.

## 1. Core email (must-have)

| # | Requirement | Status at recovery |
|---|---|---|
| R1 | Google OAuth sign-in (no password storage) | ❌ stubbed — `signIn()` returned `false` unconditionally; provider faked success with demo data |
| R2 | Fetch inbox via Gmail API (read scope) | 🟡 code exists in `EnhancedGmailService.fetchEmails` but unreachable without R1 |
| R3 | Read a full message + thread view | 🟡 same as R2 |
| R4 | Compose, reply, send | 🟡 `sendEmail` implemented against API, unreachable |
| R5 | Mark read/unread, star, archive, trash | 🟡 implemented, unreachable |
| R6 | Label list / create / apply | 🟡 implemented, unreachable |
| R7 | Search (Gmail query syntax) | 🟡 via `EmailFilter.query` |

## 2. AI insights (differentiator)

| # | Requirement | Status at recovery |
|---|---|---|
| R8 | Analyze recent emails → structured insights (orders, subscriptions, bills, travel, finance) | 🟡 `AIService.analyzeEmails` calls Claude/OpenAI; model ID was deprecated (`claude-3-haiku-20240307`) |
| R9 | Importance scoring per email | 🟡 heuristic in provider (keyword-based), not model-based |
| R10 | Per-email summary + keywords | 🟡 heuristic truncation, not model-based |
| R11 | Financial dashboard: monthly/yearly spend projections, unpaid bills, orders in transit | ✅ UI + provider getters exist (fed by demo data) |

## 3. Non-functional

- N1 — Secrets in `.env` (gitignored); never committed. `CLAUDE_API_KEY` or `OPENAI_API_KEY`, `GOOGLE_CLIENT_ID`.
- N2 — App must boot without a `.env` present (demo mode), not crash at `dotenv.load`.
- N3 — Demo mode must be explicit in the UI/state (`isDemoMode`), never silently pretend to be real data.
- N4 — Platforms: iOS, Android, Web (macOS/Windows/Linux later).
- N5 — Gmail scopes: request the minimum (`gmail.modify`, `gmail.compose`, `gmail.send`); no full-mailbox scope.

## 4. Out of scope for now (README roadmap, deferred)

Calendar integration, contacts, encryption, offline mode, multi-account, desktop apps, browser extension, voice commands.

## Open questions

1. [unverified] Which Google Cloud project / OAuth client should NoMail use — new project or reuse an existing peersclub one?
2. Web vs mobile first? OAuth setup differs (web client ID + authorized origins vs iOS URL scheme / Android SHA-1).
3. Should AI analysis run on-device key (current design, key ships in app bundle — insecure for distribution) or behind a thin backend proxy? Current design is acceptable for personal use only.

Related: [[Architecture]], [[Roadmap]]
