import 'dart:convert';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import '../lib/integrations/miru/miru_protocol.dart';

enum WalletWidgetFixture { WalletSwitcher, WalletList }
enum BudgetFilterFixture { includeIncome, defaultBudgetTransactionFilters }

void check(bool condition, String name) {
  if (!condition) throw StateError(name);
}

void main() {
  check(miruEndpoint(' https://miru.example/ ').toString() == 'https://miru.example', 'normalize endpoint');
  for (final url in ['http://miru.example', 'https://user:secret@miru.example',
    'https://miru.example?token=bad', 'https://miru.example/api', 'https://miru.example/#bad']) {
    bool rejected = false;
    try { miruEndpoint(url); } on FormatException { rejected = true; }
    check(rejected, 'reject unsafe endpoint');
  }
  check(miruAmount(0.1 + 0.2, 2) == '0.30', 'decimal serialization');
  check(miruAmount(-25.3, 2) == '-25.30', 'signed amount');
  check(miruAmount(42, 0) == '42', 'zero decimal currency');
  check(miruHash('abc') == 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', 'wire digest');
  final time = DateTime(2026, 10, 12, 0, 0);
  check(miruLocalDate(time) == '2026-10-12', 'calendar day');
  check(DateTime.parse(miruDateWithOffset(time)).isAtSameMomentAs(time), 'explicit timezone');
  // Reproduce generated Drift toJson() behavior without importing Flutter UI.
  final serializer = driftRuntimeOptions.defaultSerializer;
  final capture = {
    'wallets': [{'raw': {'homePageWidgetDisplay': serializer.toJson<List<WalletWidgetFixture>>([WalletWidgetFixture.WalletList])}}],
    'budgets': [{'raw': {'budgetTransactionFilters': serializer.toJson<List<BudgetFilterFixture>>([BudgetFilterFixture.defaultBudgetTransactionFilters, BudgetFilterFixture.includeIncome])}}],
    'transactions': [{'amount': '-0.10', 'note': '午饭🍜', 'raw': {'type': 1, 'other': null}}],
  };
  bool oldEncoderFailed = false;
  try { jsonEncode(capture); } on JsonUnsupportedObjectError { oldEncoderFailed = true; }
  check(oldEncoderFailed, 'regression fixture reproduces first-upload failure');
  final wire = miruJsonEncode(capture);
  final decoded = jsonDecode(wire);
  check(decoded['wallets'][0]['raw']['homePageWidgetDisplay'][0] == 'WalletList', 'wallet enum list');
  check(decoded['budgets'][0]['raw']['budgetTransactionFilters'][1] == 'includeIncome', 'budget enum list');
  check(decoded['transactions'][0]['amount'] == '-0.10' && decoded['transactions'][0]['note'] == '午饭🍜', 'preserve actual fields');
  check(miruHash(wire) == miruHash(miruJsonEncode(capture)), 'hash and upload share encoding');
  bool unknownRejected = false;
  try { miruJsonEncode({'unknown': Object()}); } on JsonUnsupportedObjectError { unknownRejected = true; }
  check(unknownRejected, 'unknown fields fail closed');
  print('Miru protocol checks passed');
}
