# Project Status — Budget App (Cashew Fork)

## Snapshot

| Item | Value |
|------|-------|
| **Date** | 2026-05-22 |
| **Branch** | `stable/flutter-latest` |
| **Base commit** | `b970253` — migrate to Flutter 3.44.0 |
| **Stable commit** | `5bbd3df` — stable snapshot |
| **Flutter** | 3.44.0 (stable) |
| **Dart** | 3.12.0 |
| **Platform** | Windows (dev), Web (Edge), iOS (target via Codemagic) |

## Build Status

| Check | Result |
|-------|--------|
| `flutter pub get` | ✅ Pass |
| `dart run build_runner build` | ✅ Pass (424 outputs) |
| `flutter analyze` | ✅ 0 errors, 123 warnings, 102 infos |
| `flutter run -d edge` | ✅ App launches and runs |

## Architecture

```
D:\projects\budget_app\
├── budget/                   ← Flutter project
│   ├── lib/
│   │   ├── database/         ← drift ORM (SQLite)
│   │   ├── pages/            ← all UI pages
│   │   ├── widgets/          ← reusable widgets
│   │   ├── struct/           ← shared state/helpers
│   │   └── main.dart         ← entry point
│   ├── assets/
│   │   └── translations/     ← i18n (en.json, zh.json)
│   ├── ios/                  ← iOS platform config
│   ├── pubspec.yaml          ← dependencies (locked)
│   ├── codemagic.yaml        ← CI/CD
│   └── FIREBASE_SETUP.md     ← Firebase guide
├── .gitattributes            ← LF enforcement
├── .gitignore                ← Flutter + secrets
└── PROJECT_STATUS.md         ← this file
```

## Key Dependencies

| Package | Version | Notes |
|---------|---------|-------|
| drift | 2.33.0 | ORM, upgraded from 2.14 |
| drift_dev | 2.33.0 | Code gen, upgraded from 2.14 |
| build_runner | 2.4.13 | JIT mode (AOT fails on Unicode paths) |
| analyzer | 12.1.0 | Upgraded to fix Dart 3.12 crash |
| excel | 4.0.6 | Excel import/export |
| firebase_core | 3.15.2 | Cloud sync |
| easy_localization | 3.0.7 | i18n |

## Features Implemented

| Feature | Status |
|---------|--------|
| CSV Import/Export | ✅ Original Cashew |
| Excel (.xlsx) Import | ✅ Custom widget |
| Excel (.xlsx) Export | ✅ Custom widget (3-sheet) |
| Chinese UI (zh.json) | ✅ 1183 translations |
| Firebase Cloud Sync | ✅ Configured |
| Local SQLite (drift) | ✅ |
| Codemagic CI/CD | ✅ `codemagic.yaml` |
| English UI (en.json) | ✅ |

## Known Issues

See [TECH_DEBT.md](TECH_DEBT.md) for full categorized list.

| Severity | Count | Description |
|----------|-------|-------------|
| Warning | 123 | Flutter analyze warnings |
| Info | 102 | Flutter analyze infos |
| Error | 0 | No compilation errors |
