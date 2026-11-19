# PRD — KaffePOS
**POS Custom untuk Kopi Keliling & Outlet + Loyalty Card Digital**

| | |
|---|---|
| Versi | 0.3 — draft untuk review |
| Tanggal | 19 November 2026 |
| Produk | App Kasir (Flutter, offline-first) · Web Dashboard · Web Loyalty Card |
| Stack | Flutter + SQLite · Python/Django + Django Ninja · Microsoft SQL Server 2025 Express |
| Desain teknis | [DESAIN-TEKNIS.md](DESAIN-TEKNIS.md) |

**Riwayat revisi**

| Versi | Perubahan |
|---|---|
| 0.1 | Draft awal: SaaS multi-tenant, login pelanggan OTP WhatsApp, PostgreSQL |
| 0.2 | Jadi aplikasi custom untuk satu usaha, struktur data tetap siap SaaS. Login kartu pelanggan pakai QR aktivasi dari kasir (tanpa OTP). Tidak ada layanan berbayar per pemakaian. Database SQL Server (sementara, kode dijaga portabel). Sync master data disederhanakan |
| 0.3 | Diselaraskan dengan desain teknis: SQL Server 2025 Express (database maks 50 GB), SQLite di HP via `sqflite`, path API `/api/v1`, Python 3.14 |

## 1. Ringkasan

KaffePOS adalah POS **custom** untuk satu usaha kopi yang **berjualan keliling** (gerobak/motor/sepeda) maupun di **outlet tetap**. Kasir tetap bisa berjualan tanpa internet; data tersinkron otomatis saat online. Pelanggan mengumpulkan **stamp digital** lewat web, tanpa install aplikasi dan tanpa OTP berbayar. Struktur datanya disiapkan supaya nanti bisa dikembangkan jadi SaaS tanpa bongkar ulang.

Tiga produk, satu backend:
1. **App Kasir** (Android): offline-first, auto-sync, printer thermal Bluetooth, scan QR member.
2. **Web Dashboard**: untuk owner/manager (menu, outlet, staf, laporan, loyalty).
3. **Web Loyalty Card**: kartu stamp + QR member untuk pelanggan, bisa dipasang di layar utama HP (PWA).

## 2. Masalah

- Kopi keliling sering berjualan di area sinyal lemah. POS yang wajib online membuat antrean macet atau penjualan tidak tercatat.
- Owner dengan beberapa gerobak sulit memantau penjualan per rider dan mencocokkan setoran kas, sehingga rawan selisih dan kebocoran.
- Kartu stamp kertas mudah hilang/dipalsukan, dan owner tidak punya data pelanggan setia.
- Kebanyakan POS dirancang untuk outlet tetap, bukan operasional keliling (shift per rider, satu HP per gerobak, sinyal putus-sambung).
- POS siap pakai umumnya berbayar bulanan per outlet/device, dan fitur loyalty sering jadi biaya tambahan. Aplikasi custom dengan biaya berjalan minimal lebih hemat untuk jangka panjang.

> Poin di atas masih hipotesis. Validasi dengan owner dan rider sebelum/selama pilot.

## 3. Tujuan

| # | Tujuan | Ukuran keberhasilan |
|---|---|---|
| G1 | Kasir bisa berjualan penuh tanpa internet | Semua alur transaksi inti jalan offline; 0 transaksi hilang/ganda setelah sync |
| G2 | Owner melihat penjualan semua gerobak/outlet hampir real-time | Transaksi muncul di dashboard ≤ 5 menit setelah HP online |
| G3 | Transaksi cepat di jalan | Median 1 transaksi (pilih menu → bayar → struk) ≤ 30 detik |
| G4 | Pelanggan kembali lewat stamp digital | ≥ 25% transaksi terhubung ke member, 3 bulan setelah go-live |
| G5 | Biaya berjalan minimal | Hanya VPS + domain; 0 biaya per transaksi/pesan dari layanan pihak ketiga di MVP (rincian di §10) |

## 4. Bukan Cakupan v1

| Tidak dibuat | Alasan |
|---|---|
| Fitur SaaS (registrasi tenant, paket & tagihan, panel super admin) | Dipakai satu usaha. Struktur datanya sudah disiapkan (§8.1), fiturnya menyusul jika dibutuhkan |
| Layanan berbayar per pemakaian (OTP SMS/WhatsApp, notifikasi WA, layanan email) | Menekan biaya. Kartu pelanggan diaktifkan lewat QR dari kasir |
| Pendaftaran member mandiri dari web | Tanpa OTP, no HP tidak bisa diverifikasi. Member didaftarkan di kasir (tatap muka) |
| App native untuk pelanggan | Web/PWA cukup untuk kartu stamp |
| Pesan online/delivery, integrasi GoFood/GrabFood | Inisiatif terpisah; v1 fokus penjualan langsung |
| Akuntansi penuh (jurnal, neraca, laporan pajak) | Cukup ekspor laporan |
| Inventori penuh (pembelian, supplier, gudang, HPP) | Cukup kontrol stok bawaan per shift (P1) |
| App kasir iOS | Rider mayoritas Android; Flutter memungkinkan iOS menyusul |
| Absensi & payroll | Di luar inti POS |

## 5. Pengguna & Peran

| Persona | Siapa | Butuh | Akses |
|---|---|---|---|
| Owner | Pemilik usaha kopi | Menu, outlet/gerobak, staf, laporan, aturan stamp, profil usaha | Web Dashboard + App Kasir |
| Manager | Kepala outlet / koordinator rider | Pantau outlet tertentu, approve void/diskon, cek setoran | Dashboard (outlet tertentu) + App Kasir |
| Kasir / Rider | Barista atau rider gerobak | Transaksi cepat, struk, buka/tutup shift, daftarkan member | App Kasir (PIN) |
| Pelanggan | Pembeli setia | Kumpulkan stamp, lihat progres & reward | Web Loyalty Card |

Developer memakai Django Admin hanya untuk perawatan sistem, bukan untuk operasional harian.

## 6. Cakupan & Fase

**P0** = wajib untuk MVP · **P1** = segera setelah pilot · **P2** = masa depan (desain sekarang jangan sampai menghalangi)

| Area | P0 (MVP) | P1 | P2 |
|---|---|---|---|
| Kesiapan SaaS | `tenant_id` di semua data usaha (1 tenant), filter tenant otomatis, test dengan 2 tenant | — | Registrasi tenant, paket & tagihan, panel super admin, routing per tenant, Row-Level Security |
| App Kasir | Transaksi offline, modifier, diskon manual, struk Bluetooth, shift & kas, void, daftar member + QR aktivasi kartu | Kontrol stok cup/bahan per shift, open bill, split payment, promo otomatis (happy hour, bundling), simpan lokasi GPS transaksi | App kasir iOS |
| Pembayaran | Tunai, QRIS statis (konfirmasi manual), transfer/e-wallet manual | QRIS dinamis via payment gateway (opsional, ada biaya per transaksi) | EDC/kartu |
| Sync | Auto-sync dua arah, idempotent, status sync selalu terlihat | Alert device tidak sync > 24 jam | — |
| Loyalty | Stamp digital, reward 1 item gratis, kartu web aktif lewat QR dari kasir (tanpa OTP) | Login kartu dengan no HP + PIN, klaim stamp via QR struk, bonus stamp (ulang tahun, double stamp) | Google/Apple Wallet, tier member, dompet kartu lintas brand (setelah SaaS) |
| Laporan | Dashboard harian, penjualan per produk/outlet/staf/metode bayar/jam, laporan shift, ekspor Excel | Laporan stok & selisih, posisi terakhir gerobak (peta OpenStreetMap) | Heatmap lokasi jualan, "gerobak terdekat" untuk pelanggan |

## 7. User Stories (prioritas tertinggi di atas)

**Kasir / Rider**
- Sebagai rider, saya ingin tetap bisa mencatat penjualan saat tidak ada sinyal agar antrean tidak tertahan.
- Sebagai rider, saya ingin memilih menu dan opsinya (ukuran, gula, es) dengan sedikit ketukan agar pelanggan tidak menunggu.
- Sebagai rider, saya ingin membuka shift dengan modal awal dan menutupnya dengan hitung kas agar setoran saya jelas.
- Sebagai kasir, saya ingin scan QR member pelanggan agar stamp otomatis masuk.
- Sebagai kasir, saya ingin mencetak struk ke printer Bluetooth atau mengirimnya via WhatsApp agar pelanggan punya bukti.
- Sebagai kasir, saya ingin membatalkan transaksi yang salah input (dengan alasan) agar laporan tetap benar.
- Sebagai rider, saya ingin melihat berapa data yang belum terkirim agar yakin semua penjualan sudah masuk.

**Owner / Manager**
- Sebagai owner, saya ingin melihat omzet per gerobak/outlet hari ini agar tahu mana yang laku tanpa menunggu malam.
- Sebagai owner, saya ingin membandingkan kas setoran dengan penjualan tunai tiap shift agar selisih langsung ketahuan.
- Sebagai owner, saya ingin mengatur menu beserta opsinya agar kasir input sesuai pesanan pelanggan.
- Sebagai owner, saya ingin mengatur aturan stamp (berapa stamp untuk 1 gratis, produk mana yang dapat stamp) agar sesuai margin saya.
- Sebagai owner, saya ingin tahu HP kasir mana yang lama belum sync agar data tidak hilang kalau HP rusak.

**Pelanggan**
- Sebagai pelanggan, saya ingin jadi member cukup dengan menyebut nama dan no HP ke kasir agar tidak repot.
- Sebagai pelanggan, saya ingin membuka kartu stamp di HP dengan sekali scan QR, tanpa install aplikasi atau menunggu kode OTP.
- Sebagai pelanggan, saya ingin melihat jumlah stamp dan berapa lagi menuju gratis agar termotivasi kembali.
- Sebagai pelanggan, saya ingin menunjukkan QR member dari HP agar kasir menambahkan stamp dengan cepat.
- Sebagai pelanggan yang didaftarkan kasir saat offline, saya ingin stamp saya tetap masuk setelah HP kasir online.
- Sebagai pelanggan yang ganti HP, saya ingin bisa membuka kartu saya lagi agar stamp tidak hilang.

## 8. Kebutuhan Fungsional

### 8.1 Akun & Kesiapan SaaS

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| A-01 | P0 | Satu usaha (tenant) dibuat saat instalasi; owner mengatur profil usaha (nama, logo, warna, kontak) dari dashboard | Nama/logo/warna dipakai di struk & web loyalty tanpa mengubah kode |
| A-02 | P0 | Siap SaaS: semua tabel data usaha punya `tenant_id`; semua query otomatis difilter per tenant; unique constraint per tenant (kode outlet, nomor device, no HP member) | Test otomatis dengan 2 tenant dummy: data tenant lain tidak pernah tampil di halaman/endpoint mana pun |
| A-03 | P0 | Peran: Owner, Manager (dibatasi outlet), Kasir | Kasir tidak bisa login dashboard; Manager hanya melihat outlet yang ditugaskan |
| A-04 | P0 | Login dashboard dengan username/email + password; owner bisa reset password staf; reset password owner lewat perintah admin di server (tanpa layanan email) | — |
| A-05 | P2 | Modul SaaS: registrasi tenant mandiri, trial, paket & batas device, tagihan, panel super admin, routing per tenant (subdomain/slug), Row-Level Security | Bisa ditambahkan tanpa mengubah struktur tabel yang sudah ada |

### 8.2 Master Data (Web Dashboard)

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| M-01 | P0 | Outlet/Gerobak: nama, kode, tipe (Outlet / Keliling), zona waktu (WIB/WITA/WIT), pajak (on/off, tarif, inklusif/eksklusif), pembulatan, gambar QRIS statis, header/footer struk | Kode unik |
| M-02 | P0 | Device: kode aktivasi sekali pakai (berlaku 15 menit), nomor device unik yang tidak pernah dipakai ulang, waktu sync terakhir & jumlah data pending (dilaporkan HP), cabut device | Device yang dicabut tidak bisa sync; kode kedaluwarsa ditolak |
| M-03 | P0 | Kategori & Produk: nama, kategori, harga, foto (opsional), aktif/nonaktif, ketersediaan per outlet, dapat stamp (ya/tidak) | Perubahan tampil di HP setelah sync berikutnya |
| M-04 | P0 | Grup modifier & opsi: wajib/opsional, pilih satu/banyak, harga tambahan (mis. Ukuran: Regular / Large +5.000; Gula: Normal/Less/No; Extra shot +5.000) | Grup wajib harus dipilih sebelum item masuk keranjang |
| M-05 | P0 | Staf: nama, peran, PIN 6 digit untuk app kasir, outlet yang boleh diakses, izin diskon | PIN tidak pernah tersimpan/tampil dalam teks asli; owner bisa reset PIN |
| M-06 | P0 | Metode pembayaran aktif: Tunai, QRIS statis, Transfer, E-wallet | — |
| M-07 | P1 | Harga berbeda per outlet | — |
| M-08 | P1 | Bahan terlacak & resep sederhana (produk/opsi → bahan + jumlah), mis. opsi Large memakai 1 Cup 22oz | — |

### 8.3 App Kasir (Flutter)

**Aktivasi & login**

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| K-01 | P0 | Aktivasi sekali (butuh internet): ketik/scan kode aktivasi → HP terikat ke outlet, unduh data awal | Setelah aktivasi, app bisa dipakai offline penuh |
| K-02 | P0 | Login staf dengan PIN (bisa offline); ganti staf cepat tanpa aktivasi ulang | PIN salah 5× → terkunci 5 menit |

**Shift & kas**

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| K-03 | P0 | Buka shift dengan modal awal; satu shift aktif per HP | Tidak bisa transaksi tanpa shift aktif |
| K-04 | P0 | Kas masuk/keluar selama shift (mis. beli es batu) + catatan | Muncul di rekap shift |
| K-05 | P0 | Tutup shift: input kas fisik → tampil kas seharusnya (modal + penjualan tunai + kas masuk − kas keluar) & selisih; cetak/bagikan rekap | Bisa ditutup saat offline; shift terbuka > 24 jam ditandai di dashboard |

**Transaksi**

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| K-06 | P0 | Menu grid per kategori + pencarian, tombol besar | Produk tanpa modifier wajib masuk keranjang dengan 1 ketukan |
| K-07 | P0 | Pilih modifier sesuai aturan grup, catatan per item, ubah qty/hapus item | — |
| K-08 | P0 | Nama pelanggan / no antrean opsional, tercetak di struk | — |
| K-09 | P0 | Diskon manual (nominal/%) per item atau per transaksi, wajib alasan | Hanya staf dengan izin diskon; staf lain diminta PIN manager |
| K-10 | P0 | Pajak & pembulatan otomatis sesuai setting outlet | Total sama persis di app, struk, dan laporan server |
| K-11 | P0 | Bayar: Tunai (tombol uang pas & nominal cepat, hitung kembalian), QRIS statis (tampilkan QR outlet, kasir konfirmasi manual), Transfer/E-wallet (konfirmasi manual) | Transaksi sudah tersimpan di HP sebelum layar "Berhasil" muncul |
| K-12 | P0 | Nomor struk unik tanpa online: `{KODE OUTLET}-{NO DEVICE}-{YYMMDD}-{URUT}` | Tidak ada nomor ganda walau semua HP offline |
| K-13 | P0 | Cetak struk thermal Bluetooth 58/80 mm (ESC/POS) dengan auto-reconnect; bagikan struk (gambar/teks) lewat menu share HP, mis. ke WhatsApp (gratis); cetak ulang dari riwayat | Printer gagal tidak membatalkan transaksi |
| K-14 | P0 | Void dalam shift berjalan, wajib alasan. Opsi per outlet: butuh PIN manager (default aktif untuk Outlet, nonaktif untuk Keliling karena rider bekerja sendiri). Transaksi tidak pernah dihapus | Void membalik stamp yang didapat & mengembalikan stamp yang ditukar; semua void muncul di laporan |
| K-15 | P0 | Riwayat transaksi di HP (shift berjalan + 7 hari) | — |
| K-16 | P1 | Open bill / simpan pesanan (outlet) | — |
| K-17 | P1 | Split payment (mis. tunai + QRIS) | — |
| K-18 | P1 | QRIS dinamis via payment gateway (butuh online, auto-konfirmasi, ada biaya per transaksi) | — |
| K-19 | P1 | Kontrol stok per shift: stok bawaan saat buka, sisa saat tutup; sistem hitung pemakaian dari penjualan × resep dan tampilkan selisih | — |
| K-20 | P1 | Simpan koordinat GPS saat transaksi (jika izin diberikan; tidak menghambat transaksi) | — |

**Member & stamp**

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| K-21 | P0 | Identifikasi member: scan QR kartu atau ketik no HP. Online → tampil nama & saldo stamp. Offline → transaksi ditautkan ke kode/no HP tersebut, server mencocokkan saat sync | Stamp tetap masuk setelah sync; no HP dinormalisasi ke format +62 |
| K-22 | P0 | Daftar member baru dari kasir (nama + no HP), juga saat offline. Setelah daftar, app menampilkan **QR aktivasi kartu** di layar dan mencetaknya di struk | No HP yang ternyata sudah terdaftar digabung ke member lama, stamp tidak hilang |
| K-23 | P0 | Estimasi stamp yang didapat tampil di layar & struk ("+2 stamp"); nilai final ditetapkan server | — |
| K-24 | P0 | Tukar reward hanya saat online: server cek saldo & potong stamp secara atomik; item reward berharga Rp0 (modifier berbayar tetap dibayar) | Saat offline tombol nonaktif dengan pesan jelas; dua HP tidak bisa menukar stamp yang sama |
| K-25 | P0 | Terbitkan ulang QR aktivasi untuk member yang ganti HP atau data browsernya terhapus: cari lewat no HP (butuh online), kasir mencocokkan nama, lalu tampilkan/cetak QR baru | QR lama otomatis tidak berlaku; tercatat di audit log |

**Sync**

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| K-26 | P0 | Auto-sync: setelah transaksi selesai (jika online), saat koneksi kembali, tiap 5 menit selama app terbuka, best-effort ±15 menit saat app di background (batasan Android), plus tombol "Sync sekarang" | Lihat §9 |
| K-27 | P0 | Indikator selalu terlihat: Online/Offline, jumlah data menunggu, waktu sync terakhir; daftar data yang ditolak server beserta alasannya | — |
| K-28 | P0 | Peringatan jika ada data pending > 24 jam; logout device/aktivasi ulang diblokir selama masih ada data pending | — |
| K-29 | P0 | Peringatan jika jam HP beda > 5 menit dari server | — |

### 8.4 Web Dashboard

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| W-01 | P0 | Dashboard hari ini: omzet, jumlah transaksi & item terjual, rata-rata per transaksi, per outlet/gerobak, per metode bayar, produk terlaris, penjualan per jam, status device (sync terakhir, data pending) | Ada keterangan "data s/d sync terakhir" per device |
| W-02 | P0 | Laporan dengan filter tanggal/outlet/staf: penjualan, per produk & modifier, per kategori, per metode bayar, per staf, shift (kas & selisih), void & diskon; ekspor Excel/CSV | Total laporan = total dashboard untuk periode yang sama |
| W-03 | P0 | Pengaturan stamp (lihat §8.5) | — |
| W-04 | P0 | Member: cari, riwayat stamp, koreksi stamp manual (wajib alasan), terbitkan ulang QR aktivasi, blokir | Koreksi & terbit ulang QR tercatat di audit log |
| W-05 | P0 | Audit log: perubahan harga/menu, void, diskon, koreksi stamp, terbit ulang QR aktivasi, perubahan staf/device | Tidak bisa diubah/dihapus dari UI |
| W-06 | P1 | Laporan stok & selisih per shift; posisi terakhir gerobak di peta (OpenStreetMap, gratis) | — |

### 8.5 Loyalty: Stamp Digital

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| L-01 | P0 | Aturan: jumlah stamp untuk 1 reward (default 10); produk/kategori yang dapat stamp; 1 stamp per item (qty dihitung); batas stamp per member per hari (default 10, anti-penyalahgunaan) | — |
| L-02 | P0 | Reward = 1 item gratis dari daftar produk pilihan owner | Item reward tidak menghasilkan stamp |
| L-03 | P0 | Buku besar stamp (EARN, REDEEM, REVERSAL, ADJUST, EXPIRE); saldo = jumlah buku besar | Saldo bisa dihitung ulang dari buku besar kapan saja; saldo negatif (akibat void setelah tukar) ditandai untuk ditinjau owner |
| L-04 | P0 | Kedaluwarsa opsional: stamp hangus jika member tidak bertransaksi selama N bulan (default: tidak hangus) | Web loyalty menampilkan tanggal hangus |
| L-05 | P0 | Stamp final dihitung server memakai aturan yang berlaku saat transaksi terjadi (bukan saat sync) | Transaksi offline lama tidak terpengaruh perubahan aturan |
| L-06 | P1 | Klaim stamp lewat QR di struk (untuk pembeli yang belum jadi member) | Sekali klaim per struk, maks 7 hari |
| L-07 | P1 | Bonus stamp: ulang tahun, double stamp di hari/jam tertentu | — |
| L-08 | P2 | Google/Apple Wallet, tier member, QR dinamis anti-screenshot; dompet kartu lintas brand setelah SaaS | — |

### 8.6 Web Loyalty Card (Pelanggan)

| ID | P | Kebutuhan | Kriteria penerimaan |
|---|---|---|---|
| C-01 | P0 | Satu alamat web (mis. `member.{domain}`) dengan nama, logo & warna dari profil usaha | — |
| C-02 | P0 | Aktivasi kartu tanpa OTP/password: pelanggan scan QR aktivasi (layar kasir atau struk) → kartu langsung tampil dan tersimpan di browser itu (sesi panjang, mis. 1 tahun) | QR sekali pakai, berlaku 7 hari; jika HP kasir belum sync, halaman menampilkan "kartu sedang diproses, buka lagi nanti" |
| C-03 | P0 | Kartu digital: nama, QR member besar, kode member, grid stamp (mis. 7/10), "3 stamp lagi untuk 1 minuman gratis", reward tersedia | Kartu terakhir tetap tampil saat sinyal lemah (cache PWA) |
| C-04 | P0 | Riwayat stamp: tanggal, outlet, +/− | — |
| C-05 | P0 | Ganti HP / data browser terhapus: minta QR aktivasi baru ke kasir (K-25) | Stamp tetap aman karena terikat ke no HP, bukan ke browser |
| C-06 | P0 | Persetujuan S&K + kebijakan privasi saat aktivasi; pelanggan bisa menghapus akun | Hapus akun = data pribadi dianonimkan, transaksi tetap ada tanpa identitas |
| C-07 | P0 | PWA: setelah aktivasi, pelanggan diarahkan ke "Tambahkan ke layar utama" | — |
| C-08 | P1 | Login dengan no HP + PIN, supaya kartu bisa dibuka di HP lain tanpa ke kasir | PIN salah 5× → kunci 15 menit + rate-limit per IP |
| C-09 | P1 | Klaim stamp dari QR struk (L-06); info promo usaha | — |
| C-10 | P2 | Gerobak terdekat (real-time), pre-order | — |

## 9. Offline & Sinkronisasi

**Prinsip**
1. HP adalah sumber kebenaran untuk transaksi yang dibuatnya. Server adalah sumber kebenaran untuk master data & saldo stamp.
2. Semua data transaksi memakai UUID yang dibuat di HP, jadi kirim ulang selalu aman (idempotent).
3. Transaksi tidak diedit setelah selesai; koreksi hanya lewat void.
4. Nama & harga disalin ke detail transaksi, jadi perubahan menu tidak mengubah transaksi lama.
5. Setiap siklus sync: kirim (push) dulu, lalu ambil (pull).

**Alur**
```
App Kasir                                       Server (Django + SQL Server)
transaksi → SQLite + outbox (1 transaksi lokal)
push: POST /api/v1/sync/push (≤100 event)  ──►  simpan; UUID yang sudah ada dilewati
                                           ◄──  daftar diterima / ditolak + alasan
pull: GET /api/v1/sync/master?version=…    ──►  jika versi master berubah: kirim ulang seluruh
                                           ◄──  master data outlet (menu, harga, staf, setting,
                                                aturan stamp) + versi baru
```

**Aturan konflik**

| Situasi | Aturan |
|---|---|
| Owner ubah menu/harga saat HP offline | Server menang; transaksi offline tetap memakai harga saat transaksi |
| Produk dinonaktifkan tapi terjual offline | Transaksi tetap diterima |
| No HP member yang sama didaftarkan dari 2 HP / sudah ada | Server menggabungkan ke 1 member (no HP unik) |
| Member didaftarkan / QR aktivasi dibuat saat offline | QR baru bisa dipakai setelah HP kasir sync (berlaku 7 hari) |
| Event terkirim dua kali (retry) | Dilewati berdasarkan UUID |
| Tukar reward | Hanya online, atomik di server, sehingga tidak ada tukar ganda |
| Staf dinonaktifkan saat HP offline | Masih bisa login sampai HP sync berikutnya (risiko diterima) |
| Device dicabut (mis. HP hilang) | Token ditolak dan data pending di HP itu tidak diterima. Pastikan sync dulu sebelum mencabut |
| HP rusak/hilang sebelum sync | Data yang belum terkirim hilang. Mitigasi: sync agresif, peringatan pending, dashboard device pending |
| Jam HP salah | Simpan waktu HP & waktu diterima server; peringatan di app (K-29) |
| App versi lama | Push dari versi lama tetap diterima (data tidak hilang); versi terlalu lama wajib update sebelum buka shift baru |

**Data yang disimpan di HP**
- Master data untuk outlet-nya: menu, modifier, harga, staf (hash PIN), setting, aturan stamp.
- Transaksi: yang belum terkirim + 7 hari terakhir (lalu dibersihkan otomatis).
- Tidak ada cache daftar member. Identifikasi offline ditautkan lewat kode/no HP dan diselesaikan server saat sync. Data member baru hanya ada di antrean kirim sampai terkirim.

**Kriteria penerimaan sync (P0)**
- Given HP offline dan membuat 200 transaksi, When HP online, Then semuanya muncul di dashboard ≤ 5 menit tanpa duplikat.
- Given koneksi putus di tengah push, When sync diulang, Then tidak ada transaksi ganda maupun hilang.
- Given app ditutup paksa/HP mati tepat setelah bayar, When app dibuka lagi, Then transaksi ada dan masih antre sync.
- Given owner mengubah harga, When HP sync, Then harga baru hanya berlaku untuk transaksi berikutnya.
- Given 10.000 transaksi belum terkirim, Then app tetap lancar (simpan transaksi < 300 ms).

## 10. Arsitektur & Tech Stack

```
App Kasir (Flutter + SQLite) ──┐
Browser Owner/Manager ─────────┼─HTTPS─► Django: API (Ninja) · Dashboard · Loyalty Web ──► SQL Server Express
HP Pelanggan (PWA) ────────────┘                     └──► Payment gateway (P1, opsional)
```

| Lapisan | Pilihan | Alasan |
|---|---|---|
| App kasir | Flutter (Android dulu) + SQLite (`sqflite`) | Offline-first matang; plugin printer ESC/POS & scan QR tersedia; iOS bisa menyusul dari kode yang sama |
| Backend | Python 3.14 · Django 5.2 LTS (≥ 5.2.8) + Django Ninja | Sesuai skill (Python). Django sudah termasuk ORM + migrasi, auth, admin, dan template, jadi paling sedikit kode untuk aplikasi yang banyak CRUD & laporan. Django Ninja bergaya FastAPI (Pydantic) untuk API mobile |
| Web dashboard & loyalty | Django templates + HTMX | Satu aplikasi, satu deploy, tanpa SPA terpisah; ringan di HP murah |
| Admin internal | Django Admin | Untuk developer/perawatan saja, bukan untuk owner |
| Database | Microsoft SQL Server 2025 Express (database maks 50 GB; versi 2022 hanya 10 GB) via `mssql-django`, backend resmi dari Microsoft (mendukung Django 5.2–6.1, SQL Server 2017–2025) | Sesuai keputusan; Express gratis dan cukup untuk satu usaha. Kode tidak memakai fitur khusus database, jadi nanti bisa pindah ke PostgreSQL atau edisi lain tanpa tulis ulang |
| Job terjadwal & backup | Cron + Django management command; backup database lewat `sqlcmd` | SQL Server Express tidak punya SQL Server Agent, jadi job & backup dijadwalkan dari cron |
| Hosting | 1 VPS Linux RAM ≥ 4 GB (Jakarta/Singapura) + Docker Compose: Django (Gunicorn), SQL Server Express, Caddy (HTTPS gratis) | SQL Server di Linux butuh RAM minimal 2 GB. Alternatif lebih hemat: server sendiri + Cloudflare Tunnel (lihat Q2) |

Kenapa bukan FastAPI: bagus untuk API, tapi admin, auth, template, dan migrasi harus dirakit sendiri. Hasilnya lebih banyak kode untuk aplikasi yang didominasi CRUD & dashboard.

**Keputusan teknis kunci**

| Keputusan | Alasan |
|---|---|
| Siap SaaS: tabel `Tenant` + `tenant_id` di semua data usaha, filter tenant otomatis, setting usaha disimpan di database (bukan di kode) | Jadi SaaS nanti cukup menambah modul (A-05), bukan membongkar struktur data |
| Tidak memakai fitur khusus database: trigger, constraint bersyarat (filtered index), fungsi zona waktu database | Menghindari keterbatasan `mssql-django` dan menjaga portabilitas SQL Server ↔ PostgreSQL |
| UUID dibuat di HP; unique constraint pada UUID, event yang sudah ada dilewati | Kirim ulang aman tanpa koordinasi ID; berjalan sama di SQL Server maupun PostgreSQL |
| Outbox SQLite ditulis dalam transaksi lokal yang sama dengan penjualan | Tidak ada penjualan yang tersimpan tanpa masuk antrean sync |
| Master data memakai satu nomor versi; jika berubah, HP mengambil ulang seluruh master data outletnya | Data master kecil (menu, staf, setting), jadi jauh lebih sederhana daripada sync per baris dan tidak ada perubahan yang terlewat. Jika data master membesar (ribuan produk), baru ganti ke sync per baris |
| Penjualan menyimpan tanggal bisnis & jam lokal outlet saat dibuat; waktu lain disimpan dalam UTC | Laporan per hari/jam tidak bergantung pada fungsi zona waktu database (terbatas di `mssql-django`) |
| Uang disimpan sebagai integer Rupiah (`bigint`), pembulatan pajak half-up ke Rp1 | Hindari error pembulatan desimal |
| Auth: token device (bisa dicabut) untuk API mobile, session untuk dashboard, token aktivasi sekali pakai + sesi panjang untuk kartu pelanggan | Tanpa OTP berbayar |

**Biaya berjalan**

| Komponen | Biaya | Catatan |
|---|---|---|
| Django, Flutter, Docker, Caddy | Gratis | Open source |
| SQL Server 2025 Express | Gratis | Batas: database 50 GB, 4 core, buffer ±1,4 GB; cukup untuk satu usaha |
| HTTPS | Gratis | Sertifikat Let's Encrypt otomatis lewat Caddy |
| Aktivasi kartu pelanggan | Gratis | QR dari kasir, tanpa OTP |
| Kirim struk ke pelanggan | Gratis | Lewat menu share HP (WhatsApp milik kasir) |
| Distribusi app kasir | Gratis | APK dibagikan langsung; Play Store opsional (sekali bayar US$25) |
| Crash reporting | Gratis | Tier gratis, mis. Firebase Crashlytics |
| Peta posisi gerobak (P1) | Gratis | OpenStreetMap |
| VPS Linux RAM 4 GB | ± Rp150–400 ribu/bulan | Tergantung provider; Rp0 jika pakai server sendiri + Cloudflare Tunnel |
| Domain | ± ratusan ribu Rupiah/tahun | Tergantung ekstensi domain |
| QRIS dinamis (P1, opsional) | Biaya per transaksi | Hanya jika diaktifkan |

## 11. Model Data (garis besar)

Semua tabel di bawah, kecuali `Tenant`, punya `tenant_id`.

- **Usaha:** Tenant (profil usaha, nomor versi master data)
- **Akses:** User (peran, hash PIN, outlet yang diizinkan, izin diskon), AuditLog
- **Outlet & device:** Outlet (tipe Outlet/Keliling, zona waktu, pajak, QRIS), Device (nomor, token, sync terakhir, pending)
- **Menu:** Category, Product, ModifierGroup, ModifierOption, ketersediaan produk per outlet
- **Penjualan:** Shift, CashMovement, Sale (+ tanggal bisnis & jam lokal), SaleItem (+ snapshot modifier), Payment, Void
- **Loyalty:** Member (kode, nama, no HP unik, cache saldo, persetujuan), CardActivation (token sekali pakai), StampRule (berversi), StampLedger
- **P1:** StockItem, Recipe, ShiftStockCount
- **P2 (SaaS):** Plan, Subscription, SubscriptionPayment

## 12. Kebutuhan Non-Fungsional

| Area | Target |
|---|---|
| Performa app | Simpan transaksi < 300 ms; buka app sampai siap jualan < 3 detik; jalan di Android 8+ dengan RAM 2 GB |
| Performa server | p95 API < 500 ms; push 100 event < 2 detik |
| Ketersediaan | Server ≥ 99%/bulan (1 VPS); kasir tetap jalan walau server mati (offline-first) |
| Kapasitas desain | 1 usaha · hingga 50 device · 10 ribu transaksi/hari di 1 VPS |
| Keamanan | HTTPS wajib; token device bisa dicabut; password, PIN staf & token aktivasi kartu di-hash; rate-limit login; audit log |
| Privasi (UU PDP) | Persetujuan member, data minimal (nama + no HP), hapus/anonimkan atas permintaan. Pemilik usaha adalah pengendali data, jadi perlu kebijakan privasi sederhana di web loyalty |
| Backup | Backup harian lewat cron + `sqlcmd` ke penyimpanan terpisah (retensi 30 hari), uji restore tiap bulan. Setelah restore, HP bisa diminta kirim ulang transaksi 7 hari terakhir (aman karena idempotent) |
| Kompatibilitas versi | Server menerima push dari versi app lama; versi yang terlalu lama wajib update sebelum buka shift baru |
| Monitoring | Crash & error reporting tier gratis; metrik sync per device |
| Kondisi lapangan | Tombol besar, kontras tinggi (terbaca di bawah matahari), bisa satu tangan, hemat baterai & kuota (sync seperlunya, batch) |
| Bahasa & format | Bahasa Indonesia, Rupiah, zona waktu WIB/WITA/WIT |

## 13. Metrik Keberhasilan (target awal, dikalibrasi setelah pilot)

**Leading (2–4 minggu)**
- Sync: ≥ 99% transaksi masuk server ≤ 5 menit setelah HP online; 0 transaksi ganda/hilang (jumlah transaksi per hari yang dilaporkan HP dicocokkan dengan server).
- Kecepatan: median durasi transaksi ≤ 30 detik (diukur di app).
- Loyalty: ≥ 15% transaksi terhubung member di bulan 1; ≥ 50% member baru membuka kartu web dalam 7 hari.
- Stabilitas: crash-free sessions ≥ 99,5%.

**Lagging (1–6 bulan)**
- ≥ 25% transaksi terhubung member di bulan 3; ≥ 40% member kembali dalam 30 hari.
- Selisih kas shift rata-rata turun dibanding sebelum pakai KaffePOS (baseline dari pilot).
- Biaya berjalan bulanan tetap sesuai rincian §10.

## 14. Risiko & Mitigasi

| Risiko | Mitigasi |
|---|---|
| HP hilang/rusak sebelum sync | Sync agresif, peringatan pending, dashboard device pending |
| Rider jual tanpa mencatat | Rekap kas per shift (P0), kontrol stok cup (P1), audit void & diskon |
| Kasir memakai kartu member sendiri untuk pembeli lain | Batas stamp per member per hari, QR dari HP pelanggan, laporan member tidak wajar (P1) |
| Tanpa OTP, no HP pelanggan tidak terverifikasi | Kartu hanya bisa diaktifkan lewat QR dari kasir (tatap muka); terbit ulang QR wajib online & cocokkan nama, tercatat di audit log |
| Kartu web hilang (data browser terhapus, atau QR terbuka di browser bawaan aplikasi scanner) | Stamp tetap aman (terikat ke no HP); minta QR baru ke kasir; login no HP + PIN di P1 |
| Batas SQL Server Express (ukuran database, CPU/RAM) | Cukup untuk satu usaha; pantau ukuran database tiap bulan; pindah ke PostgreSQL atau edisi berbayar bila mendekati batas (kode portabel) |
| `mssql-django` tertinggal dari rilis Django terbaru | Pakai Django LTS yang didukung; naik versi setelah `mssql-django` mendukungnya |
| Printer Bluetooth beragam merek | Uji 3–5 printer 58/80 mm paling umum; buat daftar printer yang didukung |
| Data bocor antar usaha saat nanti jadi SaaS | Filter tenant + test 2 tenant sejak sekarang (A-02); Row-Level Security saat SaaS |
| Screenshot QR member dipakai orang lain | Risiko kecil di MVP; QR dinamis (P2) jika terjadi |
| PIN 6 digit staf di HP bisa dibobol jika HP dibongkar | PIN hanya untuk atribusi kasir; cabut device jika hilang; enkripsi DB lokal (P1) |

## 15. Asumsi

- Dipakai satu usaha kopi (aplikasi custom), dengan banyak outlet/gerobak.
- Android 8+ dulu; app kasir iOS di P2.
- 1 HP = 1 outlet/gerobak = 1 shift aktif = 1 kas.
- Rupiah & Bahasa Indonesia saja di v1.
- Pembayaran non-tunai dikonfirmasi manual oleh kasir di MVP.
- Member hanya didaftarkan lewat kasir.
- Tidak ada layanan berbayar per pemakaian (OTP, SMS, WhatsApp API, email).
- App kasir dibagikan sebagai APK langsung, tanpa Play Store.
- Harga sama untuk semua outlet di MVP.
- SQL Server dipakai sementara; kode dijaga portabel ke PostgreSQL.
- Pajak (PBJT) opsional per outlet, karena banyak kopi keliling tidak memungut.

## 16. Pertanyaan Terbuka

| # | Pertanyaan | Dijawab oleh | Blocking? |
|---|---|---|---|
| Q1 | Nama brand & skala usaha (jumlah outlet/gerobak sekarang dan target 1 tahun)? | Owner produk | Ya, untuk sizing & branding |
| Q2 | Hosting: VPS (± Rp150–400 ribu/bulan) atau server milik sendiri + Cloudflare Tunnel (gratis, tapi bergantung listrik & internet di lokasi)? | Owner produk | Ya, sebelum deploy staging |
| Q3 | Kontrol stok cup per shift cukup P1, atau wajib MVP? | Owner produk + pemilik usaha | Tidak |
| Q4 | Perlu QRIS dinamis (ada biaya per transaksi), atau cukup QRIS statis? | Owner produk | Tidak |
| Q5 | Domain untuk dashboard & kartu member? | Owner produk | Tidak |
| Q6 | Gerobak/outlet mana yang jadi pilot (2–3 gerobak + 1 outlet)? | Owner produk | Ya, untuk validasi |
| Q7 | Sudah punya lisensi SQL Server berbayar, atau pakai Express (gratis)? | Owner produk | Tidak |
| Q8 | Kebijakan privasi & S&K member? Perlu integrasi pelaporan pajak daerah untuk outlet tertentu? | Owner produk + legal | Ya sebelum go-live (privasi); pajak = kandidat P2 |

## 17. Milestone

| Milestone | Isi |
|---|---|
| M0 Fondasi | Proyek Django + SQL Server Express (Docker), model tenant/user/outlet/device, deploy staging |
| M1 Master data & API sync | Dashboard menu/outlet/staf/device; endpoint aktivasi device, push, pull master + test idempotensi & test 2 tenant |
| M2 App Kasir offline | Flutter + SQLite, transaksi, shift & kas, printer, outbox & auto-sync |
| M3 Loyalty | Stamp di kasir & server, QR aktivasi kartu, web Loyalty Card (PWA) |
| M4 Laporan | Dashboard, laporan & ekspor, audit log |
| M5 Pilot | 2–3 gerobak + 1 outlet selama 2–4 minggu → perbaikan → rilis APK |

Estimasi kasar: ±3–4 bulan sampai pilot untuk 2 developer (1 Django, 1 Flutter), atau ±6–8 bulan jika dikerjakan 1 orang. Lebih cepat dari v0.1 karena tanpa modul SaaS & OTP. Angka ini dihitung ulang setelah desain teknis.

Dependensi eksternal: VPS atau server sendiri, domain, dan 2–3 printer thermal Bluetooth untuk uji.
