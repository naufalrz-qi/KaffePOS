# Status Pengembangan KaffePOS

Per 26 November 2026. Ringkasan untuk pemilik proyek: apa yang sudah jadi, apa yang belum, dan kekurangan yang perlu diketahui.
Rincian kebutuhan ada di [PRD.md](PRD.md); rincian teknis di [DESAIN-TEKNIS.md](DESAIN-TEKNIS.md).

## 1. Gambaran singkat

KaffePOS adalah POS untuk satu usaha kopi (gerobak keliling dan outlet), dibangun siap dijadikan SaaS.

| Bagian | Teknologi | Status |
|---|---|---|
| Server + API sync | Python/Django, SQL Server Express | Jalan di PC dev (`127.0.0.1:8010`), belum di-deploy |
| Dashboard web (owner/manager) | Django templates + Pico.css | Jalan di PC dev |
| App kasir Android | Flutter, SQLite (offline-first) | Jalan di HP uji (itel, Android 15) lewat kabel USB |
| Kartu member web (pelanggan) | — | Belum dibuat (M3) |

## 2. Posisi milestone

| Milestone | Isi | Status |
|---|---|---|
| M0 Fondasi | Django + SQL Server, model usaha/user/outlet/device | ✅ Selesai, kecuali **deploy staging** (belum ada server) |
| M1 Master data & API sync | Dashboard menu/outlet/staf/device; aktivasi, push, pull + test | ✅ Selesai |
| M2 App kasir offline | Transaksi, shift & kas, printer, outbox & auto-sync | ✅ Selesai; **printer belum diuji dengan alat asli** |
| M3 Loyalty | Member, stamp, kartu web (PWA) | ⏳ Belum dimulai |
| M4 Laporan | Beranda, laporan + Excel, audit log, akses manager | ✅ Selesai dikode & direview; 1 uji manual dari HP tersisa |
| M5 Pilot | 2–3 gerobak + 1 outlet, rilis APK | ⏳ Belum dimulai |

Urutan dikerjakan: M0 → M1 → M2 → M4 (M4 didahulukan dari M3 atas keputusan owner, supaya penjualan bisa dilihat dulu).

Angka saat ini: 51 commit di `main`; 111 test backend dan 61 test app lulus; `flutter analyze` bersih.

## 3. Yang sudah bisa dipakai

### Owner (dashboard web)
- Login username + password; profil usaha dan metode bayar aktif.
- Kelola outlet/gerobak (termasuk gambar QRIS statis, pajak, pembulatan), kategori, produk, modifier, staf (peran, PIN, outlet, izin diskon).
- Device: buat kode aktivasi (15 menit, sekali pakai), cabut HP yang hilang, lihat sync terakhir & data menunggu.
- **Beranda:** omzet, transaksi, item, rata-rata hari ini (per zona waktu outlet), per outlet, per metode bayar, per jam, 5 produk terlaris, status HP, peringatan HP/shift > 24 jam.
- **Laporan** dengan filter tanggal/outlet/staf: Penjualan, Produk, Shift (kas & selisih), Void & diskon; **unduh Excel** 12 sheet.
- **Audit log:** perubahan data master, harga, staf, device, profil usaha, void, dan diskon (beserta penyetuju). Tidak bisa diubah/dihapus.

### Manager
- Melihat beranda dan laporan **hanya untuk outlet yang ditugaskan**; tidak bisa membuka menu Kelola dan audit log.
- Menyetujui void dan diskon di HP kasir dengan PIN (bisa offline).

### Kasir / rider (app Android)
- Aktivasi HP sekali dengan kode; login nama + PIN (bisa offline).
- Buka shift dengan modal, kas masuk/keluar, tutup shift dengan hitung kas dan selisih; rekap bisa dicetak/dibagikan.
- Jualan: menu per kategori + cari, modifier wajib/opsional, catatan, diskon item/transaksi (wajib alasan), nama pelanggan, pajak & pembulatan otomatis.
- Bayar tunai (nominal cepat, kembalian), QRIS statis (gambar tampil), transfer, e-wallet.
- Nomor struk unik tanpa internet; struk dicetak (Bluetooth) atau dibagikan ke WhatsApp; riwayat 7 hari, cetak ulang, void.
- Tetap berjualan saat offline; sync otomatis saat online, status sync selalu terlihat, peringatan jam HP salah & data tertunda > 24 jam.
- Tampilan tema biru langit, ikon app sendiri.

### Developer
- `manage.py setup_tenant` membuat usaha + akun owner pertama; reset password owner dengan `manage.py changepassword`.
- Isolasi data antar-usaha dijaga dan dites (siap SaaS).

## 4. Yang belum dibuat

### M3 Loyalty (PRD P0, semuanya belum)
- Member: daftar dari kasir (juga offline), scan QR/ketik no HP, estimasi stamp di struk (K-21…K-25).
- Aturan stamp, buku besar stamp, tukar reward online, kedaluwarsa (L-01…L-05).
- Kartu member web/PWA untuk pelanggan, aktivasi lewat QR dari kasir, S&K & privasi (C-01…C-07).
- Halaman dashboard: pengaturan stamp dan member (W-03, W-04); audit koreksi stamp.

### M5 Pilot & rilis
- **Server produksi:** belum ada Docker Compose/Caddy/HTTPS, belum ada folder `deploy/`, belum ada backup harian & uji restore (DESAIN-TEKNIS §10).
- **Rilis APK:** belum ada keystore rilis (APK masih ditandatangani kunci debug), URL produksi belum diisi, belum di Play Store.
- Uji lapangan di 2–3 gerobak + 1 outlet selama 2–4 minggu.

### Fitur P1 / nanti (sengaja ditunda di PRD)
- Harga beda per outlet, resep & kontrol stok cup per shift (M-07, M-08, K-19, W-06).
- Open bill, split payment, QRIS dinamis, GPS transaksi (K-16…K-20).
- Tutup paksa shift dari dashboard (sekarang hanya peringatan), foto produk.
- Modul SaaS (registrasi usaha, paket, tagihan, super admin) — P2.

## 5. Kekurangan & hal yang belum terverifikasi

| Hal | Dampak | Langkah |
|---|---|---|
| Printer Bluetooth belum pernah diuji dengan printer asli; [printer.md](printer.md) masih kosong | Cetak struk bisa gagal/berantakan di lapangan | Uji 2–3 printer 58/80 mm sebelum pilot |
| Sync otomatis di latar belakang (WorkManager) dan pemicu saat sinyal kembali belum diuji di HP | Data mungkin baru terkirim saat app dibuka | Uji mode pesawat di HP |
| Uji diskon dari HP → nama manager penyetuju di audit log belum dilakukan | Hanya terbukti lewat test otomatis | Build ulang app, 1 transaksi diskon |
| Peringatan jam HP salah belum diuji di HP | — | Uji dengan jam HP diubah |
| Belum ada server online; HP terhubung ke PC lewat kabel (`adb reverse`) | Belum bisa dipakai di jalan | Tentukan hosting & domain (PRD Q2, Q5), lalu deploy |
| APK ditandatangani kunci debug | Update APK harus dibuat di PC yang sama | Buat keystore rilis di M5 |
| Pilihan staf di filter laporan menampilkan username, bukan nama | Kosmetik | Perbaikan kecil |
| Audit log hanya mencatat perubahan setelah fitur M4 dipasang | Riwayat lama tidak ada | — |
| Tanda `unknown_approver` bisa muncul dua kali pada satu penjualan | Kosmetik | — |
| Satu HP uji (itel, Android 15) | Perilaku di HP/Android lain belum dicek | Uji di 1–2 HP lain saat pilot |

## 6. Pertanyaan terbuka untuk owner (PRD §16)

| # | Pertanyaan | Kenapa penting |
|---|---|---|
| Q1 | Nama brand & skala usaha (outlet/gerobak sekarang dan target 1 tahun) | Branding & ukuran server |
| Q2 | Hosting: VPS atau server sendiri + Cloudflare Tunnel | **Menghalangi deploy** |
| Q3 | Kontrol stok cup: cukup P1 atau wajib sebelum pilot | Ruang lingkup |
| Q4 | QRIS dinamis (ada biaya) atau cukup statis | Ruang lingkup |
| Q5 | Domain untuk dashboard & kartu member | **Menghalangi deploy & M3** |
| Q6 | Gerobak/outlet mana yang jadi pilot | **Menghalangi M5** |
| Q7 | Lisensi SQL Server berbayar atau Express | Kapasitas (Express maks 50 GB) |
| Q8 | Kebijakan privasi & S&K member; pajak daerah | **Wajib sebelum go-live M3** |

## 7. Saran urutan berikutnya

1. Tuntaskan sisa M4: uji diskon dari HP, perbaiki label staf.
2. Jawab Q2 & Q5, lalu deploy staging (server online + HTTPS) — tanpa ini app belum bisa dipakai di luar.
3. Uji printer asli.
4. M3 Loyalty (butuh jawaban Q8).
5. M5 pilot: keystore rilis, uji lapangan, perbaikan.

## 8. Dokumen terkait

- [PRD.md](PRD.md) — kebutuhan produk.
- [DESAIN-TEKNIS.md](DESAIN-TEKNIS.md) — arsitektur, skema, API sync, deploy.
- [printer.md](printer.md) — daftar printer teruji.
- `mobile/README.md` — cara menjalankan test, app di HP, dan build APK.
- `docs/superpowers/specs/` dan `docs/superpowers/plans/` — desain & rencana per milestone.
