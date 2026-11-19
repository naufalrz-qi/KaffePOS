# KaffePOS Kasir (Flutter)

App kasir Android offline-first.
- Desain: `docs/DESAIN-TEKNIS.md` §6.
- Rencana: `docs/superpowers/plans/2026-11-19-m2-app-kasir.md`.

## Prasyarat
- Flutter stable di PATH (`D:\dev\flutter\bin`).
- Android SDK (lewat Android Studio).
- HP Android 8+ dengan USB debugging aktif.

## Test (tanpa HP)
```powershell
flutter test
flutter analyze
```
Run pertama mengunduh `sqlite3.dll` untuk test, jadi butuh internet.

## Jalankan di HP terhadap server dev
1. Jalankan backend dari folder `backend`:
   ```powershell
   .\.venv\Scripts\python.exe manage.py runserver 127.0.0.1:8010
   ```
2. Hubungkan port HP ke PC (ulangi setiap kabel dicabut):
   ```powershell
   adb reverse tcp:8010 tcp:8010
   ```
3. Jalankan app. App memakai `API_BASE` bawaan `http://127.0.0.1:8010/api/v1`:
   ```powershell
   flutter run
   ```

## Build APK
```powershell
flutter build apk --release --dart-define=API_BASE=https://app.<domain>/api/v1
```

Catatan:
- Build rilis hanya mengizinkan HTTPS.
- Keystore rilis dan URL produksi disiapkan di M5. Sampai saat itu, APK rilis ditandatangani kunci debug, sehingga update APK harus dibangun di PC yang sama.

## Printer
Daftar printer yang sudah diuji ada di `docs/printer.md`.
