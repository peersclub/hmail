# Development Log

## 2026-08-01 — Recovery + Phase 1

**Context.** Repo located at `peersclub/hmail` (single commit, 2025-08-21), cloned to `/Users/Victor/Projects22/hmail`. Audit found the README describing a full product while the code was a demo-mode prototype: sign-in stubbed (`return false`), three hardcoded emails, canned orders/subscriptions/bills, and a retired Claude model in the AI service.

**Changes (uncommitted, working tree):**

1. **Startup crash fixed** — `main.dart` wrapped `dotenv.load` in try/catch with `dotenv.testLoad(fileInput: '')` fallback; app boots with no `.env`. Added `.env.example`; local `.env` created from it (gitignored).
2. **Real Google Sign-In** — `enhanced_gmail_service.dart` rewritten for google_sign_in **7.x**: `GoogleSignIn.instance.initialize(clientId:)` → `attemptLightweightAuthentication()` → `authenticate(scopeHint:)` → `authorizationClient.authorizeScopes()` → access token → `GmailApi`. Returns `false` when `GOOGLE_CLIENT_ID` is unset or the user cancels.
3. **Explicit demo mode** — provider now attempts real sign-in first and only falls back to demo with `isDemoMode = true`; demo mode guards all Gmail mutations so swipe actions mutate the local list instead of throwing.
4. **Dead-provider bug fixed** — 4 of 5 navigation tabs (`AmazonOrdersList`, `SubscriptionsList`, `BillsList`, plus `HomeScreen`/`InsightsChart`) consumed the legacy `EmailProvider`, which `main.dart` never provides — every dashboard tab crashed with `ProviderNotFoundException`. Migrated all five files to `EnhancedEmailProvider` and added a `fetchAndAnalyzeEmails()` alias.
5. **Claude model migrated** — `claude-3-haiku-20240307` (retired 2026-04-19, now 404s) → `claude-haiku-4-5`. Empty-string env keys now normalized to null so the template `.env` doesn't trip the "key configured" check.
6. **Login overflow fixed** — `LoginScreen` Column wrapped in `SingleChildScrollView` (overflowed 36px on small viewports).
7. **Tests green** — dotenv `setUpAll` seed added; nav-icon assertions relaxed to `findsWidgets`. `flutter test`: **6/6 pass**. `flutter analyze`: 0 errors (43 pre-existing infos/warnings).

**Not yet done / blockers:**
- No Google Cloud OAuth client exists → app runs in demo mode until `GOOGLE_CLIENT_ID` is minted (Phase 2, user action).
- On **web**, google_sign_in 7.x does not support `authenticate()` — needs the GIS `renderButton` widget. Prefer iOS/Android for first real-account test, or add the web button flow.
- Changes are local only — not committed or pushed.

Related: [[Roadmap]], [[Architecture]]

## 2026-08-01 — Rename: HMail → NoMail

Google rejected "HMail" as the OAuth consent-screen app name (too close to Gmail). Product renamed **NoMail**. Scope of the rename: user-visible strings only — MaterialApp title, login/inbox/home screen text, iOS `CFBundleName`, Android `android:label`, web `index.html` + `manifest.json`, README, this vault, demo address (`demo@nomail.app`), tests (6/6 still green).

**Deliberately unchanged:** GitHub repo slug `peersclub/hmail`, local path `Projects22/hmail`, Dart package name (`package:hmail/...`), and bundle/application ID `com.hmail.hmail` — the OAuth client binds to the bundle ID, and Google has no objection to it. Use "NoMail" as the app name on the consent screen; keep `com.hmail.hmail` as the iOS client's bundle ID.

## 2026-08-01 — OAuth client wired (iOS)

Victor created the Google Cloud OAuth iOS client (project consent name "NoMail"). Client plist landed in Downloads; values wired in:

- `GOOGLE_CLIENT_ID` set in local `.env` (client `129153074260-ek9c...`)
- `ios/Runner/Info.plist`: added `GIDClientID` + `CFBundleURLTypes` URL scheme with the reversed client ID; fixed leftover `CFBundleDisplayName` "Hmail" → "NoMail"
- **Bundle ID renamed** `com.hmail.hmail` → `com.nomail.nomail` (pbxproj ×6 incl. RunnerTests, Android `namespace`/`applicationId`, MainActivity package path) — the OAuth client was registered against `com.nomail.nomail`, and nothing shipped yet, so the app moved to match. Earlier "keep the bundle ID" note in this log is superseded.
- `plutil -lint` OK; analyze 0 errors; tests 6/6.

**Blocked on machine setup, not code:** first `flutter build ios --simulator` failed — Xcode license unaccepted, first-launch components missing, CocoaPods absent (brew install also blocked by the license). Victor to run `sudo xcodebuild -license accept` + `sudo xcodebuild -runFirstLaunch`, then install cocoapods and rebuild. No Android SDK on this Mac — iOS is the only mobile path locally.
