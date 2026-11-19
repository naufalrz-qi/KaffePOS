import 'package:uuid/uuid.dart';

final _uuid = Uuid();

/// UUIDv7 (urut waktu) untuk ID transaksi & event yang dibuat di HP (desain §4).
String newId() => _uuid.v7();
