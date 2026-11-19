# Desain Teknis — KaffePOS

| | |
|---|---|
| Versi | 0.1 — draft untuk review |
| Tanggal | 19 November 2026 |
| Dasar | [PRD v0.3](PRD.md) |

## 0. Ringkasan Keputusan

- **Satu aplikasi Django** melayani tiga permukaan: API mobile & dashboard di `app.<domain>`, kartu member di `member.<domain>`.
- **SQL Server 2025 Express** (gratis, database maks **50 GB**; versi 2022 hanya 10 GB) lewat `mssql-django`.
- **ID = UUIDv7.** `mssql-django` menyimpan UUID sebagai `char(32)`. Karena UUIDv7 berurutan waktu, insert tetap rapi di index. Data transaksi diberi ID di HP.
- **Master data di HP = satu snapshot JSON**, diganti utuh saat nomor versinya berubah. Tidak ada tabel master per entitas di HP.
- **Transaksi dikirim sebagai event lewat outbox.** Setiap event idempotent lewat kunci entitasnya, jadi server tidak perlu tabel log event.
- **Penjualan tidak pernah ditolak karena aturan bisnis.** Penjualan diterima lalu diberi tanda (flag) untuk ditinjau. Penolakan hanya untuk data rusak; event yang belum bisa diproses karena urutan akan dicoba ulang.
- **Uang = integer Rupiah**, dengan satu rumus total yang identik di Dart & Python, dijaga oleh file test vector bersama.
- **Tanpa Redis, Celery, atau antrean job**: cukup cron + Django management command; cache untuk rate-limit pakai tabel database.

## 1. Kebutuhan, Batasan, Estimasi Beban

Kebutuhan fungsional & non-fungsional ada di PRD §8 dan §12. Batasan yang membentuk desain:
- SQL Server Express: maks 1 socket/4 core, buffer pool ±1,4 GB, database maks 50 GB (versi 2025).
- Tanpa layanan berbayar per pemakaian (PRD §4).
- Satu tenant sekarang, struktur siap multi-tenant (PRD A-02).
- Tim: Python (backend) dan Flutter (mobile).

| Besaran (batas atas PRD: 50 device, 10 ribu transaksi/hari) | Estimasi |
|---|---|
| Request ke server | Puncak < 5 request/detik (push per transaksi + cek master tiap 5 menit per device) |
| Ukuran 1 penjualan di database | ±2 KB (item, modifier, pembayaran, ledger stamp, index) |
| Pertumbuhan database | 2 ribu transaksi/hari ≈ 1,5 GB/tahun; 10 ribu ≈ 7 GB/tahun → batas 50 GB aman bertahun-tahun |
| Snapshot master per outlet | 100 produk + modifier + staf ≈ 30–60 KB JSON |

## 2. Arsitektur

```
HP kasir (Flutter + SQLite) ─┐
Browser owner/manager ───────┼─HTTPS─► Caddy ─► Django + Gunicorn ─► SQL Server 2025 Express
HP pelanggan (PWA) ──────────┘          │         ├─ /api/v1       app.<domain>
                                        │         ├─ dashboard     app.<domain>
                                        │         └─ kartu member  member.<domain>
                                        └─ file statis & media (volume)
cron di host: backup database · job harian (stamp hangus, redeem yatim)
```

**Struktur repo (monorepo)**
```
KaffePOS/
├─ docs/                     PRD.md, DESAIN-TEKNIS.md
├─ shared/totals_cases.json  test vector rumus total (dipakai pytest & dart test)
├─ backend/
│  ├─ kaffepos/              settings, urls, middleware (host → urlconf, tenant aktif)
│  ├─ core/                  Tenant, User, Outlet, Device, AuditLog, scoping tenant, versi master
│  ├─ catalog/               Category, Product, ModifierGroup, ModifierOption
│  ├─ sales/                 Shift, CashMovement, Sale, SaleItem, SaleItemModifier, Payment, totals.py
│  ├─ loyalty/               Member, CardActivation, StampRule, StampLedger, stamps.py
│  ├─ api/                   Django Ninja: device, sync, members, loyalty
│  ├─ dashboard/             view & template owner/manager
│  ├─ card/                  view & template kartu member, manifest, service worker
│  └─ Dockerfile
├─ mobile/                   aplikasi Flutter
└─ deploy/                   docker-compose.yml, Caddyfile, .env.example, backup.sh, crontab
```

## 3. Backend (Django)

### 3.1 Konfigurasi penting

| Setting | Nilai | Alasan |
|---|---|---|
| `AUTH_USER_MODEL` | `core.User`, sejak migrasi pertama | Mengganti model user setelah ada data itu sulit |
| `USE_TZ` / `TIME_ZONE` | `True` / `Asia/Jakarta` | Database menyimpan UTC; tampilan default WIB |
| `ATOMIC_REQUESTS` | `True` | Setiap request = satu transaksi; perubahan master & kenaikan versinya commit bersama |
| `CACHES` | `DatabaseCache` | Rate-limit berlaku lintas worker tanpa Redis |
| `DATABASES` | engine `mssql`, driver "ODBC Driver 18 for SQL Server" | Di dalam jaringan Docker pakai `TrustServerCertificate=yes` |
| Opsi database | `READ_COMMITTED_SNAPSHOT ON` | Pembaca tidak memblokir penulis (perilaku seperti PostgreSQL), jadi dashboard tidak mengganggu sync |

### 3.2 Scoping tenant
- Model abstrak `TenantScoped`: kolom `tenant`, manager `objects` (otomatis difilter), dan `all_tenants` (tanpa filter, khusus job/admin).
- Tenant aktif disimpan di `contextvars`. Diisi oleh middleware dashboard (dari user login), auth API (dari device), dan view kartu (dari sesi/aktivasi). Job memakai `with tenant_context(t):`.
- **Fail closed**: query lewat `objects` tanpa tenant aktif → error, bukan data semua tenant.
- `save()` mengisi `tenant` dari konteks jika kosong.
- Tabel M2M otomatis Django tidak punya `tenant_id`. Ini aman karena tabel itu hanya diakses lewat induknya yang sudah ber-tenant.

### 3.3 Autentikasi

| Permukaan | Mekanisme |
|---|---|
| Dashboard | Session Django. Hanya role OWNER/MANAGER yang boleh login. Gagal login 5× dalam 15 menit per username+IP → ditahan sementara |
| API mobile | `Authorization: Bearer <token device>`. Server menyimpan SHA-256 token. Device dicabut → 401 `device_revoked` |
| Kartu member | Session Django di host `member.<domain>` (cookie terpisah dari dashboard), umur 1 tahun, berisi `member_id` + `card_epoch` |
| PIN staf (diverifikasi offline di HP) | PBKDF2-SHA256 format Django `pbkdf2_sha256$iterasi$salt$hash` dengan iterasi rendah (awal 20.000). Jumlah iterasi adalah kenop kalibrasi: setel di HP termurah supaya verifikasi < 300 ms. PIN terpisah dari password dashboard |

### 3.4 Versi master data
- `Tenant.master_version` (bigint) naik +1 setiap kali data master berubah: profil usaha, Outlet, Category, Product, ModifierGroup, ModifierOption, staf (User), StampRule, termasuk relasi M2M-nya.
- Satu receiver sinyal (`post_save`, `post_delete`, `m2m_changed`) untuk daftar model tersebut menjalankan `UPDATE … SET master_version = master_version + 1`. Karena `ATOMIC_REQUESTS`, kenaikan versi commit bersama perubahannya.
- Penyimpanan yang hanya mengubah `last_login` diabaikan.
- Aturan: jangan memakai `QuerySet.update()`/`bulk_update()` pada model master, karena keduanya tidak memicu sinyal.

## 4. Skema Database

**Konvensi**
- PK `id` = UUIDv7, tersimpan sebagai `char(32)`. Data transaksi diberi ID di HP. Data master & member diberi ID oleh server dengan `uuid.uuid7()` bawaan Python 3.14.
- `tenant_id` ada di semua tabel, kecuali `core_tenant` dan tabel M2M otomatis.
- Uang `bigint` Rupiah; persentase `int` basis poin (1000 = 10,00%); waktu `datetime2` UTC.
- Enum = `varchar` pendek (CharField + choices).
- **Tidak dipakai**: trigger, unique/index bersyarat (filtered), kolom JSON yang di-query, fungsi zona waktu database, dan unique pada kolom yang boleh NULL (SQL Server hanya mengizinkan satu NULL).
- Master data yang sudah dipakai transaksi tidak dihapus permanen; cukup `is_active = false`.

**core**

| Tabel | Kolom utama | Kunci / index |
|---|---|---|
| `core_tenant` | name, logo, primary_color, contact, receipt_footer, payment_methods (mis. `CASH,QRIS`), master_version, next_device_no, resend_since | — |
| `core_user` | (AbstractUser) + role (OWNER/MANAGER/CASHIER), display_name, pin_hash, can_discount; M2M `outlets` | username unik |
| `core_outlet` | code, name, type (OUTLET/MOBILE), timezone, tax_enabled, tax_rate_bp, tax_inclusive, rounding_unit (0/100/500/1000), void_needs_manager, qris_image (biner PNG/JPG ≤ 300 KB, ikut backup database), receipt_header, receipt_footer, is_active | unik (tenant, code) |
| `core_device` | outlet_id, number, name, activation_code, activation_expires_at, token_hash, activated_at, revoked_at, last_sync_at, pending_count, app_version | unik (tenant, number); index token_hash, activation_code |
| `core_auditlog` | at, actor_id, device_id, action, object_type, object_id, detail | index (tenant, at) |

**catalog**

| Tabel | Kolom utama | Kunci / index |
|---|---|---|
| `catalog_category` | name, sort, is_active | — |
| `catalog_product` | category_id, name, price, image, earns_stamp, is_active, sort; M2M `modifier_groups`; M2M `available_outlets` (kosong = semua outlet) | index (tenant, category_id) |
| `catalog_modifiergroup` | name, required, multi, sort | — |
| `catalog_modifieroption` | group_id, name, price_delta, sort, is_active | index group_id |

**sales** (ID dari HP)

| Tabel | Kolom utama | Kunci / index |
|---|---|---|
| `sales_shift` | outlet_id, device_id, staff_id, opened_at, opening_cash, business_date, closed_at, counted_cash, expected_cash, received_at | index (tenant, business_date) |
| `sales_cashmovement` | shift_id, staff_id, at, direction (IN/OUT), amount, note | index shift_id |
| `sales_sale` | outlet_id, device_id, shift_id, staff_id, receipt_no, created_at, received_at, business_date, local_hour, customer_label, member_id, member_ref, subtotal, discount_total, discount_reason, tax_total, rounding, total, tax_enabled, tax_rate_bp, tax_inclusive, rounding_unit, status (COMPLETED/VOIDED), voided_at, voided_by_id, void_approved_by_id, void_reason, stamps_earned, flags | index (tenant, business_date, outlet_id), shift_id, receipt_no, member_id |
| `sales_saleitem` | sale_id, product_id (tanpa FK), name, category_name, qty, unit_price, modifiers_total, discount, line_total, is_reward, earns_stamp, note | index sale_id |
| `sales_saleitemmodifier` | sale_item_id, option_id (tanpa FK), group_name, name, price_delta | index sale_item_id |
| `sales_payment` | sale_id, method (CASH/QRIS/TRANSFER/EWALLET), amount, tendered, change_amount, reference | index sale_id |

`product_id` & `option_id` sengaja tanpa foreign key. Detail transaksi adalah snapshot, jadi event dari HP tidak pernah gagal hanya karena referensi ke master data. Laporan memakai nama dari snapshot.

**loyalty**

| Tabel | Kolom utama | Kunci / index |
|---|---|---|
| `loyalty_member` | code, name, phone (E.164), stamp_balance, last_activity_at, consent_at, card_epoch, card_activated_at, is_blocked, anonymized_at, created_at | unik (tenant, code); unik (tenant, phone) |
| `loyalty_cardactivation` | member_id, token_hash, source (POS/DASHBOARD), created_at, expires_at, used_at, revoked_at, revoke_reason | index token_hash |
| `loyalty_stamprule` | version, effective_from, stamps_per_reward, daily_cap, expiry_months; M2M `reward_products` | unik (tenant, version) |
| `loyalty_stampledger` | member_id, at, business_date, kind, qty (+/−), sale_id, ref, reason, actor_id | unik (tenant, ref); index (member_id, business_date) |

- `kind`: EARN, REDEEM, REVERSE_EARN, REVERSE_REDEEM, ADJUST, EXPIRE.
- `ref` membuat ledger idempotent tanpa unique bersyarat: `"{kind}:{sale_id}"` untuk entri yang terkait penjualan, UUID acak untuk ADJUST/EXPIRE.
- Anonimisasi member: name → NULL, phone → `deleted:<id>` (tetap unik), isi `anonymized_at`.

Ditambah tabel bawaan Django: session, cache (`DatabaseCache`), auth/permission, dan migrasi.

## 5. Kontrak API Mobile (`/api/v1`)

**Aturan umum**
- Base URL `https://app.<domain>/api/v1`, JSON UTF-8. Semua endpoint kecuali `device/activate` butuh `Authorization: Bearer <token>`. Header `X-App-Version` wajib.
- Waktu dalam ISO-8601 UTC (`2026-11-19T03:15:00.123Z`); uang integer Rupiah; ID berupa string UUID.
- Format error: `{"error": "<kode>", "message": "<teks untuk manusia>"}`.

| HTTP | `error` | Arti |
|---|---|---|
| 400 | `invalid_request`, `invalid_code` | Body tidak valid / kode aktivasi salah, kedaluwarsa, atau sudah dipakai |
| 401 | `invalid_token`, `device_revoked` | Token salah / device dicabut |
| 409 | `insufficient_stamps`, `reward_not_allowed`, `member_blocked` | Tukar reward ditolak |
| 429 | `rate_limited` | Terlalu sering |

### POST /device/activate
Tanpa token; maks 10 percobaan/jam per IP.
```json
{"code": "K7F3X9QA", "app_version": "1.0.0"}
```
Response 200:
```json
{"token": "<43 karakter>", "device": {"id": "…", "number": 3},
 "outlet": {"id": "…", "code": "GRB01", "name": "Gerobak Sudirman"}}
```

### GET /sync/master?version=41
Jika tidak berubah: `{"changed": false, "version": 41, "server_time": "…"}`. Jika berubah:
```json
{"changed": true, "version": 42, "server_time": "…", "snapshot": {
  "min_app_version": "1.0.0",
  "card_base_url": "https://member.contoh.id",
  "resend_since": null,
  "business": {"name": "Kopi Contoh", "logo_url": null, "receipt_footer": "IG @kopicontoh"},
  "outlet": {"id": "…", "code": "GRB01", "name": "Gerobak Sudirman", "type": "MOBILE",
             "timezone": "Asia/Jakarta", "tax_enabled": false, "tax_rate_bp": 1000,
             "tax_inclusive": true, "rounding_unit": 0, "void_needs_manager": false,
             "qris_image": "<base64 PNG/JPG atau null>", "receipt_header": "…", "receipt_footer": "…"},
  "device": {"id": "…", "number": 3},
  "staff": [{"id": "…", "name": "Andi", "role": "CASHIER",
             "pin_hash": "pbkdf2_sha256$20000$…", "can_discount": false}],
  "categories": [{"id": "…", "name": "Kopi", "sort": 1}],
  "products": [{"id": "…", "category_id": "…", "name": "Es Kopi Susu", "price": 18000,
                "earns_stamp": true, "image_url": null, "modifier_group_ids": ["…"], "sort": 1}],
  "modifier_groups": [{"id": "…", "name": "Ukuran", "required": true, "multi": false, "sort": 1,
                       "options": [{"id": "…", "name": "Regular", "price_delta": 0},
                                   {"id": "…", "name": "Large", "price_delta": 5000}]}],
  "payment_methods": ["CASH", "QRIS", "TRANSFER", "EWALLET"],
  "stamp_rule": {"version": 3, "stamps_per_reward": 10, "daily_cap": 10,
                 "reward_product_ids": ["…"]}
}}
```
- Isinya hanya produk aktif yang tersedia di outlet itu, dan staf aktif yang punya akses ke outlet itu (owner selalu ikut).
- `payment_methods` = metode aktif dari profil usaha (PRD M-06). `outlet.qris_image` ikut snapshot sebagai base64 supaya QRIS tetap tampil saat offline; jika snapshot membesar, pindah ke URL + cache di HP.
- Server membaca `master_version` **sebelum** mengambil data. Jika ada perubahan di antara keduanya, HP mendapat data yang lebih baru dengan label versi lama, lalu mengunduh ulang di siklus berikutnya. Jadi tidak ada perubahan yang terlewat.
- `resend_since` diisi setelah restore backup (§10.4).

### POST /sync/push
Maks 100 event, urut sesuai outbox:
```json
{"pending_after": 0, "events": [{"id": "<uuid event>", "type": "sale.completed", "data": {}}]}
```
Response:
```json
{"results": [{"id": "…", "status": "ok"},
             {"id": "…", "status": "duplicate"},
             {"id": "…", "status": "retry", "reason": "shift_unknown"},
             {"id": "…", "status": "rejected", "reason": "invalid_payload: items[0].qty"}],
 "server_time": "…", "master_version": 42}
```

| Status | Arti | Tindakan HP |
|---|---|---|
| `ok` | Diproses | Tandai terkirim |
| `duplicate` | Sudah pernah diproses | Tandai terkirim |
| `retry` | Ketergantungan belum ada (mis. shift belum diterima) | Biarkan antre, kirim lagi di siklus berikutnya |
| `rejected` | Data rusak (bug) | Tandai ditolak, tampilkan di "Masalah sync" |

Server memproses event berurutan, masing-masing dalam savepoint sendiri, lalu memperbarui `last_sync_at`, `pending_count`, dan `app_version` device.

**Jenis event**

| `type` | Isi `data` | Kunci idempotensi | `retry` jika |
|---|---|---|---|
| `shift.opened` | shift_id, staff_id, opened_at, opening_cash | shift_id | — |
| `cash.moved` | id, shift_id, staff_id, at, direction, amount, note | id | shift belum ada |
| `sale.completed` | lihat contoh di bawah | sale_id | shift belum ada |
| `sale.voided` | sale_id, staff_id, approved_by_id, voided_at, reason | status sale sudah VOIDED | sale belum ada |
| `shift.closed` | shift_id, staff_id, closed_at, counted_cash | closed_at sudah terisi | shift belum ada |
| `member.registered` | phone, name, registered_at, activation_token | hash token | — |
| `card.issued` | member_code, issued_at, activation_token | hash token | — |

Contoh `sale.completed`:
```json
{
  "sale_id": "…", "shift_id": "…", "staff_id": "…",
  "receipt_no": "GRB01-3-261119-0042", "created_at": "2026-11-19T03:15:00.123Z",
  "customer_label": "Budi",
  "member": {"code": "K7F3X9QA"},
  "pricing": {"tax_enabled": false, "tax_rate_bp": 1000, "tax_inclusive": true, "rounding_unit": 0},
  "items": [{
    "id": "…", "product_id": "…", "name": "Es Kopi Susu", "category_name": "Kopi",
    "qty": 2, "unit_price": 18000, "discount": 0, "earns_stamp": true, "is_reward": false,
    "note": "", "modifiers": [{"option_id": "…", "group_name": "Ukuran",
                               "name": "Large", "price_delta": 5000}]
  }],
  "order_discount": 0, "discount_reason": null,
  "subtotal": 46000, "tax_total": 0, "rounding": 0, "total": 46000,
  "payments": [{"id": "…", "method": "CASH", "amount": 46000,
                "tendered": 50000, "change": 4000, "reference": null}]
}
```
- `member` berisi `{"code": …}` (QR di-scan / hasil lookup), `{"phone": "+62…"}` (diketik atau member baru), atau `null`.
- `pricing` adalah setting pajak & pembulatan yang dipakai HP saat transaksi. Dengan begitu server tetap bisa memeriksa hitungan walaupun setting outlet sudah berubah sejak itu.

**Tanda (flag) pada penjualan.** Penjualan tetap diterima, tandanya muncul di dashboard:

| Flag | Kapan |
|---|---|
| `total_mismatch` | Hitung ulang server (dengan `pricing` dari event) ≠ total dari HP |
| `reward_unverified` | Ada item reward tanpa REDEEM yang cocok |
| `member_unknown` | Kode member tidak ditemukan; penjualan disimpan tanpa member |
| `duplicate_receipt_no` | Nomor struk sudah dipakai penjualan lain |
| `clock_ahead` | `created_at` lebih dari 5 menit di depan jam server |

### GET /members/lookup?code=… atau ?phone=…
Maks 60/jam per device.
```json
{"found": true, "member": {"code": "K7F3X9QA", "name": "Budi", "stamp_balance": 12,
                           "rewards_available": 1, "card_active": true}}
```
Atau `{"found": false}`.

### POST /loyalty/redeem
```json
{"sale_id": "…", "member_code": "K7F3X9QA", "product_id": "…"}
```
- 200 `{"ok": true, "stamps_used": 10, "stamp_balance": 2}`. Panggilan ulang dengan `sale_id` yang sama → jawaban sama (idempotent).
- 409 `insufficient_stamps` (disertai `stamp_balance`), `reward_not_allowed`, atau `member_blocked`.
- Maksimal 1 reward per transaksi di MVP.

## 6. Aplikasi Kasir (Flutter)

### 6.1 Paket

| Kebutuhan | Paket |
|---|---|
| Database lokal | `sqflite` |
| HTTP | `http` |
| Simpan token device | `flutter_secure_storage` |
| UUIDv7 | `uuid` |
| Deteksi perubahan jaringan | `connectivity_plus` |
| Sync di background | `workmanager` |
| Scan QR | `mobile_scanner` (mulai M3) |
| Tampilkan QR di layar | `qr_flutter` (mulai M3) |
| Bagikan struk | `share_plus` |
| PBKDF2 untuk PIN | `crypto` (HMAC-SHA256 resmi dart-lang) + loop PBKDF2 ±15 baris, dijalankan di `Isolate.run` |
| Printer ESC/POS Bluetooth | Tanpa paket: MethodChannel Kotlin (Bluetooth Classic SPP) + perintah ESC/POS buatan sendiri (§13). Printer yang sudah diuji dicatat di `docs/printer.md` |
| Test di PC | `sqflite_common_ffi` (SQLite in-memory), `package:http/testing.dart` |

State memakai `ChangeNotifier` + `ListenableBuilder` bawaan Flutter, tanpa library state management. URL server diset saat build (`--dart-define=API_BASE=…`).

### 6.2 Skema SQLite

| Tabel | Isi |
|---|---|
| `meta` (key, value) | last_sync_at, clock_skew_ms, revoked, last_error, status kunci PIN (pin_fails, pin_locked_until), setting printer (printer_address, printer_name, paper_width, auto_print), resend_applied (M5). Token device ada di `flutter_secure_storage`; nomor device & outlet dibaca dari snapshot |
| `master_snapshot` (version, json) | 1 baris: snapshot master utuh, dimuat ke memori saat app dibuka. `version` adalah versi master yang dikirim ke `GET /sync/master` |
| `shifts` | id, staff_id, opened_at, opening_cash, closed_at, counted_cash (`business_date` dihitung server) |
| `cash_movements` | id, shift_id, at, direction, amount, note |
| `sales` | id, shift_id, receipt_no, created_at, total, status, payload (JSON `sale.completed`) |
| `outbox` | seq (autoincrement), event_id (unik), type, payload, created_at, status (PENDING/SENT/REJECTED), attempts, last_error |
| `receipt_seq` | date (PK), last |

- Menyelesaikan penjualan = **satu transaksi SQLite**: naikkan `receipt_seq`, insert `sales`, insert `outbox`. Layar "Berhasil" dan cetak struk baru jalan setelah commit.
- Saat app dibuka, baris `sales` dan `outbox` berstatus SENT yang lebih tua dari 7 hari dihapus.

### 6.3 Mesin sync
```
sync():
  if sedang_sync: return
  sedang_sync = true
  try:
    loop:
      batch = outbox PENDING urut seq, maks 100
      if batch kosong: break
      res = POST /sync/push
      ok/duplicate → SENT · rejected → REJECTED (+alasan) · retry → attempts += 1
      if semua hasil batch = retry: break        # tidak ada kemajuan, tunggu siklus berikutnya
    res = GET /sync/master?version=meta.master_version
    if res.changed: ganti master_snapshot (1 transaksi), muat ulang ke memori
    simpan last_sync_at & selisih jam (server_time − jam HP)
  catch error jaringan: diam, coba lagi di pemicu berikutnya
  finally: sedang_sync = false
```
- **Pemicu**: setelah transaksi selesai, perubahan jaringan (`connectivity_plus`), timer 5 menit selama app terbuka, `workmanager` ±15 menit di background, dan tombol "Sync sekarang".
- Sync foreground dan background kadang jalan bersamaan dan mengirim event yang sama. Ini aman karena server idempotent, jadi tidak perlu kunci antar-isolate.
- (Mulai M5) Jika `snapshot.resend_since` berbeda dari `meta.resend_applied`, outbox SENT sejak waktu itu dikembalikan ke PENDING, lalu `resend_applied` diperbarui (pemulihan setelah restore, §10.4).
- Jika versi app < `min_app_version`: sync & tutup shift tetap boleh, tapi buka shift baru diblokir.

### 6.4 Login staf, struk, member
- Login: pilih nama staf → PIN 6 digit → dicocokkan dengan `pin_hash` dari snapshot. Salah 5× → terkunci 5 menit.
- Struk 58 mm = 32 karakter/baris, 80 mm = 48. Untuk member baru, struk memuat QR aktivasi `{card_base_url}/a/{token}`.
- Token aktivasi kartu: 32 byte dari `Random.secure()`, base64url. Dibuat di HP supaya bisa offline; server hanya menyimpan hash-nya.
- Terbit ulang QR (PRD K-25): lookup online → kasir cocokkan nama → buat token baru → event `card.issued` → sync langsung.

## 7. Algoritma Inti

### 7.1 Total transaksi (identik di Dart & Python, hanya integer)
```
half_up(a, b) = (2a + b) // 2b                          # a ≥ 0, b > 0
line_gross    = (unit_price + Σ price_delta) × qty     # item reward: unit_price = 0
line_total    = line_gross − discount_item
subtotal      = Σ line_total
net           = subtotal − order_discount
tax           = 0                                        jika pajak nonaktif
              = half_up(net × rate_bp, 10000)            jika eksklusif
              = half_up(net × rate_bp, 10000 + rate_bp)  jika inklusif (sudah termasuk di net)
sebelum_bulat = net + tax (eksklusif) atau net (inklusif/nonaktif)
total         = (sebelum_bulat // unit) × unit           jika unit > 0; selalu ke bawah, tidak merugikan pembeli
rounding      = total − sebelum_bulat                    # ≤ 0
```
Diskon persen diubah jadi nominal di HP: `basis × pct_bp // 10000`. `discount_total` di tabel = Σ diskon item + diskon transaksi.

Contoh berikut juga menjadi isi awal `shared/totals_cases.json`:

| # | Input | Subtotal | Pajak | Pembulatan | Total |
|---|---|---|---|---|---|
| 1 | 2× Es Kopi Susu 18.000 + Large 5.000; tanpa pajak | 46.000 | 0 | 0 | 46.000 |
| 2 | Kasus 1 + pajak eksklusif 10% | 46.000 | 4.600 | 0 | 50.600 |
| 3 | Americano 15.000, diskon item 1.450; pajak eksklusif 11%; bulat Rp100 | 13.550 | 1.491 (1.490,5 dibulatkan naik) | −41 | 15.000 |
| 4 | Es Kopi Susu 18.000; pajak inklusif 10% | 18.000 | 1.636 (sudah termasuk) | 0 | 18.000 |
| 5 | Reward Es Kopi Susu + Large, ditambah 1 Es Kopi Susu Regular berbayar | 23.000 | 0 | 0 | 23.000 |

### 7.2 Nomor struk
Format `{KODE_OUTLET}-{NO_DEVICE}-{YYMMDD}-{URUT 4 digit}`. YYMMDD = tanggal lokal outlet; URUT diambil dari `receipt_seq[tanggal]` dalam transaksi yang sama dengan penjualan. Jika jam HP mundur ke tanggal yang sudah lewat, urutan melanjutkan angka terakhir tanggal itu, jadi tidak ada nomor ganda. Di server `receipt_no` hanya di-index (tidak unik); nomor ganda diberi flag.

### 7.3 Stamp
- **EARN** (saat memproses `sale.completed` yang punya member):
  1. Kunci baris member: `UPDATE loyalty_member SET last_activity_at = now WHERE id = …`. Kuncinya bertahan sampai commit, dan cara ini portabel tanpa `select_for_update`.
  2. `eligible` = Σ qty item yang `earns_stamp` dan bukan reward (nilai snapshot dari event).
  3. Aturan = StampRule dengan `effective_from ≤ created_at` yang paling baru.
  4. `earn = min(eligible, max(0, daily_cap − EARN member itu di business_date yang sama))`.
  5. Jika `earn > 0`: insert ledger (`ref = EARN:{sale_id}`), `stamp_balance += earn`, `sale.stamps_earned = earn`.
- **REDEEM** (online): kunci member → ambil aturan terbaru → cek produk termasuk reward, saldo ≥ `stamps_per_reward`, dan member tidak diblokir → insert ledger (`ref = REDEEM:{sale_id}`) → kurangi saldo. Jika `ref` sudah ada → kembalikan hasil sebelumnya.
- **VOID**: insert REVERSE_EARN dan/atau REVERSE_REDEEM (`ref` per sale), lalu perbarui saldo. Saldo negatif ditandai di dashboard.
- **EXPIRE** (job harian, jika `expiry_months` diisi): member dengan saldo > 0 yang `last_activity_at`-nya lebih lama dari N bulan → ledger EXPIRE sebesar −saldo.
- **Redeem yatim** (job harian): REDEEM yang penjualannya belum diterima setelah 7 hari → REVERSE_REDEEM otomatis + audit log. Biasanya terjadi karena app mati tepat setelah redeem.

### 7.4 Member & aktivasi kartu
- Normalisasi no HP: buang spasi/tanda baca; `08…` → `+628…`; `628…` → `+628…`; valid jika 10–15 digit.
- Kode member: 8 karakter Crockford base32 acak (tanpa I, L, O, U), dibuat server. QR di kartu berisi `KP1:<kode>` supaya HP kasir bisa membedakannya dari QR lain.
- `member.registered`:
  - Nomor baru → buat member + simpan aktivasi.
  - Nomor sudah terdaftar → isi nama jika masih kosong. Jika member **belum pernah** mengaktifkan kartu, aktivasi disimpan seperti biasa. Jika sudah pernah, aktivasi disimpan dalam keadaan dicabut (`revoke_reason = needs_reissue`), dan halamannya menyuruh pelanggan minta terbit ulang ke kasir. Ini mencegah orang lain mengambil alih kartu hanya dengan menyebut nomor HP.
- `card.issued`: cabut semua aktivasi yang belum dipakai, `card_epoch += 1` (sesi lama di browser lain otomatis keluar), lalu simpan aktivasi baru.
- Halaman `/a/<token>`:
  - Token tidak ditemukan → "Kartu sedang diproses, buka lagi link ini sebentar lagi" (HP kasir mungkin belum sync).
  - Kedaluwarsa, sudah dipakai, atau dicabut → pesan sesuai + arahan minta QR baru.
  - Valid → persetujuan S&K → isi `used_at` dan `card_activated_at` → sesi 1 tahun → halaman kartu.
- Di setiap request kartu: jika `session.card_epoch ≠ member.card_epoch` atau member sudah dianonimkan → sesi dihapus.

### 7.5 Shift, tanggal bisnis, kas
- `business_date` shift = tanggal lokal (zona waktu outlet) saat shift dibuka. Penjualan mengikuti `business_date` shift-nya; `local_hour` = jam lokal saat transaksi. Keduanya dihitung server dengan `zoneinfo` saat event diterima, bukan dengan fungsi SQL.
- Kas seharusnya = `opening_cash + Σ pembayaran CASH (penjualan COMPLETED) + Σ kas IN − Σ kas OUT`; selisih = `counted_cash − kas seharusnya`. Dihitung di HP untuk rekap, lalu dihitung ulang server saat `shift.closed`.
- Shift yang tidak pernah ditutup (mis. app di-install ulang) bisa ditutup paksa owner dari dashboard, tercatat di audit log.

## 8. Web

### 8.1 Dashboard (`app.<domain>`)
Django templates + HTMX + satu file CSS ringan tanpa proses build (mis. Pico.css) + Chart.js untuk grafik.

| Halaman | Isi |
|---|---|
| `/` | Ringkasan hari ini + status device |
| `/laporan/…` | Penjualan, produk & modifier, kategori, metode bayar, staf, shift, void & diskon; ekspor `.xlsx` |
| `/outlet`, `/device`, `/menu`, `/staf`, `/stamp`, `/member`, `/audit`, `/usaha` | Kelola data master, member, audit log, profil usaha |

- Laporan dihitung langsung dari tabel penjualan (GROUP BY `business_date`, outlet, staf, produk). Tabel ringkasan baru ditambah kalau laporan mulai lambat.
- Ekspor pakai `.xlsx` (`openpyxl`), bukan CSV. Excel dengan setting regional Indonesia memakai `;` sebagai pemisah, jadi CSV berkoma akan terbuka berantakan.
- Halaman device: tombol "Tambah device" menampilkan kode aktivasi (teks + QR) yang berlaku 15 menit.

### 8.2 Kartu member (`member.<domain>`)

| Halaman | Isi |
|---|---|
| `/a/<token>` | Aktivasi + persetujuan S&K |
| `/` | Kartu: QR member (SVG dibuat server dengan `segno`), grid stamp, reward |
| `/riwayat` | Riwayat stamp |
| `/privasi`, `/hapus-akun` | Kebijakan privasi; hapus akun = anonimisasi + logout |
| `/manifest.webmanifest`, `/sw.js` | PWA: service worker network-first untuk halaman kartu, sehingga kartu terakhir tetap tampil saat offline |

Middleware memilih `urlconf` berdasarkan host: `member.*` → URL kartu, selain itu → dashboard & API.

## 9. Keamanan
- HTTPS di semua host (Caddy, HSTS). Cookie `Secure`, `HttpOnly`, `SameSite=Lax`.
- CSRF Django untuk semua form. API memakai Bearer tanpa cookie, jadi tidak perlu CSRF.
- Token device & token aktivasi kartu: 32 byte acak; server hanya menyimpan SHA-256-nya. Di HP, token device disimpan di `flutter_secure_storage`.
- Kode aktivasi device: 8 karakter, berlaku 15 menit, sekali pakai, rate-limit per IP.
- Otorisasi: semua query lewat manager tenant; izin per role dicek di setiap view; device hanya boleh mengirim data untuk outlet-nya sendiri (selain itu → `rejected: forbidden`).
- SQL Server: login khusus aplikasi (bukan `sa`); port 1433 hanya di jaringan Docker, tidak dibuka ke internet.
- Rahasia disimpan di `.env` (tidak di-commit); repo hanya berisi `.env.example`.
- Lookup member dibatasi 60/jam per device, supaya token device curian tidak bisa dipakai menyedot data member.

## 10. Deploy & Operasional

### 10.1 Docker Compose (produksi)

| Service | Image | Catatan |
|---|---|---|
| `db` | `mcr.microsoft.com/mssql/server:2025-latest` | `MSSQL_PID=Express`, `ACCEPT_EULA=Y`, volume data & backup, tidak di-expose |
| `web` | build dari `backend/` (`python:3.14-slim` + ODBC Driver 18) | Gunicorn 3 worker; `migrate` & `collectstatic` saat deploy |
| `caddy` | `caddy:2` | HTTPS otomatis untuk `app.` & `member.`; menyajikan `/static` & `/media` dari volume |
| `cloudflared` (opsional) | `cloudflare/cloudflared` | Hanya jika di-host di server sendiri lewat Cloudflare Tunnel (PRD Q2) |

VPS harus **x86_64** (SQL Server untuk Linux tidak tersedia di ARM), RAM ≥ 4 GB, SSD ≥ 40 GB.

Caddyfile:
```
app.contoh.id, member.contoh.id {
    encode gzip
    handle_path /static/* {
        root * /srv/static
        file_server
    }
    handle_path /media/* {
        root * /srv/media
        file_server
    }
    reverse_proxy web:8000
}
```

### 10.2 Setup database (sekali)
1. Buat database `kaffepos` dan login aplikasi yang hanya menjadi owner database itu.
2. `ALTER DATABASE kaffepos SET READ_COMMITTED_SNAPSHOT ON;`
3. `python manage.py migrate`, `python manage.py createcachetable`, lalu `python manage.py setup_tenant` (membuat usaha + akun owner).

### 10.3 Cron di host

| Jadwal | Tugas |
|---|---|
| Harian 02:00 | `backup.sh`: `BACKUP DATABASE` lewat `sqlcmd` → gzip (Express tidak mendukung backup compression) → salin ke penyimpanan lain (mis. `rclone` ke Google Drive) → hapus salinan lokal > 7 hari dan remote > 30 hari |
| Harian 03:00 | `manage.py daily_jobs`: stamp hangus, redeem yatim, catat ukuran database ke log |
| Mingguan | `manage.py clearsessions` |

### 10.4 Restore
1. `RESTORE DATABASE … WITH REPLACE` dari backup terakhir.
2. Lewat Django Admin, isi `resend_since` di data usaha dengan waktu backup. Versi master naik, lalu setiap HP mengirim ulang outbox sejak waktu itu (data 7 hari masih ada di HP). Pengiriman ulang aman karena idempotent.
3. Setelah semua device sync, kosongkan lagi `resend_since`.

### 10.5 Development di Windows
- SQL Server 2025 Express/Developer (gratis), dipasang langsung atau pakai image yang sama lewat Docker Desktop.
- ODBC Driver 18 for SQL Server, Python 3.14, Flutter SDK + Android Studio.
- Uji app di HP Android nyata, karena printer Bluetooth tidak bisa diuji di emulator.

## 11. Strategi Testing (sesuai risiko)

| Area | Test |
|---|---|
| Rumus total | `shared/totals_cases.json` dijalankan di pytest dan `dart test`; hasilnya harus identik |
| Sync server | Push batch yang sama 2× → tidak ada duplikat; event tidak berurutan → `retry` lalu `ok`; total salah → diterima + flag |
| Isolasi tenant | Fixture 2 tenant; semua URL dashboard & endpoint API dicek tidak pernah mengembalikan data tenant lain |
| Stamp | Earn + batas harian; redeem idempotent; saldo kurang → 409; void membalik; expire |
| Versi master | Ubah produk/staf/relasi M2M → versi naik; snapshot hanya berisi data outlet itu |
| App | Outbox & `receipt_seq` (sqflite in-memory di desktop via `sqflite_common_ffi`); mesin sync dengan API palsu |
| Lapangan (manual) | Mode pesawat 200 transaksi → online; app dimatikan saat bayar; printer dicabut; 2 HP menukar reward yang sama |

Test backend dijalankan terhadap SQL Server (engine yang sama dengan produksi) supaya keanehan `mssql-django` ketahuan sejak awal.

## 12. Trade-off & Kapan Ditinjau Ulang

| Keputusan sekarang | Batasnya | Ganti ke |
|---|---|---|
| Snapshot master utuh | Ribuan produk / snapshot > ±1 MB | Sync per baris dengan versi per baris |
| Laporan langsung dari tabel transaksi | Laporan > 2–3 detik | Tabel ringkasan harian yang diisi job |
| Satu VPS, satu instance database | Butuh uptime tinggi | Database managed + 2 instance app |
| SQL Server Express | 50 GB, 4 core, buffer ±1,4 GB | PostgreSQL (kode portabel) atau edisi berbayar |
| Cron tanpa antrean job | Job berat / notifikasi massal | Antrean job (mis. RQ/Celery + Redis) |
| Tidak ada cache member di HP | Perlu lihat saldo saat offline | Cache member terbatas (kode, nama, saldo) |
| Sesi kartu terikat browser | Pelanggan sering ganti HP | Login no HP + PIN (PRD C-08) |
| Satu tenant | Jadi SaaS | Modul SaaS (PRD A-05) + Row-Level Security + routing per tenant |

## 13. Spike & Keputusan Terbuka

| Item | Kapan | Kriteria |
|---|---|---|
| Paket printer Bluetooth | M2 (Task 12) | Keputusan: tanpa plugin. MethodChannel Kotlin dengan socket SPP (secure, jatuh ke insecure untuk printer murah) + ESC/POS buatan sendiri; izin Android 12+ `BLUETOOTH_CONNECT`. Spike = uji teks, potong kertas, QR `GS ( k`, dan sambung ulang di 2–3 printer 58/80 mm; hasilnya di `docs/printer.md`. Printer yang gagal QR → fallback QR raster di M3 |
| Hosting (PRD Q2) | Sebelum deploy staging di M0 | VPS vs server sendiri + Cloudflare Tunnel; compose sama, bedanya hanya service `cloudflared` |
| Domain (PRD Q5) | Sebelum staging | Butuh 2 subdomain: `app.` dan `member.` |
| Foto produk | M1 | Jika dipakai, HP perlu cache gambar (tambah `cached_network_image`) |
