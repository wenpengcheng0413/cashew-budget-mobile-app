# Technical Debt — Budget App

Generated from `flutter analyze` on 2026-05-22.
Total: **225 issues** (0 errors, 123 warnings, 102 infos)

---

## 1. WARNING Level (123 issues)

### 1.1 notifyListeners misuse (68 issues)
**Type:** `invalid_use_of_visible_for_testing_member` + `invalid_use_of_protected_member`
**Severity:** Medium. `notifyListeners()` is called from outside `ChangeNotifier` subclasses. This is a pattern used throughout the codebase (34 call sites, each triggers 2 warnings). Not a crash risk but violates Flutter conventions.
**Files:** `activityPage.dart`, `budgetPage.dart`, and many page files.
**Fix difficulty:** High — requires refactoring notification logic. Do not attempt bulk replacement.

### 1.2 Unused local variables (20 issues)
**Type:** `unused_local_variable`
**Severity:** Low. Variables assigned but never read.
**Fix difficulty:** Low — remove the variable declarations. Safe to fix one by one.
**Files:** `tables.dart`, `addBudgetPage.dart`, `addCategoryPage.dart`, `addTransactionPage.dart`, and others.

### 1.3 Dead null-aware expressions (8 issues)
**Type:** `dead_null_aware_expression`
**Severity:** Low. `?.` or `??` on non-nullable expressions. No runtime impact but dead code.
**Files:** `tables.dart`, `functions.dart`

### 1.4 must_call_super violations (7 issues)
**Type:** `must_call_super`
**Severity:** Medium. Overrides of `initState`, `dispose`, etc. without calling `super`. Can cause state leaks.
**Files:** `budgetPage.dart` and others.

### 1.5 Dead code (5 issues)
**Type:** `dead_code`
**Severity:** Low. Unreachable code paths.
**Files:** `functions.dart`, `main.dart`

### 1.6 Third-party: sliding_sheet doc directives (8 issues)
**Type:** `doc_directive_unknown` + `doc_directive_missing_closing_tag`
**Severity:** Low. In `packages/sliding_sheet-0.5.2-modified/`. Cannot fix (third-party code).
**Action:** Suppress via `analysis_options.yaml` if desired.

### 1.7 Other warnings
| Type | Count | Notes |
|------|-------|-------|
| `unused_field` | 2 | Unused class fields |
| `unnecessary_null_comparison` | 2 | Null checks on non-nullable |
| `invalid_null_aware_operator` | 2 | `?.` on non-nullable |
| `include_file_not_found` | 1 | `flutter_lints/flutter.yaml` missing |

---

## 2. INFO Level (102 issues)

### 2.1 Deprecated member use (85 issues)
**Type:** `deprecated_member_use`
**Severity:** Low. Flutter 3.x deprecation warnings. Most common:
- `color.red`/`.green`/`.blue`/`.alpha` → use `color.r`/`.g`/`.b`/`.a` with `* 255.0` (colorPicker.dart, ~50 issues)
- `WillPopScope` → `PopScope` (multiple pages)
- `toolbarOptions` → `contextMenuBuilder` (addEmailTemplate.dart)
- `drift/web.dart` → `drift/wasm.dart` (web platform support)
- `cacheExtent` → `scrollCacheExtent` (reorderable_list.dart)

### 2.2 Unnecessary imports (9 issues)
**Type:** `unnecessary_import`
**Severity:** Trivial. Imports that are not needed.

### 2.3 Missing documentation (5 issues)
**Type:** `public_member_api_docs`
**Severity:** Trivial. Public members without doc comments.

### 2.4 Style issues (3 issues)
| Type | Count |
|------|-------|
| `avoid_positional_boolean_parameters` | 2 |
| `sort_pub_dependencies` | 1 |

---

## Fix Priority

| Priority | Category | Count | Effort |
|----------|----------|-------|--------|
| P1 | `must_call_super` | 7 | Medium |
| P2 | `unused_local_variable` + `unused_field` | 22 | Low |
| P3 | `dead_code` + `dead_null_aware_expression` | 13 | Low |
| P4 | `deprecated_member_use` (project) | ~82 | Medium-High |
| P5 | `notifyListeners` pattern | 68 | High (do not touch without plan) |
| Ignore | Third-party packages | 8 | N/A |

## Decision Log

| Date | Decision | Reason |
|------|----------|--------|
| 2026-05-22 | Keep `build_runner: ^2.4.7` (JIT mode) | AOT compiler crashes on Unicode paths |
| 2026-05-22 | `on StateError` catch in init DB | Cleaner than generic `catch(e)` |
| 2026-05-22 | Do not upgrade remaining 60 packages | Avoid cascading breakage |
