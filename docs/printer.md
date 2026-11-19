# Printer thermal yang didukung

Diuji dengan app KaffePOS Kasir: Bluetooth Classic SPP lewat `mobile/android/.../MainActivity.kt`, perintah ESC/POS
dari `mobile/lib/print/escpos.dart`. Printer harus di-pair dulu di pengaturan Bluetooth HP.

Cara uji:
1. Menu → Printer → pilih printer → pilih lebar → **Cetak tes**.
2. Jual 1 transaksi dengan cetak otomatis aktif.
3. Matikan printer, jual 1 transaksi (harus muncul pesan gagal, transaksi tetap tersimpan),
   nyalakan lagi → Riwayat → **Cetak**.

| Printer (merk/model) | Lebar | HP & versi Android | Teks rapi & potong | QR (GS ( k) bisa di-scan | Sambung ulang | Catatan |
|---|---|---|---|---|---|---|
