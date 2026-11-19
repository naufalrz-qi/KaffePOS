import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import 'escpos.dart';

class BtPrinter {
  const BtPrinter(this.name, this.address);

  final String name, address;
}

/// Jembatan ke MainActivity.kt: Bluetooth Classic SPP ke printer yang sudah di-pair (desain §13).
class PrinterChannel {
  static const _channel = MethodChannel('kaffepos/printer');

  static Future<List<BtPrinter>> paired() async {
    final list = await _channel.invokeListMethod<Map<Object?, Object?>>('paired') ?? const [];
    return [for (final m in list) BtPrinter('${m['name']}', '${m['address']}')];
  }

  static Future<void> send(String address, List<int> bytes) =>
      _channel.invokeMethod<void>('print', {'address': address, 'bytes': Uint8List.fromList(bytes)});
}

/// Printer pilihan, lebar kertas, dan cetak otomatis; disimpan di tabel meta.
class PrinterSettings extends ChangeNotifier {
  PrinterSettings(this.store);

  final Store store;
  String? address;
  String? name;
  int width = 32;
  bool autoPrint = true;

  Future<void> load() async {
    address = await store.meta('printer_address');
    name = await store.meta('printer_name');
    width = int.tryParse(await store.meta('paper_width') ?? '') ?? 32;
    autoPrint = await store.meta('auto_print') != '0';
    notifyListeners();
  }

  Future<void> choose(BtPrinter printer) async {
    await store.setMeta('printer_address', printer.address);
    await store.setMeta('printer_name', printer.name);
    await load();
  }

  Future<void> setWidth(int value) async {
    await store.setMeta('paper_width', '$value');
    await load();
  }

  Future<void> setAutoPrint(bool on) async {
    await store.setMeta('auto_print', on ? '1' : '0');
    await load();
  }

  /// Kirim ke printer. Mengembalikan pesan kesalahan atau null. Gagal cetak tidak pernah membatalkan transaksi (PRD K-13).
  Future<String?> printBytes(List<int> bytes) async {
    final target = address;
    if (target == null) return 'Printer belum dipilih (menu Printer).';
    try {
      await PrinterChannel.send(target, bytes);
      return null;
    } on PlatformException catch (e) {
      return e.code == 'permission'
          ? 'Izinkan akses Bluetooth (Perangkat sekitar), lalu cetak ulang.'
          : 'Printer gagal (${e.message}). Transaksi tetap tersimpan; cetak ulang dari Riwayat.';
    }
  }

  Future<String?> printLines(List<String> lines) => printBytes(escposText(lines));
}
