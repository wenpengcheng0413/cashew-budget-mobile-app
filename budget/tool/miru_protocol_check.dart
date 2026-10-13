import '../lib/integrations/miru/miru_protocol.dart';

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
  print('Miru protocol checks passed');
}
