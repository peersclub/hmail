# Settings — the trust surface

> 2026-08-02. Built and shipping in the app; see [[One App Vision]] for the product thesis and [[Actions API]] for the actions layer.

## Why Settings matters more here than in most apps

NoMail asks for a person's whole mailbox, sends derived data to a cloud model, and then **rewrites their data** — dropping insights it decides aren't real and renaming others. Every one of those is a reason to distrust the app. Settings is where that distrust gets answered, so it's designed around the three questions a paying user actually asks:

1. **What is the AI doing?** → AI screen
2. **What is it reading?** → Scanning screen
3. **What did it change?** → Processing screen

Nothing in these screens is static marketing copy — every number is live.

## Structure

```
Settings
├─ Profile (account, demo badge)
├─ DATA
│  ├─ Sync Now            → live stage label while running
│  ├─ Scanning            → "Money, packages and meetings · up to 100 emails · 1 year"
│  └─ Processing          → last-scan headline
├─ INTELLIGENCE
│  ├─ AI                  → model name, or "Off — rules only"
│  └─ Daily Brief         → "Every day at 8am"
├─ YOUR DATA
│  ├─ Export Insights     → JSON to clipboard
│  └─ Rescan Everything   → confirm → clear store → re-extract
└─ Sign Out
```

### AI screen
- **Connection**: key configured (masked `sk-or-…65d9`), model picker with cost trade-off notes, and **Test connection** — sends one tiny real request and reports `Connected · 420 ms`, or a human error (`Key rejected`, `Out of credits`, `Rate limited`, `No network`).
- **Spend**: live usage from OpenRouter's `/api/v1/key` — `$0.42 this month`, or `$0.42 of $10.00 used` when a cap exists. **Warns when the key has no spend cap.**
- **Privacy**: master AI switch. Off = rules only, nothing leaves the device. Plus an explicit statement of what is sent (extracted summary + subjects, never full bodies).

### Scanning screen
- Hero: **"100 emails per scan, at most"** + plain-English scope sentence.
- Emails per search: 25 / 50 / 100 / 200.
- How far back: 3 months / 6 months / 1 year / 2 years — applies to receipts so annual renewals surface; bills (60d), packages (30d) and invites (14d) keep their own tight windows and can only be *tightened* by a shorter setting, never widened.
- Per-domain toggles: Money / Packages / Meetings. Turning one off removes its Gmail query entirely — fewer API calls, less data read.
- Changes apply on the next scan, deliberately: silently re-scanning on every toggle would burn quota.

### Processing screen
- Headline: *"Read 84 emails, found 19 insights, AI corrected 3."*
- **Pipeline checklist** with live position: Reading mail → Finding insights → AI checking results → Saving.
- **Extracted** breakdown (zero rows omitted).
- **AI audit** — every correction in plain language: *"Dropped Github — not a real package"*, *"Renamed Nct → Flipkart"*. Notes name the thing, never a raw email id.
- Footnote: corrections touch stored insights only; Gmail scope is read-only.

## Why these are paid-tier features

| Feature | Why someone pays |
|---|---|
| Spend meter + no-cap warning | The app spends their money. Showing it honestly is table stakes for trust, and nobody else does it. |
| AI audit log | "The assistant edited my data and told me exactly what it changed" — the single strongest anti-black-box feature. |
| Scan depth control | Power users want 2 years of history; privacy-minded users want 3 months. Both are paying postures. |
| Model choice | Cheap default, upgrade path. Users self-select into cost. |
| Export | "Your data is yours" — kills lock-in objection, costs one clipboard call. |
| AI off switch | Makes the privacy claim falsifiable rather than rhetorical. |

## Not built yet (next candidates)

- **Per-insight feedback** ("this isn't a bill") feeding a local ignore-list — turns corrections into training data without a server.
- **Cost estimate before a scan** — "this scan will read ~200 emails, about ₹2" using model pricing.
- **Notification rules** — which trigger types are allowed to push, not just when.
- **Multi-account** — the biggest single unlock from [[One App Vision]]; Settings is where accounts get added.
- **Server-side key proxy** — required before public release; `.env` currently ships inside the IPA.
