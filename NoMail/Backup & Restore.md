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

### 2. iCloud — add the capability
In **Xcode** → `Runner` target → *Signing & Capabilities* → **+ Capability → iCloud**:
- Tick **iCloud Documents**.
- Add container **`iCloud.com.nomail.nomail`**.

This writes `Runner.entitlements` (`com.apple.developer.icloud-container-identifiers`) and registers the container on the provisioning profile (team `68FA4847UT`). Rebuild — `FileManager.url(forUbiquityContainerIdentifier:)` then returns a real URL and `isAvailable` flips to true. The native handler is already in `AppDelegate.swift`; no code change needed.

> The entitlement is **not** committed by default because referencing an unprovisioned container breaks signed release builds. Add it via Xcode (which provisions it) rather than by hand.

## Status
- 288 tests pass (`test/backup_service_test.dart` proves bundle round-trip + full-store restore). `flutter analyze` clean.
- Release build signed + installed to the iPhone. iCloud reports unavailable until step 2; Drive prompts for the scope on first use after step 1.

Related: [[Architecture]], [[Development Log]]
