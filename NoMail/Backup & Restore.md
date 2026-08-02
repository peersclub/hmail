# Backup & Restore

WhatsApp-style backup of everything NoMail has learned and computed, to **iCloud** or **Google Drive**, with restore on a fresh install.

## What travels (and what never does)

A backup is a single JSON document — a `BackupBundle` — aggregating the four on-device stores:

| Section | Store | Why it matters |
|---|---|---|
| `snapshot` | `InsightStore` (`insight_snapshot_v8`) | The computed insights (bills, deliveries, returns, travel, …). Re-derivable by a rescan, but restoring is instant. |
| `playbook` | `KnowledgeStore` (`playbook_v1`) | **The crown jewel** — the AI-earned recipes. Each took real model calls to learn; a rescan does *not* rebuild them. |
| `settings` | `SettingsStore` (`scan_settings_v1`) | Scan scope, AI toggle, brief hour. |
| `timelineOrder` | `TimelineOrderStore` | The user's chip order. |

**Mail never leaves Gmail.** The backup holds only NoMail's own derived data. Google Drive backups live in the hidden `appDataFolder` — invisible in the user's Drive and unreadable by any other app. iCloud backups live in the app's private ubiquity container.

## Architecture

Three decoupled concerns (mirrors the app's `MailSource` seam):

- **What** — `BackupBundle` (`lib/domain/backup_bundle.dart`), pure data, versioned envelope.
- **How** — `BackupTarget` interface (`lib/data/backup/backup_target.dart`) with `DriveBackupTarget`, `ICloudBackupTarget`, and `MemoryBackupTarget` (tests/null). `BackupService` (`collect`/`restore`) knows the stores; the target knows the cloud; neither knows the other.
- **When** — `BackupPrefs` (Off/Daily/Weekly). No phone daemon exists, so auto-backup is **opportunistic**: after a successful sync, if the interval has elapsed (`AppController._maybeAutoBackup`). Honest mobile equivalent of WhatsApp's nightly job.

Restore rehydrates all four stores, then `AppController._reloadFromStores()` refreshes in-memory state so the UI updates immediately.

UI: Settings → **Backup** (`lib/ui/screens/backup_screen.dart`) — last-backup status, Back Up Now, destination picker, frequency, Restore.

## ⚠️ Two enablement steps (need Victor's accounts)

The code is complete and ships today; both clouds need a one-time capability switch to go live. Until then the app runs, Drive works after step 1, and iCloud shows "Turn on iCloud."

### 1. Google Drive — add the OAuth scope
In **Google Cloud Console** → the NoMail project → *APIs & Services → OAuth consent screen → Edit → Scopes*, add:

```
https://www.googleapis.com/auth/drive.appdata
```

(Also ensure the **Google Drive API** is enabled under *Enabled APIs*.) The next "Back Up Now" will prompt for the Drive permission. `drive.appdata` is a narrow, non-sensitive scope — it grants access only to the app's own hidden folder, not the user's files.

### 2. iCloud — ⚠️ BLOCKED on a paid Apple Developer membership
**Attempted 2026-08-02 and it failed at signing.** The current signing team `68FA4847UT` ("Suresh Elangovan") is a **free/personal** Apple team, and Apple does **not** allow the iCloud capability on personal teams. `flutter build ios` returned:

> *"Personal development teams … do not support the iCloud capability."*
> *"Provisioning profile doesn't support the iCloud.com.nomail.nomail iCloud Container."*

The entitlement wiring was reverted so the release build stays green. **iCloud cannot be enabled until the app is signed by a team with a paid Apple Developer Program membership ($99/yr).** This is an account-tier limit, not a code issue — the Dart `ICloudBackupTarget` and the native `AppDelegate.swift` handler are complete and correct; they just report "unavailable" because there's no container.

Once on a paid team, enabling is the additive Xcode step:
- **Xcode** → `Runner` target → *Signing & Capabilities* → **+ Capability → iCloud** → tick **iCloud Documents** → add container **`iCloud.com.nomail.nomail`**.
- Rebuild. `FileManager.url(forUbiquityContainerIdentifier:)` returns a real URL, `isAvailable` flips to true, no code change needed.

> Add the capability via the Xcode GUI (which provisions the container in the portal), not by hand-editing `Runner.entitlements` — an unprovisioned container breaks signed release builds.

**Until then, Google Drive (step 1) is the working backup path.**

## Status
- 288 tests pass (`test/backup_service_test.dart` proves bundle round-trip + full-store restore). `flutter analyze` clean.
- Release build signed + installed to the iPhone. iCloud reports unavailable until step 2; Drive prompts for the scope on first use after step 1.

Related: [[Architecture]], [[Development Log]]
