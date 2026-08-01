# One App Vision — NoMail as the phone's front door

> Synthesized 2026-08-01 from a 4-agent research batch (domains & deep links, iOS surfaces, AI agent layer, competitive strategy). Companion docs: [[Actions API]], [[Roadmap]], [[Architecture]].

## Thesis

Email is the receipts layer of digital life — every app, bank, merchant, airline, school, and government office emails you. NoMail extracts that into typed, actionable cards so the user opens **one app** and fans out to others only at the moment of action (via deep links). Apple just validated the thesis (iOS 26 Wallet scans Mail for orders); Google Now proved users want it and died for lack of a business model and actions. NoMail's already-built actions layer is exactly what Google Now lacked.

**Already built (foundation):** rule-based extraction (subscriptions, bills, deliveries, calendar events), deep-link actions layer (`domain/actions.dart` — pay/UPI, track, join, manage, open-email), rule-based daily brief, Claude AI hook, Google OAuth.

---

## Pillar 1 — Cover every life domain that flows through email

14 domains, each = email shapes → typed insight → one-tap action. Current 4 (bills, subs, parcels, meetings) plus:

| Domain | Key insights | Killer actions (verified links bold) |
|---|---|---|
| Travel | PNR, flight/train times, hotel, passport/visa expiry | Web check-in (**IndiGo/Air India URLs**), boarding pass → Wallet, PNR status, **Uber to airport** |
| Money+ | Bank debit alerts, CC statements, CAS/MF, EMIs, ITR deadlines | Pay via **`upi://pay` (NPCI spec)** / **`gpay://upi/pay`**, cash-flow rollup, statement PDF w/ password hint |
| Food & local | Swiggy/Zomato orders, grocery, reservations | Track order (https universal links; `swiggy://` params undocumented), monthly spend rollup |
| Transport | Uber/Ola receipts, FASTag balance | **`uber://?action=setPickup`**, **`olacabs://app/launch`**, FASTag recharge |
| Health | Appointments, lab reports, refills, claims | Directions, calendar add, biomarker trends across report emails, refill prediction |
| Tickets | BookMyShow, events, OTT | **Render the QR from the email inline** (no app needed), venue directions, cancel-OTT links |
| Work | Jira/GitHub/Slack/DocuSign emails | **`slack://channel`**, GitHub/Docs universal links, sign-by deadlines, "3 PRs + free hour at 2pm" |
| Government | e-challans, Aadhaar/PAN, DL/passport/PUC expiry | Pay challan (parivahan), **expiry radar** card for all identity docs |
| Education | School fees, assignments, PTMs | Fee pay links, family deadline board |
| Shopping+ | Return windows, refunds, warranties, gift cards | Return-by countdown, refund-not-credited escalation (cross-checks bank alerts), warranty vault |
| Home/society | Electricity/broadband/maintenance | UPI pay, consumption anomaly ("June bill 40% above baseline") |
| Security | Sign-in alerts, breaches, OTPs | Secure-account links, dormant-account audit, OTP auto-surface |
| Loyalty | Points expiry, price changes | "Use 12k Bonvoy points on your Goa trip" (fuses with travel) |
| Career | Interview invites, offers | **`zoomus://join`**, **`msteams://`**, conflict detection with flights |

**iOS gotcha:** no system-wide `upi://` handler on iOS — needs a "preferred UPI app" setting mapping to per-app schemes (gpay/phonepe/paytm), https fallback. Ship https universal links first for every unverified scheme (`swiggy://`, `phonepe://`, `bookmyshow://`, `digilocker://`…).

## Pillar 2 — Become an OS surface, not an app (iOS-first)

Ranked by ROI (agent-assessed Flutter feasibility, S/M/L effort):

1. **Background refresh backbone** (L) — Gmail `users.watch` → Pub/Sub → APNs silent push; `workmanager` BGTask as fallback. Everything below depends on freshness. ⚠️ Gmail restricted scopes → annual CASA Tier 2 audit before public launch.
2. **Home widgets** (M) — brief / next-meeting / parcel widgets via `home_widget` + SwiftUI extension + App Group `group.com.nomail.nomail`.
3. **Actionable notifications** (S) — "BESCOM due tomorrow [Pay] [Remind]" via `flutter_local_notifications` categories.
4. **EventKit** (S) — write meetings/bill-reminders into the system calendar (write-only permission = light prompt).
5. **Live Activities** (M–L) — parcel out-for-delivery and flight-day cards in Dynamic Island (`live_activities`, iOS 16.1+; remote updates need the push backbone).
6. **Siri / App Intents + App Shortcuts + Control Center** (M+S) — "Hey Siri, what's my brief"; static Swift intents calling into Dart; `AssistantSchema.MailIntent` (iOS 18.1) worth exploring.
7. **Apple Wallet** (S) — detect `.pkpass` attachments (boarding passes/tickets) → one-tap add via `apple_passkit`. Huge wow-per-effort.
8. **Spotlight** (S) — extracted entities searchable from the home screen (`flutter_core_spotlight`).
9. **Share extension** (M) — share any PDF/URL/screenshot into NoMail → same extraction pipeline ("understand this" inbox).
10. **On-device intelligence** (M) — Apple Foundation Models (iOS 26, guided generation) for private extraction; ladder: regex/NSDataDetector → on-device FM → Claude for synthesis.

⚠️ Found by the surfaces agent: `.env` ships inside the IPA as a Flutter asset — API keys must move server-side before any public build.

## Pillar 3 — The AI agent layer (why the user opens ONE app)

Three new consumers of the existing snapshot spine (full design with Dart interfaces in the agent report, summarized):

1. **Command bar** — Claude tool-use loop over tools that expose only extracted data: `get_snapshot`, `query_spend`, `get_actions`, `search_emails` (scoped, consent-gated), `draft_email`, `create_reminder`. "When's my Delhivery arriving?" / "Cancel Hotstar" → tappable action chips. Agent proposes; user's tap executes. Never sends/pays autonomously.
2. **Proactive trigger engine** — deterministic cross-domain rules evaluated on sync (testable like extractors), AI only ranks and phrases: bill due + no payment confirmation seen → nudge; renewal in 7d + zero emails from that service in 60d → "cancel?"; flight tomorrow + meeting conflict → warn; parcel out-for-delivery + meetings all day → "you'll miss it".
3. **Drafting concierge** — unsubscribe ladder (List-Unsubscribe header → manage link → AI-drafted cancellation email), reply drafts, bill disputes, RSVP (deterministic iCal REPLY).
4. **Memory** — local-only `UserFact` store (salary day, preferred UPI app per biller, habitual meeting lateness), learned by rules not AI, legible and deletable in Settings.
5. **Privacy tiers** — T0 rules on-device (current) / T1 on-device LLM (Apple FM) / T2 cloud Claude, opt-in, receives structured snapshot JSON, never raw bodies (except previewed, consented drafting sources). *This architecture is also the marketing.*
6. **Cost** — Haiku for sync/triggers, Sonnet for command bar/drafting ≈ **$2.80/user/mo heavy, $1.20 light** — comfortably inside a ₹99–199 Pro tier.

## Pillar 4 — Strategy (why we win)

- **Gmail/Apple can't follow:** their UI *is* the message list — they're institutionally unable to demote the inbox to a backend. Apple's order tracking is English-US/UK, Apple-Mail-only. Gemini cards decorate mail-reading; no cross-account, no India rails.
- **AI mail clients (Shortwave/Superhuman/Spark) are in a different lane:** compose/triage speed for US knowledge workers at $10–30/mo. None treat email as life-admin data.
- **Super-apps/CRED/trackers see only their own transactions.** Walnut→Axio (SMS parsing) ended as an Amazon lending acquisition; SMS receipts are structurally dying (banks moving alerts to email — HDFC already did for small UPI).
- **Moats (ranked):** cross-provider receipts graph → India-native action rails (UPI/BBPS/couriers/IRCTC, updated weekly) → the opinionated daily-brief home screen → subscription P&L + cancel flows (Google/Apple are conflicted) → compounding extracted-history memory.
- **Monetization:** freemium Pro **₹99/mo / ₹799/yr** (multi-account, agent Q&A, subs P&L, vault); ₹499 Max for unlimited agent later. No ads, no data resale, no lending pivot — trust is the counter-position.

## Phased roadmap

**Phase A — Daily habit (2–4 wks):** onboarding backfill scan with the money-shot ("₹18,400/yr of subscriptions found"), Today screen as default, 8am brief push, parcel Live Activity/widget, top-30 Indian sender templates. **Metric: % users opening ≥4 of 7 days.** Risk: one wrong "bill due tomorrow" kills trust → confidence thresholds, suppress rather than guess.

**Phase B — Replace the switching (1–2 mo):** action completion everywhere (UPI pay, in-app tracking, calendar add, cancel links), multi-account (Outlook/IMAP), subscriptions dashboard + price-hike alerts, forward-to-NoMail address, entity search. **Metric: completed actions per WAU.** Risk: deep-link brittleness → template-monitoring harness + OTA rule updates as ongoing ops.

**Phase C — The agent (3–6 mo):** command bar Q&A over receipts history, proactive concierge (refund chasing, duplicate subs, warranty expiries) with one-tap drafts, weekly money digest from bank-alert emails, document vault, personalized brief. **Metric: agent-initiated tasks accepted /user/mo; churn of >6-month users ≈ 0.**

## Cross-cutting risks

1. Extraction precision = trust (suppress low-confidence, never guess).
2. CASA Tier 2 audit for Gmail restricted scopes — start early, budget annually.
3. `.env` secrets ship in the IPA today — server-side proxy before TestFlight beyond the team.
4. Deep-link rot — treat action rails as ops (monitor, hotfix via remote config).
5. WhatsApp-first receipts gap — mitigated by GST-forced email invoices + forward-to-NoMail + (later) Android notification companion.
