import 'package:sqflite/sqflite.dart';

// Skema SQLite di HP (desain §6.2).
const _schema = [
  'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  'CREATE TABLE master_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), version INTEGER NOT NULL, json TEXT NOT NULL)',
  'CREATE TABLE shifts (id TEXT PRIMARY KEY, staff_id TEXT NOT NULL, opened_at TEXT NOT NULL, '
      'opening_cash INTEGER NOT NULL, closed_at TEXT, counted_cash INTEGER)',
  'CREATE TABLE cash_movements (id TEXT PRIMARY KEY, shift_id TEXT NOT NULL, at TEXT NOT NULL, '
      'direction TEXT NOT NULL, amount INTEGER NOT NULL, note TEXT NOT NULL)',
  'CREATE TABLE sales (id TEXT PRIMARY KEY, shift_id TEXT NOT NULL, receipt_no TEXT NOT NULL, '
      'created_at TEXT NOT NULL, total INTEGER NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL)',
  'CREATE INDEX sales_shift ON sales (shift_id)',
  "CREATE TABLE outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT NOT NULL UNIQUE, type TEXT NOT NULL, "
      "payload TEXT NOT NULL, created_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'PENDING', "
      'attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT)',
  'CREATE INDEX outbox_status ON outbox (status, seq)',
  'CREATE TABLE receipt_seq (date TEXT PRIMARY KEY, last INTEGER NOT NULL)',
];

/// Buka database lokal. Isolate kedua (workmanager) wajib `singleInstance: false` dan tidak menutupnya
/// (anjuran sqflite). Test memakai `inMemoryDatabasePath` + factory ffi.
Future<Database> openDb(String path, {bool singleInstance = true, DatabaseFactory? factory}) =>
    (factory ?? databaseFactory).openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          singleInstance: singleInstance,
          onCreate: (db, _) async {
            for (final sql in _schema) {
              await db.execute(sql);
            }
          },
        ));

Future<String> dbPath() async => '${await getDatabasesPath()}/kasir.db';
