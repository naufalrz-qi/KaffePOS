import 'package:kasir/data/db.dart';
import 'package:kasir/data/store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;

/// PIN 111111 (kasir) dan 222222 (manager), 1 iterasi supaya test cepat. Dibuat dengan hasher Django.
const kasirPinHash = r'pbkdf2_sha256$1$garamkasir$3QdGTIwAemak/JCfxaJ23r/oZkp2tcM2+kpQVX/OAnY=';
const managerPinHash = r'pbkdf2_sha256$1$garammanager$oge8k4MRCPqF6kE4YqD34F9+HAg5iLesqfPIgIdjxw0=';

/// Database SQLite in-memory yang baru (sqflite_common_ffi, jalan di Windows tanpa HP).
Future<Store> memoryStore() async {
  sqfliteFfiInit();
  return Store(await openDb(inMemoryDatabasePath, singleInstance: false, factory: databaseFactoryFfi));
}

/// Snapshot master seperti keluaran GET /sync/master (backend/api/snapshot.py).
Map<String, dynamic> snapshotJson({bool taxEnabled = false, bool voidNeedsManager = false, String minAppVersion = '1.0.0'}) => {
      'min_app_version': minAppVersion,
      'business': {'name': 'Kopi Uji', 'receipt_footer': 'IG @kopiuji'},
      'outlet': {
        'id': 'o1', 'code': 'GRB01', 'name': 'Gerobak Sudirman', 'type': 'MOBILE', 'timezone': 'Asia/Jakarta',
        'tax_enabled': taxEnabled, 'tax_rate_bp': 1000, 'tax_inclusive': false, 'rounding_unit': 0,
        'void_needs_manager': voidNeedsManager, 'receipt_header': 'Jl. Sudirman', 'receipt_footer': 'Terima kasih',
        'qris_image': null,
      },
      'device': {'id': 'd1', 'number': 3},
      'staff': [
        {'id': 'u-kasir', 'name': 'Andi', 'role': 'CASHIER', 'pin_hash': kasirPinHash, 'can_discount': false},
        {'id': 'u-manager', 'name': 'Bu Sari', 'role': 'MANAGER', 'pin_hash': managerPinHash, 'can_discount': true},
      ],
      'categories': [
        {'id': 'c1', 'name': 'Kopi', 'sort': 1},
      ],
      'products': [
        {'id': 'p-eskopi', 'category_id': 'c1', 'name': 'Es Kopi Susu', 'price': 18000, 'earns_stamp': true,
         'sort': 1, 'modifier_group_ids': ['g-ukuran']},
        {'id': 'p-americano', 'category_id': 'c1', 'name': 'Americano', 'price': 15000, 'earns_stamp': true,
         'sort': 2, 'modifier_group_ids': <String>[]},
      ],
      'modifier_groups': [
        {'id': 'g-ukuran', 'name': 'Ukuran', 'required': true, 'multi': false, 'sort': 1, 'options': [
          {'id': 'm-reg', 'name': 'Regular', 'price_delta': 0},
          {'id': 'm-large', 'name': 'Large', 'price_delta': 5000},
        ]},
      ],
      'payment_methods': ['CASH', 'QRIS', 'TRANSFER', 'EWALLET'],
      'stamp_rule': null,
    };
