import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../core/ids.dart';
import 'store.dart';

class Shift {
  Shift(Map<String, Object?> r)
      : id = r['id'] as String,
        staffId = r['staff_id'] as String,
        openedAt = DateTime.parse(r['opened_at'] as String),
        openingCash = r['opening_cash'] as int;

  final String id, staffId;
  final DateTime openedAt;
  final int openingCash;
}

/// Rekap kas shift (desain §7.5): kas seharusnya = modal + tunai + kas masuk − kas keluar.
class ShiftRecap {
  const ShiftRecap({
    required this.openingCash,
    required this.cashSales,
    required this.cashIn,
    required this.cashOut,
    required this.salesCount,
    required this.salesTotal,
  });

  final int openingCash, cashSales, cashIn, cashOut, salesCount, salesTotal;

  int get expected => openingCash + cashSales + cashIn - cashOut;
}

class SaleRow {
  SaleRow(Map<String, Object?> r)
      : id = r['id'] as String,
        shiftId = r['shift_id'] as String,
        receiptNo = r['receipt_no'] as String,
        createdAt = DateTime.parse(r['created_at'] as String),
        total = r['total'] as int,
        voided = r['status'] == 'VOIDED',
        payload = jsonDecode(r['payload'] as String) as Map<String, dynamic>;

  final String id, shiftId, receiptNo;
  final DateTime createdAt;
  final int total;
  final bool voided;
  final Map<String, dynamic> payload;
}

/// Operasi transaksi. Setiap perubahan + event outbox-nya ditulis dalam SATU transaksi SQLite (desain §6.2).
extension SalesStore on Store {
  Future<Shift?> openShift() async {
    final rows = await db.query('shifts', where: 'closed_at IS NULL', limit: 1);
    return rows.isEmpty ? null : Shift(rows.first);
  }

  Future<Shift> startShift({required String staffId, required int openingCash, required DateTime now}) async {
    final row = {'id': newId(), 'staff_id': staffId, 'opened_at': isoUtc(now), 'opening_cash': openingCash};
    await db.transaction((tx) async {
      await tx.insert('shifts', row);
      await addEvent(tx, 'shift.opened',
          {'shift_id': row['id'], 'staff_id': staffId, 'opened_at': row['opened_at'], 'opening_cash': openingCash}, now);
    });
    return Shift(row);
  }

  Future<void> moveCash({
    required String shiftId,
    required String staffId,
    required String direction,
    required int amount,
    required String note,
    required DateTime now,
  }) =>
      db.transaction((tx) async {
        final row = {'id': newId(), 'shift_id': shiftId, 'at': isoUtc(now), 'direction': direction, 'amount': amount, 'note': note};
        await tx.insert('cash_movements', row);
        await addEvent(tx, 'cash.moved', {...row, 'staff_id': staffId}, now);
      });

  /// Simpan penjualan (desain §6.2, §7.2): nomor struk dari `receipt_seq[tanggal lokal]`, baris `sales`,
  /// dan event `sale.completed` dalam satu transaksi. [sale] = payload tanpa `receipt_no`.
  Future<Map<String, dynamic>> saveSale(Map<String, dynamic> sale,
          {required String outletCode, required int deviceNo, required String timezone, required DateTime now}) =>
      db.transaction((tx) async {
        final date = yymmdd(outletTime(now, timezone));
        final last = Sqflite.firstIntValue(await tx.rawQuery('SELECT last FROM receipt_seq WHERE date = ?', [date])) ?? 0;
        await tx.insert('receipt_seq', {'date': date, 'last': last + 1}, conflictAlgorithm: ConflictAlgorithm.replace);
        final seq = (last + 1).toString().padLeft(4, '0');
        final full = {...sale, 'receipt_no': '$outletCode-$deviceNo-$date-$seq'};
        await tx.insert('sales', {
          'id': full['sale_id'],
          'shift_id': full['shift_id'],
          'receipt_no': full['receipt_no'],
          'created_at': full['created_at'],
          'total': full['total'],
          'status': 'COMPLETED',
          'payload': jsonEncode(full),
        });
        await addEvent(tx, 'sale.completed', full, now);
        return full;
      });

  Future<void> voidSale({
    required String saleId,
    required String staffId,
    String? approvedById,
    required String reason,
    required DateTime now,
  }) =>
      db.transaction((tx) async {
        await tx.update('sales', {'status': 'VOIDED'}, where: 'id = ?', whereArgs: [saleId]);
        await addEvent(tx, 'sale.voided',
            {'sale_id': saleId, 'staff_id': staffId, 'approved_by_id': approvedById, 'voided_at': isoUtc(now), 'reason': reason}, now);
      });

  Future<ShiftRecap> recap(Shift shift) async {
    var cashSales = 0, salesTotal = 0, cashIn = 0, cashOut = 0;
    final sales = await db.query('sales', where: "shift_id = ? AND status = 'COMPLETED'", whereArgs: [shift.id]);
    for (final row in sales) {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      salesTotal += payload['total'] as int;
      for (final p in (payload['payments'] as List).cast<Map<String, dynamic>>()) {
        if (p['method'] == 'CASH') cashSales += p['amount'] as int;
      }
    }
    for (final m in await db.query('cash_movements', where: 'shift_id = ?', whereArgs: [shift.id])) {
      if (m['direction'] == 'IN') {
        cashIn += m['amount'] as int;
      } else {
        cashOut += m['amount'] as int;
      }
    }
    return ShiftRecap(
        openingCash: shift.openingCash, cashSales: cashSales, cashIn: cashIn, cashOut: cashOut,
        salesCount: sales.length, salesTotal: salesTotal);
  }

  Future<void> closeShift({required Shift shift, required String staffId, required int countedCash, required DateTime now}) =>
      db.transaction((tx) async {
        await tx.update('shifts', {'closed_at': isoUtc(now), 'counted_cash': countedCash}, where: 'id = ?', whereArgs: [shift.id]);
        await addEvent(tx, 'shift.closed',
            {'shift_id': shift.id, 'staff_id': staffId, 'closed_at': isoUtc(now), 'counted_cash': countedCash}, now);
      });

  /// Riwayat di HP (PRD K-15): isi tabel `sales` = shift berjalan + 7 hari terakhir.
  Future<List<SaleRow>> history() async =>
      [for (final r in await db.query('sales', orderBy: 'created_at DESC', limit: 500)) SaleRow(r)];

  /// Hapus data terkirim yang lebih tua dari 7 hari (desain §6.2). Penjualan shift yang masih terbuka
  /// dan event yang belum terkirim tidak pernah dihapus.
  Future<void> cleanup(DateTime now) async {
    final cutoff = isoUtc(now.subtract(const Duration(days: 7)));
    await db.delete('outbox', where: "status = 'SENT' AND created_at < ?", whereArgs: [cutoff]);
    await db.delete('sales',
        where: 'created_at < ? AND shift_id NOT IN (SELECT id FROM shifts WHERE closed_at IS NULL)', whereArgs: [cutoff]);
    await db.delete('cash_movements', where: 'shift_id IN (SELECT id FROM shifts WHERE closed_at < ?)', whereArgs: [cutoff]);
    await db.delete('shifts', where: 'closed_at < ?', whereArgs: [cutoff]);
  }
}
