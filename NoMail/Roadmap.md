# Roadmap

Phased plan from demo prototype to working client. Each phase is independently shippable.

## Phase 1 — Make it honest and bootable ✅ (2026-08-01)

- [x] Clone repo to `/Users/Victor/Projects22/hmail`, audit code vs README
- [x] Fix startup crash when `.env` missing (tolerant load, demo fallback)
- [x] `.env.example` committed; `.env` gitignored and created locally
- [x] Replace retired Claude model (`claude-3-haiku-20240307` → `claude-haiku-4-5`)
- [x] Real Google Sign-In wiring (google_sign_in 7.x) with graceful fall-back to explicit demo mode (`isDemoMode`)
- [x] Demo-mode badge visible in app state (provider flag)

## Phase 2 — Real Gmail, one platform (next)

- [ ] Create/choose Google Cloud project, enable Gmail API, mint OAuth client ID *(user action — blocks everything below)*
- [ ] Pick first platform (recommend **iOS or Android** — google_sign_in 7.x on web doesn't support `authenticate()`; web needs the GIS renderButton flow, deferred)
- [ ] Verify sign-in → inbox fetch → detail view end-to-end with a real account
- [ ] Read/unread, star, archive, trash against the live API
- [ ] Compose + send

## Phase 3 — Real AI insights

- [ ] Wire `CLAUDE_API_KEY`, run `analyzeEmails` on real inbox
- [ ] Parse insights into `AmazonOrder` / `Subscription` / `Bill` and feed the dashboard (currently only demo data reaches it)
- [ ] Replace heuristic importance/summary/keywords with model output (single batched call)
- [ ] Cost control: cap analysis to N most-recent emails, cache results locally (shared_preferences)

## Phase 4 — Hardening

- [ ] Delete legacy `gmail_service.dart` + `email_provider.dart`
- [ ] Consolidate charts on `fl_chart` (drop discontinued `charts_flutter`)
- [ ] Fix `withOpacity` deprecations (`.withValues()`)
- [ ] Tests: provider unit tests for demo/real mode switching; widget test currently references unused import
- [ ] Token refresh + sign-in persistence across app restarts

## Later (from README wishlist)

Multi-account, offline mode, notifications, calendar, desktop targets.

Related: [[Requirements]], [[Development Log]]
