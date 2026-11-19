import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/ids.dart';
import 'snapshot.dart';

/// Satu baris outbox: event yang menunggu dikirim ke POST /sync/push.
class OutboxRow {
  OutboxRow(Map<String, Object?> r)
      : seq = r['seq'] as int,
        eventId = r['event_id'] as String,
        type = r['type'] as String,
        payload = r['payload'] as String,
        createdAt = r['created_at'] as String,
        status = r['status'] as String,
        lastError = r['last_error'] as String?;

  final int seq;
  final String eventId, type, payload, createdAt, status;
  final String? lastError;

  Map<String, Object?> toEvent() => {'id': eventId, 'type': type, 'data': jsonDecode(payload)};
}

/// Akses SQLite untuk meta, snapshot master, dan outbox. Operasi transaksi ada di sales_store.dart.
class Store {
  Store(this.db);

  final Database db;

  Future<String?> meta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  /// Nilai null menghapus key.
  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      await db.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Snapshot?> loadSnapshot() async {
    final rows = await db.query('master_snapshot');
    return rows.isEmpty ? null : Snapshot.parse(rows.first['version'] as int, rows.first['json'] as String);
  }

  Future<int> snapshotVersion() async => Sqflite.firstIntValue(await db.rawQuery('SELECT version FROM master_snapshot')) ?? 0;

  /// Ganti snapshot master secara utuh (desain §6.2).
  Future<void> saveSnapshot(int version, Map<String, dynamic> snapshot) => db.insert(
      'master_snapshot', {'id': 1, 'version': version, 'json': jsonEncode(snapshot)},
      conflictAlgorithm: ConflictAlgorithm.replace);

  /// Masukkan event ke outbox. Selalu dipanggil di dalam transaksi yang sama dengan perubahan datanya.
  Future<void> addEvent(DatabaseExecutor tx, String type, Map<String, Object?> data, DateTime now) => tx.insert(
      'outbox', {'event_id': newId(), 'type': type, 'payload': jsonEncode(data), 'created_at': isoUtc(now)});

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'PENDING'")) ?? 0;

  Future<String?> oldestPendingAt() async =>
      (await db.rawQuery("SELECT MIN(created_at) AS t FROM outbox WHERE status = 'PENDING'")).first['t'] as String?;

  Future<List<OutboxRow>> pendingBatch(int limit) async =>
      [for (final r in await db.query('outbox', where: "status = 'PENDING'", orderBy: 'seq', limit: limit)) OutboxRow(r)];

  Future<List<OutboxRow>> rejected() async =>
      [for (final r in await db.query('outbox', where: "status = 'REJECTED'", orderBy: 'seq DESC')) OutboxRow(r)];

  /// Terapkan hasil POST /sync/push (desain §5): ok/duplicate → SENT, rejected → REJECTED, retry → tetap antre.
  Future<void> applyResults(List<dynamic> results) => db.transaction((tx) async {
        for (final r in results.cast<Map<String, dynamic>>()) {
          switch (r['status']) {
            case 'ok' || 'duplicate':
              await tx.update('outbox', {'status': 'SENT'}, where: 'event_id = ?', whereArgs: [r['id']]);
            case 'rejected':
              await tx.update('outbox', {'status': 'REJECTED', 'last_error': r['reason']},
                  where: 'event_id = ?', whereArgs: [r['id']]);
            default:
              await tx.rawUpdate(
                  'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE event_id = ?', [r['reason'], r['id']]);
          }
        }
      });

  /// Hapus semua data lokal (reset device, PRD K-28).
  Future<void> wipe() => db.transaction((tx) async {
        for (final table in ['meta', 'master_snapshot', 'shifts', 'cash_movements', 'sales', 'outbox', 'receipt_seq']) {
          await tx.delete(table);
        }
      });
}
