# M4 Laporan — Desain

Tanggal: 26 November 2026 · Status: disetujui per bagian di chat, menunggu review file ini.
Sumber kebutuhan: PRD §8.1 (A-03), §8.3 (K-05, K-09), §8.4 (W-01, W-02, W-05); DESAIN-TEKNIS §7.5, §8.1, §12.

## 1. Tujuan

Owner dan manager bisa melihat hasil penjualan dari dashboard web, di HP maupun laptop, tanpa membuka database.
Semua perubahan penting tercatat di audit log.

Kriteria keberhasilan:
- Beranda menampilkan ringkasan hari ini dan status sync tiap HP.
- Laporan dengan filter tanggal/outlet/staf, dan file Excel yang angkanya sama persis dengan halaman.
- Manager hanya melihat outlet yang ditugaskan.
- Audit log mencatat perubahan master data, device, void, dan diskon (termasuk siapa yang menyetujui).

## 2. Di luar cakupan

| Tidak dibuat | Alasan |
|---|---|
| Grafik interaktif (Chart.js) | Batang CSS cukup; tanpa JavaScript |
| Tabel ringkasan harian | Laporan dihitung langsung dari tabel penjualan sampai lambat > 2–3 detik (DESAIN-TEKNIS §12) |
| Tutup paksa shift dari dashboard | Cukup peringatan dulu; ditambah jika saat pilot sering terjadi |
| Laporan member & stamp, koreksi stamp di audit log | Ikut M3 |
| Audit login/logout | Tidak diminta PRD |

## 3. Halaman

### 3.1 Menu
`Beranda · Laporan · Kelola ▾ · Keluar`. Kelola (dropdown) berisi Usaha, Outlet, Kategori, Produk, Modifier, Opsi, Staf, Device, Audit log, dan hanya tampil untuk owner.
Warna dashboard memakai tema Pico berwarna biru (selaras app kasir), cukup ganti file CSS Pico.

### 3.2 Beranda `/` (owner & manager)
- Kartu hari ini: omzet, transaksi, item terjual, rata-rata per transaksi.
- Per outlet (omzet, transaksi), per metode bayar, penjualan per jam (`<progress>` atau batang CSS), 5 produk terlaris.
- Status device: nama, outlet, sync terakhir, data menunggu, versi app.
- Peringatan kuning: device aktif belum sync > 24 jam; shift terbuka > 24 jam.
- Keterangan: "Angka mencakup data sampai sync terakhir tiap HP."

### 3.3 Laporan `/laporan/…` (owner & manager)
Satu form filter (GET) dipakai semua tab: `dari`, `sampai` (input date), `outlet`, `staf`; tombol cepat Hari ini, Kemarin, 7 hari, Bulan ini. Default: hari ini.

| Tab | URL | Isi |
|---|---|---|
| Penjualan | `/laporan/` | Kartu (omzet, transaksi, diskon, void), per hari, per outlet, per metode bayar, per staf, per jam |
| Produk | `/laporan/produk/` | Per produk (qty, omzet), per kategori, per modifier (qty, tambahan harga) |
| Shift | `/laporan/shift/` | Outlet, staf, buka, tutup, modal, kas seharusnya, kas fisik, selisih; tanda shift terbuka > 24 jam |
| Void & diskon | `/laporan/void-diskon/` | Void: no struk, waktu, nilai, alasan, pelaku, penyetuju. Diskon: no struk, nilai, alasan, kasir, penyetuju |

Tombol "Unduh Excel" di setiap tab → `/laporan/excel/?<filter yang sama>`.

### 3.4 Audit log `/audit/` (owner)
Tabel baca saja: waktu (ditampilkan dalam WIB, karena usaha belum punya zona waktu sendiri), pelaku, aksi, objek, rincian. Filter tanggal & jenis aksi, 50 baris per halaman. Tidak ada aksi ubah/hapus.

### 3.5 Tampilan
HP: kartu satu kolom, tabel di dalam wadah yang bisa digeser (`overflow-auto`). Layar lebar: kartu berjajar (`grid`), tabel penuh. Tetap Django templates + Pico, tanpa build step.

## 4. Definisi angka

- **Penjualan selesai** = `Sale.status == COMPLETED`. Void tidak masuk angka mana pun kecuali tab Void & diskon.
- **Omzet** = Σ `Sale.total` (sesudah diskon, termasuk pajak & pembulatan).
- **Transaksi** = jumlah penjualan selesai. **Item terjual** = Σ `SaleItem.qty`. **Rata-rata** = omzet ÷ transaksi (dibulatkan ke rupiah; 0 jika tidak ada transaksi).
- **Tanggal** = `business_date` (tanggal lokal saat shift dibuka). **Per jam** = `local_hour`.
- **Hari ini** = untuk tiap outlet, tanggal hari ini di zona waktu outlet itu.
- **Per metode bayar** = Σ `Payment.amount` dari penjualan selesai.
- **Per modifier** = qty Σ `SaleItem.qty`, nilai Σ `price_delta × qty`, dikelompokkan (nama grup, nama opsi).
- **Selisih shift** = `counted_cash − expected_cash`; kosong jika shift belum ditutup.
- Invarian (dites): Σ per outlet = Σ per staf = Σ per hari = omzet; Σ per metode bayar = omzet (satu pembayaran per penjualan di M2).

## 5. Akses

| Peran | Beranda & Laporan | Kelola & Audit log |
|---|---|---|
| Owner | Semua outlet | Ya |
| Manager | Outlet di `User.outlets` | Tidak (403) |
| Kasir | Tidak bisa login (sudah ada) | Tidak |

- Satu fungsi `allowed_outlets(user)` menjadi satu-satunya sumber pembatasan; dipakai query laporan, pilihan filter, status device.
- Parameter `outlet` di luar `allowed_outlets` → 404. Manager tanpa outlet → halaman berisi pesan "Belum ada outlet yang ditugaskan".
- Rentang tanggal maks 366 hari; `dari > sampai` atau format salah → pesan error di form, data tidak dihitung.

## 6. Komponen

| Unit | Tanggung jawab |
|---|---|
| `reports/queries.py` | Fungsi murni `Filter → dict/list` untuk semua angka (ringkasan, per hari/outlet/metode/staf/jam, produk, kategori, modifier, shift, void, diskon, status device). Dipakai halaman & Excel |
| `reports/filters.py` | Parsing & validasi filter dari query string (Django Form), termasuk `allowed_outlets` |
| `reports/excel.py` | Membuat workbook `.xlsx` (openpyxl) dari hasil `queries.py` |
| `reports/views.py`, templates | Beranda, 4 tab laporan, ekspor, audit log |
| `core.AuditLog` + `core/audit.py` | Model & fungsi `record(actor, action, obj, detail, device=None)` |

App Django baru `reports` (tanpa model). `Home` di `dashboard` diganti beranda baru.

## 7. Ekspor Excel

- `.xlsx` via `openpyxl` (dependensi baru, gratis; minta izin sebelum diunduh).
- Sheet: Ringkasan (filter + kartu), Harian, Outlet, Metode bayar, Staf, Per jam, Produk, Kategori, Modifier, Shift, Void & diskon.
- Angka disimpan sebagai angka (format ribuan), tanggal sebagai tanggal. Nama file `laporan-<dari>_<sampai>.xlsx`.

## 8. Audit log

Model `core.AuditLog` (tenant-scoped, sesuai DESAIN-TEKNIS §4): `at`, `actor` (FK User, null), `device` (FK Device, null), `action`, `object_type`, `object_id`, `detail` (teks ≤ 500). Index (tenant, at).

| Sumber | Aksi | Rincian |
|---|---|---|
| Dashboard: produk, kategori, modifier, opsi, outlet, staf, usaha | `create`, `update` | Field yang berubah, "lama → baru" (dari `form.changed_data`). PIN/password: "PIN diubah", tanpa nilai |
| Dashboard: device | `device_create`, `device_code`, `device_revoke` | Nama device, outlet |
| Sync `sale.voided` | `void` | No struk, nilai, alasan; actor = pelaku, penyetuju di rincian |
| Sync `sale.completed` dengan diskon > 0 | `discount` | No struk, nominal, alasan, penyetuju |

Dicatat eksplisit di view/handler (bukan signal), di transaksi database yang sama dengan perubahannya. Event sync yang dikirim ulang tidak membuat catatan ganda (dicatat hanya saat penjualan/void baru tersimpan).

## 9. Penyetuju diskon (perubahan app + API)

- App: saat PIN manager menyetujui diskon (item/transaksi), simpan ID manager di keranjang; event `sale.completed` mengirim `discount_approved_by_id` (null jika tidak perlu persetujuan).
- Server: kolom `Sale.discount_approved_by` (FK User, null) + field opsional di skema push. Event dari app versi lama tanpa field ini tetap diterima.
- Perlu pasang ulang app di HP.

## 10. Pengujian

Backend (pytest terhadap SQL Server):
- `queries`: data contoh 2 outlet beda zona waktu, penjualan selesai + void + diskon → invarian §4, void dikecualikan, "hari ini" per zona.
- Akses: manager 404 untuk outlet lain, 403 untuk Kelola/Audit; owner melihat semua; filter tidak valid → error form.
- Isolasi: URL baru ditambahkan ke `test_isolation.py`.
- Excel: dibuka ulang dengan openpyxl; total sheet = angka `queries`.
- Audit: ubah harga produk, cabut device, void lewat sync, diskon dengan penyetuju lewat sync → masing-masing satu catatan; push ulang tidak menggandakan.

App (flutter test): event penjualan berisi `discount_approved_by_id` setelah diskon disetujui manager.

Manual: dashboard di browser HP & laptop; satu transaksi diskon dari HP lalu cek audit log dan tab Void & diskon.
