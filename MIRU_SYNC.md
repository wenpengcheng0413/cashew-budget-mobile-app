# Miru ledger sync (iOS, 5.4.3+418)

## Build 418: first-upload and LiveContainer flow fix

The first pairing was accepted by the server, but Drift's generated `toJson()` retains enum lists for wallet home-page settings and budget filters. Plain `jsonEncode()` failed before sending the first snapshot. The new shared wire encoder converts nested enums to their names, preserving all other source fields and using identical serialization for snapshot hashing and transmission. The protocol check reproduces the old failure using Drift's actual serializer and validates the corrected payload.

The settings page now shows saved pairing separately from upload progress and hides the pairing form after success. Retry sync does not consume another pairing code. LiveContainer users can close Miru before opening Cashew: the pairing code lives on the server for ten minutes and no concurrent app execution is needed. Update Cashew in the same existing container, keep the saved Keychain credential, and press 立即同步. Miru and the server do not need an update for this fix.

Continue entering transactions in Cashew. In Miru, open 我的账本 → 连接 Cashew, then copy its HTTPS address and one-time pairing code into Cashew 设置 → 米汝同步. The code expires after ten minutes. With the private Miru deployment, Tailscale must be connected on the phone.

The first successful sync uploads all transactions, wallets, categories, budgets and objectives as an atomic snapshot. Editing and deleting remain in Cashew. Foreground changes are debounced for three seconds; a thirty-second foreground check covers bulk changes. Reopen Cashew after an offline period. iOS background execution is not guaranteed, so Miru always shows the last successful sync time.

Before updating a sideloaded installation, export a Cashew backup and preserve the existing app/container. Do not uninstall the old app to update it. Install the new IPA using the same app identity/container so the existing database remains available.

The upload token is stored in iOS Keychain, separately from exported settings and database backups. Re-pairing rotates it; Miru can revoke it. HTTPS redirects are disabled. Restoring a database pauses sync before the file is overwritten and persists a reconciliation marker. Restart Cashew after restoring, then explicitly approve the proposed snapshot in Miru. Large deletions or an empty replacement also require approval.

The protocol preserves raw source fields and fixed-decimal amounts; summaries use original currencies and exclude transfers, balance adjustments, loans, skipped, unpaid and future entries. All these records remain visible in transaction history. Calendar dates mirror Cashew's local display at synchronization time; historical travel timezone is not reconstructed. Missing wallet currency is labelled UNKNOWN rather than guessed. Attachments/images are not uploaded. Version 1 accepts up to 100,000 transactions and a 16 MiB payload; exceeding either limit fails without replacing the last good snapshot. Chunked upload is not implemented.

## Protected-file review

- `main.dart` adds a lifecycle host without changing Firebase, themes or navigation.
- `database/platform/native.dart` pauses uploads immediately before restore overwrites the database. Schema 46 and generated database code are unchanged.
- `ios/Runner/AppDelegate.swift` adds a narrow Keychain method channel for this integration only.
- `pubspec.yaml` declares existing locked http 1.6.0 and crypto 3.0.7 dependencies directly; no dependency version is upgraded.
- CI pins Flutter 3.44.0 to the repository's validated migration SDK and adds the pure protocol check. The IPA output directory is explicitly created.

Validation: `dart tool/miru_protocol_check.dart`; `dart analyze lib/integrations/miru lib/pages/miruSyncPage.dart lib/database/platform/native.dart` (no issues). Native Keychain registration and unsigned iOS compilation additionally require the Codemagic build; pairing and database persistence need device verification.
