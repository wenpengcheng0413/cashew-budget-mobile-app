# Safe Development Rules — Budget App

> **Purpose:** Prevent future agents and developers from introducing instability.
> **Last updated:** 2026-05-22 (post Flutter 3.44.0 SDK migration)
> **Working path:** `D:\projects\budget_app\budget`

---

## 1. Protected Directories — DO NOT MODIFY CASUALLY

These directories form the stable core. Changes here require explicit justification:

| Directory | Reason |
|-----------|--------|
| `budget/lib/database/` | Drift ORM schema + generated code. Changes cascade to `tables.g.dart`. |
| `budget/lib/struct/` | Shared state, settings, global singletons. Tight coupling across all pages. |
| `budget/lib/widgets/framework/` | Navigation framework, page framework. Every page depends on these. |
| `budget/packages/` | Modified third-party packages (sliding_sheet, reorderable_list). Do not upgrade. |
| `budget/ios/` | iOS platform config, signing, Firebase plist. |
| `budget/assets/translations/` | i18n JSON files. Key names are used across 100+ files. |

## 2. Stable Layer Files — READ-ONLY Without Review

These files define the architecture. Changing them affects the entire app:

| File | Role |
|------|------|
| `pubspec.yaml` | Dependency versions. **Do not upgrade without explicit request.** |
| `pubspec.lock` | Locked dependency graph. Committed intentionally for reproducibility. |
| `analysis_options.yaml` | Lint rules. Currently references missing `flutter_lints`. |
| `lib/main.dart` | App entry, Firebase init, theme setup, localization init. |
| `lib/colors.dart` | Theme colors, `AppColors`, `HexColor`, `getColorScheme`. |
| `lib/functions.dart` | Utility functions used everywhere. |
| `lib/database/tables.dart` | Drift table definitions. |
| `lib/database/tables.g.dart` | Auto-generated. Regenerate via `build_runner`. |
| `lib/struct/settings.dart` | App settings singleton. |
| `lib/struct/databaseGlobal.dart` | Database singleton. |
| `.gitattributes` | LF line ending enforcement. **Do not remove.** |
| `.gitignore` | Ignore patterns for secrets and build artifacts. |

## 3. Where to Put New Code

| Type of change | Location | Example |
|----------------|----------|---------|
| New page | `lib/pages/` | `lib/pages/myNewPage.dart` |
| New widget | `lib/widgets/` | `lib/widgets/myNewWidget.dart` |
| New database table | `lib/database/tables.dart` + run `build_runner` | Add `DataClass` + table definition |
| New translation key | `assets/translations/generated/en.json` + `zh.json` | Add key to BOTH files |
| New feature config | `lib/struct/settings.dart` or new file in `struct/` | Follow existing pattern |
| CI/CD changes | `codemagic.yaml` | Follow Codemagic schema |

## 4. Forbidden Operations (Without Explicit User Request)

### 4.1 Never do these automatically:
- ❌ Upgrade any package in `pubspec.yaml`
- ❌ Run `flutter pub upgrade` or `flutter pub outdated --upgrade`
- ❌ Change `analysis_options.yaml` lint rules
- ❌ Refactor state management (Provider pattern is locked)
- ❌ Change theme system or color scheme structure
- ❌ Replace `notifyListeners()` call pattern (known tech debt, see TECH_DEBT.md)
- ❌ Run `dart format` or any bulk formatter on the entire codebase
- ❌ Delete or rename any `Pk` suffix fields (database primary keys)
- ❌ Modify `build_runner` version (2.4.x JIT mode is required for Unicode path support)
- ❌ Change `.gitattributes` line ending rules

### 4.2 Build system rules:
- Always use `build_runner` from path: `D:\projects\budget_app\budget`
- Never use paths containing non-ASCII characters (Chinese, etc.) — Dart AOT compiler crashes
- After any change to `lib/database/tables.dart`, run: `dart run build_runner build --delete-conflicting-outputs`
- Before committing: `flutter analyze` must show 0 new errors

## 5. How to Avoid SDK Migration Pollution

### 5.1 When a new Flutter/Dart version is installed:
1. Run `flutter analyze` first — capture the baseline warning count
2. If new deprecation warnings appear, do NOT do bulk find-and-replace
3. Fix deprecated APIs **one file at a time**, test each change
4. Commit each file fix separately with clear messages like:
   ```
   fix: migrate WillPopScope to PopScope in settingsPage
   ```

### 5.2 Migration checklist per file:
- [ ] Read the entire file before editing
- [ ] Understand what the deprecated API does in context
- [ ] Verify the replacement API has identical behavior
- [ ] `flutter analyze` after each file change
- [ ] Commit before moving to the next file

### 5.3 What went wrong last time (lessons learned):
- The original SDK migration (`b970253`) touched 105+ files in a single commit
- This made it impossible to review individual changes
- The migration was done via bulk find-and-replace
- Result: some replacements may not be semantically identical
- **New rule:** Never migrate more than 5 files per commit

## 6. Commit Conventions

```
fix: <description>          — bug fix
feat: <description>         — new feature  
chore: <description>        — config, docs, non-code
refactor: <description>     — code restructuring (rare, needs approval)
```

## 7. Pre-Commit Checklist

```bash
cd D:\projects\budget_app\budget
flutter analyze          # Must show 0 new errors
flutter run -d edge      # Must launch without runtime crash
git diff --stat          # Review what changed
```

## 8. Emergency Contacts

If the app fails to build:
1. Check `flutter doctor` for environment issues
2. Verify path is pure ASCII: `D:\projects\budget_app\budget`
3. Run `flutter clean && flutter pub get && dart run build_runner build`
4. Check `PROJECT_STATUS.md` for known baseline state
5. Check `TECH_DEBT.md` for known issues
