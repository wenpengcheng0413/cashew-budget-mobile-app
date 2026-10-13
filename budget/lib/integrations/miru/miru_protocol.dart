import 'dart:convert';

import 'package:crypto/crypto.dart';

String miruHash(String value) => sha256.convert(utf8.encode(value)).toString();

Uri miruEndpoint(String address) {
  final uri = Uri.parse(address.trim());
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty ||
      uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException('请填写 HTTPS 服务器地址，不要附带路径或凭据');
  }
  return uri.replace(path: '', query: null, fragment: null);
}

String miruLocalDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

// Mirror the calendar day displayed by Cashew at sync time, with an explicit offset.
String miruDateWithOffset(DateTime value) {
  final local = value.toLocal();
  final offset = local.timeZoneOffset.inMinutes;
  final sign = offset < 0 ? '-' : '+';
  final minutes = offset.abs();
  return '${local.toIso8601String()}$sign${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

String miruAmount(double amount, int decimals) {
  if (!amount.isFinite || amount.abs() > 1000000000000 || decimals < 0 || decimals > 8) {
    throw const FormatException('账单金额或账户精度不受支持');
  }
  return amount.toStringAsFixed(decimals);
}
