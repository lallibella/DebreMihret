# Debre Mihret St Michael Church

Local-first iPhone admin app for managing Debre Mihret St Michael Church servants, assignments, schedules, and Telegram reminders.

## Current Build

This repository currently contains a native SwiftUI iOS app because this Mac has Xcode installed, but Flutter/Dart are not installed. The app is structured around a small local domain model so the same workflows can be ported to Flutter for Android after the Flutter toolchain is available.

## Implemented

- Servant CRUD with name, phone number, Telegram chat ID, notes, and role qualifications.
- Task CRUD with required headcount, task type, and qualified roles.
- One-tap Sunday schedule generation with role matching and simple fair rotation from past assignments.
- Custom occasion creation with date/time, custom tasks, and manual assignment.
- Manual assignment override for every schedule slot before or after finalizing.
- Encrypted local persistence using AES-GCM, with the database key stored in iOS Keychain.
- Password-encrypted backup export/import for moving data to another device.
- Optional app lock with Face ID/device authentication and PIN fallback.
- In-app English/Amharic language switch in Settings.
- Telegram deep links using `https://t.me/<bot>?start=<servant-id>`.
- Telegram polling through `getUpdates` to link servants without a server.
- Telegram reminder sending through `sendMessage`.
- Reminder preparation:
  - Sunday service: Friday evening, Saturday evening, Sunday morning.
  - Custom occasions: three reminders spaced between event creation and event start.
- iOS background app refresh registration for due reminder attempts.

## Run On iPhone

1. Open `DebremihretServiceScheduler.xcodeproj` in Xcode.
2. Select the `DebremihretServiceScheduler` scheme.
3. Select your iPhone or an iPhone simulator.
4. For a physical iPhone, set your Apple development team in the target Signing & Capabilities panel.
5. Build and run.

Command-line simulator build:

```sh
xcodebuild -project DebremihretServiceScheduler.xcodeproj \
  -scheme DebremihretServiceScheduler \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/DebremihretServiceSchedulerDerived \
  build CODE_SIGNING_ALLOWED=NO
```

## Telegram Setup

1. Create or configure your Telegram bot with BotFather.
2. Paste the bot token into Settings.
3. Add a servant.
4. Open the servant detail screen and share the generated Telegram link.
5. The servant taps Start in Telegram.
6. In the app, tap Sync Telegram Links.

Because this app has no backend, Telegram cannot push chat IDs directly into the phone while the app is offline. The admin app polls Telegram updates when Sync Telegram Links is tapped or when the app gets a background opportunity.

## Manual Telegram Messages

For rare cases where the admin needs help outside the normal schedule flow, Dashboard -> Manual Telegram Message lets the admin select one or more Telegram-linked servants, write a custom message, and send it through the configured Debre Mihret St Michael Church Telegram bot. Servants without a linked Telegram Chat ID are shown as not available for direct bot messages until they complete the Telegram Start link flow.

## Admin Access

This is a local-first single-device admin app. Whoever can unlock the organizer's phone and pass the in-app lock is the active admin.

- First launch requires a 4-digit in-app PIN.
- When the app is reopened after going to the background, it locks again and asks for Face ID, Touch ID, device passcode, or the app PIN.
- Admin handoff uses Settings -> Export Backup and Settings -> Import Backup.
- Imported backups keep the receiving phone's local app lock settings, so a new organizer does not inherit the previous organizer's PIN.

## Language

The app supports English and Amharic from Settings -> Language. The setting applies immediately on the phone and is included in encrypted backups, so an imported backup restores the organizer's preferred app language along with the Debre Mihret St Michael Church data.

## Admin Handoff Procedure

Use this when a new organizer, deacon, or trusted servant needs to take over scheduling.

1. Current organizer opens Settings.
2. Current organizer enters a backup password only they and the new organizer will know.
3. Current organizer taps Export Backup.
4. Current organizer shares the `.dmsbackup` file with the new organizer using AirDrop, Telegram, email, or another trusted method.
5. Current organizer shares the backup password separately, not in the same message as the backup file.
6. New organizer installs Debre Mihret St Michael Church and completes the first-launch app lock setup on their own phone.
7. New organizer opens Settings, enters the backup password, taps Import Backup, and selects the received file.
8. New organizer confirms the servants, tasks, schedules, and Telegram settings appear correctly.

Important local-first note: the backup is a point-in-time copy. There is no cloud sync. If both organizers keep using separate copies of the app after the handoff, their schedules will diverge. After a real handoff, choose one active admin device and treat it as the source of truth.

Security note: the backup contains Debre Mihret St Michael Church servant details and Telegram bot settings. Share it only with an authorized organizer, use a strong backup password, and delete extra backup copies after import.

## Background Reminder Note

iOS background refresh is opportunistic. The app registers a background refresh task and can send due Telegram reminders when iOS wakes it, but Apple does not guarantee exact execution at Friday/Saturday/Sunday reminder times for a fully serverless app. The Dashboard and Schedule screens include Send Due Reminders so the admin can manually force any pending due reminders.

For guaranteed exact remote reminder delivery, the future architecture would need either a tiny backend/webhook worker or a scheduled automation service. The current implementation preserves the requested local-first/no-server design.

## Android Path

Install Flutter/Dart, then port the existing model and store behavior to:

- Flutter UI
- Hive or Isar encrypted storage
- `workmanager` on Android
- `background_fetch`/BackgroundTasks on iOS
- `http` or `dio` for Telegram

The iOS app in this repo is the runnable first version for iPhone testing.
