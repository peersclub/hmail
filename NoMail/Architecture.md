# Architecture

Flutter app, ~4,500 lines of Dart under `lib/`. Provider (ChangeNotifier) for state; no repository layer yet despite README's claim — services are called directly from the provider.

## Layout

```
lib/
├── main.dart                          # dotenv load + ChangeNotifierProvider(EnhancedEmailProvider)
├── models/
│   ├── email.dart                     # Email, EmailThread, EmailFilter, EmailAttachment, EmailCategory
│   └── email_insight.dart             # EmailInsight, AmazonOrder, Subscription, Bill
├── providers/
│   ├── enhanced_email_provider.dart   # ACTIVE — all app state; demo-mode fallback lives here
│   └── email_provider.dart            # legacy, unused
├── services/
│   ├── enhanced_gmail_service.dart    # ACTIVE — google_sign_in v7 + googleapis GmailApi
│   ├── gmail_service.dart             # legacy, unused (dead code; candidate for deletion)
│   └── ai_service.dart                # Claude (claude-haiku-4-5) primary, OpenAI fallback, via dio
├── screens/                           # login, main navigation, home (dashboard), inbox, detail, compose
└── widgets/                           # dashboard cards, insight lists (orders/subs/bills), chart, filter chips
```

## Data flow

1. `LoginScreen` → `EnhancedEmailProvider.signIn()`
2. Provider → `EnhancedGmailService.signIn()` (google_sign_in 7.x: `initialize` → `authenticate` → `authorizationClient.authorizeScopes`) → access token → `GoogleAuthClient` → `GmailApi`
3. On any sign-in failure or missing `GOOGLE_CLIENT_ID` → **demo mode** (`isDemoMode = true`, canned emails/orders/subs/bills)
4. Real mode: `fetchEmails` → Gmail API → `_enhanceEmailsWithAI()` → `AIService.analyzeEmails` (batches 20 emails into one prompt, expects JSON insights back) → dashboard getters (`totalMonthlySpend`, `unpaidBillsCount`, …)

## Key decisions & gotchas

- **google_sign_in is v7.x** — completely different API from v6 (`GoogleSignIn.instance`, `authenticate()`, `authorizationClient`). Most online samples are v6; don't copy them.
- **flutter_dotenv loads `.env` as a bundled asset** — the file must exist at build time (declared in pubspec assets). `main.dart` wraps the load in try/catch so a missing file degrades to demo mode instead of crashing (requirement N2).
- **Claude model**: `claude-haiku-4-5` (migrated 2026-08-01; the original `claude-3-haiku-20240307` was retired 2026-04-19 and now 404s, so the AI path was hard-broken, not just deprecated). OpenAI path still `gpt-3.5-turbo` — update if ever used.
- **API keys ship in the app bundle** via dotenv — fine for personal builds, not for store distribution (see Requirements open question 3).
- **charts_flutter is discontinued**; `fl_chart` is also a dependency — consolidate on fl_chart.

Related: [[Requirements]], [[Development Log]]
